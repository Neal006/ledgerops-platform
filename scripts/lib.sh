#!/usr/bin/env bash
# Shared helpers for deploy.sh / rollback.sh. Resource names follow the Terraform convention
# ledgerops-<env>-<component>, so no Terraform state access is needed at deploy time.
set -euo pipefail

log() { printf '\033[1;34m[%s]\033[0m %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }
die() { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

resolve_env() {
  ENV_NAME="${1:?usage: <staging|prod-in|prod-ae>}"
  case "$ENV_NAME" in
    staging) AWS_REGION=ap-south-1;   API_URL="${API_URL:-https://ledger.staging.example.com}" ;;
    prod-in) AWS_REGION=ap-south-1;   API_URL="${API_URL:-https://ledger.in.example.com}" ;;
    prod-ae) AWS_REGION=me-central-1; API_URL="${API_URL:-https://ledger.ae.example.com}" ;;
    *) die "unknown environment: $ENV_NAME" ;;
  esac
  export AWS_REGION AWS_DEFAULT_REGION="$AWS_REGION"
  CLUSTER="ledgerops-$ENV_NAME"
  SERVICE="ledgerops-$ENV_NAME-ledger-api"
  # shellcheck disable=SC2034  # consumed by the scripts that source this file
  API_FAMILY="$SERVICE" RECON_FAMILY="ledgerops-$ENV_NAME-recon-worker"
}

current_task_definition() {
  aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" \
    --query 'services[0].taskDefinition' --output text
}

# Clone a task definition with a new image for one container and register it as a new revision.
register_with_image() {
  local source_td="$1" container="$2" image="$3"
  aws ecs describe-task-definition --task-definition "$source_td" --include TAGS --output json \
    | jq --arg c "$container" --arg img "$image" --arg sha "${GIT_SHA:-unknown}" '
        .tags as $tags
        | .taskDefinition
        | .containerDefinitions |= map(if .name == $c then .image = $img else . end)
        | .containerDefinitions |= map(if .name == $c
            then .environment = ((.environment // []) | map(select(.name != "GIT_SHA")) + [{name: "GIT_SHA", value: $sha}])
            else . end)
        | del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities,
              .registeredAt, .registeredBy, .deregisteredAt)
        | if ($tags | length) > 0 then .tags = $tags else . end' \
    > "$TMPDIR_DEPLOY/td.json"
  aws ecs register-task-definition --cli-input-json "file://$TMPDIR_DEPLOY/td.json" \
    --query 'taskDefinition.taskDefinitionArn' --output text
}

wait_for_rollout() {
  local td="$1" deadline=$((SECONDS + ${ROLLOUT_TIMEOUT_S:-900})) state
  while (( SECONDS < deadline )); do
    state=$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" --output json \
      | jq -r --arg td "$td" '.services[0].deployments[] | select(.taskDefinition == $td) | .rolloutState' | head -1)
    case "$state" in
      COMPLETED) log "rollout of $td completed"; return 0 ;;
      FAILED)    log "rollout of $td FAILED (circuit breaker or alarm triggered ECS rollback)"; return 1 ;;
      "")        log "deployment for $td no longer present (rolled back)"; return 1 ;;
      *)         log "rollout state: $state"; sleep 15 ;;
    esac
  done
  log "timed out waiting for rollout"; return 1
}

smoke_test() {
  local attempt
  for attempt in 1 2 3 4 5; do
    if curl -fsS --max-time 5 "$API_URL/readyz" >/dev/null; then
      log "smoke test passed ($API_URL/readyz)"; return 0
    fi
    log "smoke test attempt $attempt failed"; sleep 6
  done
  return 1
}
