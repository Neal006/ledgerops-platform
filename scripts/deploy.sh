#!/usr/bin/env bash
# One-command deploy: ./scripts/deploy.sh <env> <image-tag>
#
#   1. Register new task definition revisions (API + recon job) pointing at the immutable image.
#   2. Run database migrations as a one-off Fargate task against the direct DB endpoint.
#      If migrations fail, nothing has been rolled out and production is untouched.
#   3. Roll the ECS service; ECS's circuit breaker and CloudWatch alarm rollback watch the rollout.
#   4. Smoke test through the public load balancer; on failure, roll back to the previous revision.
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

resolve_env "${1:-}"
TAG="${2:?usage: deploy.sh <env> <image-tag>}"
GIT_SHA="${GIT_SHA:-$TAG}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGISTRY="$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
TMPDIR_DEPLOY=$(mktemp -d); trap 'rm -rf "$TMPDIR_DEPLOY"' EXIT

# The UAE region receives images by ECR replication; wait until this tag has landed.
for repo in ledger-api recon-worker; do
  for i in $(seq 1 40); do
    aws ecr describe-images --repository-name "ledgerops/$repo" --image-ids imageTag="$TAG" >/dev/null 2>&1 && break
    (( i == 40 )) && die "image ledgerops/$repo:$TAG not found in $AWS_REGION"
    log "waiting for ledgerops/$repo:$TAG to replicate to $AWS_REGION"; sleep 15
  done
done

PREVIOUS_TD=$(current_task_definition)
log "env=$ENV_NAME region=$AWS_REGION current=$PREVIOUS_TD"

NEW_API_TD=$(register_with_image "$PREVIOUS_TD" app "$REGISTRY/ledgerops/ledger-api:$TAG")
NEW_RECON_TD=$(register_with_image "$RECON_FAMILY" job "$REGISTRY/ledgerops/recon-worker:$TAG")
log "registered $NEW_API_TD and $NEW_RECON_TD"

# --- Migrations ---------------------------------------------------------------------------------
NETWORK=$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" \
  --query 'services[0].networkConfiguration' --output json)
DIRECT_HOST=$(aws ecs describe-task-definition --task-definition "$NEW_API_TD" --output json \
  | jq -r '.taskDefinition.containerDefinitions[] | select(.name=="app") | .environment[] | select(.name=="DB_DIRECT_HOST") | .value')
[[ -n "$DIRECT_HOST" ]] || die "DB_DIRECT_HOST missing from task definition"

log "running migrations"
MIGRATION_TASK=$(aws ecs run-task --cluster "$CLUSTER" --task-definition "$NEW_API_TD" --launch-type FARGATE \
  --network-configuration "$NETWORK" --started-by "deploy-$GIT_SHA" \
  --overrides "$(jq -nc --arg host "$DIRECT_HOST" '{containerOverrides: [{name: "app", command: ["dist/migrate.js"], environment: [{name: "PGHOST", value: $host}]}]}')" \
  --query 'tasks[0].taskArn' --output text)
aws ecs wait tasks-stopped --cluster "$CLUSTER" --tasks "$MIGRATION_TASK"
EXIT_CODE=$(aws ecs describe-tasks --cluster "$CLUSTER" --tasks "$MIGRATION_TASK" \
  --query 'tasks[0].containers[?name==`app`].exitCode | [0]' --output text)
if [[ "$EXIT_CODE" != "0" ]]; then
  die "migrations failed (exit $EXIT_CODE). Service NOT updated. Logs: /ledgerops/$SERVICE, stream app/app/${MIGRATION_TASK##*/}"
fi
log "migrations applied"

# --- Roll out ------------------------------------------------------------------------------------
aws ecs update-service --cluster "$CLUSTER" --service "$SERVICE" --task-definition "$NEW_API_TD" >/dev/null
if ! wait_for_rollout "$NEW_API_TD"; then
  die "rollout failed; ECS has restored $PREVIOUS_TD"
fi

if ! smoke_test; then
  log "smoke test failed, rolling back to $PREVIOUS_TD"
  aws ecs update-service --cluster "$CLUSTER" --service "$SERVICE" --task-definition "$PREVIOUS_TD" >/dev/null
  wait_for_rollout "$PREVIOUS_TD" || true
  die "deploy of $TAG rolled back"
fi

log "deployed $TAG to $ENV_NAME"
echo "previous_task_definition=$PREVIOUS_TD" >> "${GITHUB_OUTPUT:-/dev/null}"
