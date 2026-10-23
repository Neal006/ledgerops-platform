#!/usr/bin/env bash
# One-command rollback: ./scripts/rollback.sh <env> [task-definition-revision]
# Without a revision, rolls back to the revision immediately before the one currently running.
# Schema is not rolled back: migrations are expand-only, so the previous app version still works.
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

resolve_env "${1:-}"
CURRENT=$(current_task_definition)
CURRENT_REV="${CURRENT##*:}"

if [[ -n "${2:-}" ]]; then
  TARGET="$API_FAMILY:$2"
else
  TARGET=$(aws ecs list-task-definitions --family-prefix "$API_FAMILY" --sort DESC --output json \
    | jq -r --argjson cur "$CURRENT_REV" '[.taskDefinitionArns[] | select((split(":") | last | tonumber) < $cur)][0] // empty')
  [[ -n "$TARGET" ]] || die "no revision older than $CURRENT_REV"
fi

IMAGE=$(aws ecs describe-task-definition --task-definition "$TARGET" \
  --query 'taskDefinition.containerDefinitions[?name==`app`].image | [0]' --output text)
log "rolling $SERVICE back: $CURRENT -> $TARGET ($IMAGE)"

aws ecs update-service --cluster "$CLUSTER" --service "$SERVICE" --task-definition "$TARGET" >/dev/null
wait_for_rollout "$(aws ecs describe-task-definition --task-definition "$TARGET" --query 'taskDefinition.taskDefinitionArn' --output text)"
smoke_test || die "rolled back, but smoke test still failing: escalate (docs/runbooks/high-error-rate.md)"
log "rollback complete"
