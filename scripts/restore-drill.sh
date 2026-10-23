#!/usr/bin/env bash
# Backup restore drill: ./scripts/restore-drill.sh <env> [minutes-ago]
#
# Restores the ledger database to a point in time on a throwaway instance, proves the restored
# copy is usable and internally consistent, records how long it took (our real RTO), then
# deletes the copy. A backup that has never been restored is a hope, not a backup.
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

resolve_env "${1:-}"
MINUTES_AGO="${2:-15}"
SOURCE="ledgerops-$ENV_NAME"
DRILL="$SOURCE-drill-$(date -u +%Y%m%d%H%M)"
RESTORE_TIME=$(date -u -d "-$MINUTES_AGO minutes" +%Y-%m-%dT%H:%M:%SZ)

cleanup() {
  log "deleting drill instance $DRILL"
  aws rds delete-db-instance --db-instance-identifier "$DRILL" --skip-final-snapshot \
    --delete-automated-backups >/dev/null 2>&1 || true
}
trap cleanup EXIT

SRC=$(aws rds describe-db-instances --db-instance-identifier "$SOURCE" --output json | jq '.DBInstances[0]')
LATEST=$(aws rds describe-db-instances --db-instance-identifier "$SOURCE" \
  --query 'DBInstances[0].LatestRestorableTime' --output text)
log "restoring $SOURCE to $RESTORE_TIME (latest restorable: $LATEST) as $DRILL"

started=$SECONDS
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier "$SOURCE" \
  --target-db-instance-identifier "$DRILL" \
  --restore-time "$RESTORE_TIME" \
  --db-instance-class db.t4g.medium \
  --no-multi-az --no-publicly-accessible --no-deletion-protection \
  --db-subnet-group-name "$(jq -r '.DBSubnetGroup.DBSubnetGroupName' <<<"$SRC")" \
  --vpc-security-group-ids "$(jq -r '.VpcSecurityGroups[0].VpcSecurityGroupId' <<<"$SRC")" \
  --db-parameter-group-name "$(jq -r '.DBParameterGroups[0].DBParameterGroupName' <<<"$SRC")" \
  --tags Key=purpose,Value=restore-drill >/dev/null

aws rds wait db-instance-available --db-instance-identifier "$DRILL"
RTO=$((SECONDS - started))
HOST=$(aws rds describe-db-instances --db-instance-identifier "$DRILL" \
  --query 'DBInstances[0].Endpoint.Address' --output text)
log "restore available after ${RTO}s at $HOST"

# Integrity checks run inside the VPC as a one-off task using the API image's credentials.
CHECK_SQL="SELECT
  (SELECT count(*) FROM schema_migrations) AS migrations,
  (SELECT count(*) FROM journal_entries) AS journal_entries,
  (SELECT count(*) FROM (SELECT journal_entry_id FROM postings GROUP BY journal_entry_id, currency
                          HAVING sum(amount_minor) <> 0) u) AS unbalanced_entries,
  (SELECT max(created_at) FROM journal_entries) AS newest_entry"

NETWORK=$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" \
  --query 'services[0].networkConfiguration' --output json)
SCRIPT="const {Client}=require('pg');const c=new Client();c.connect().then(()=>c.query(process.env.SQL)).then(r=>{console.log(JSON.stringify(r.rows[0]));process.exit(Number(r.rows[0].unbalanced_entries)===0?0:2)}).catch(e=>{console.error(e);process.exit(1)})"
TASK=$(aws ecs run-task --cluster "$CLUSTER" --task-definition "$(current_task_definition)" --launch-type FARGATE \
  --network-configuration "$NETWORK" --started-by restore-drill \
  --overrides "$(jq -nc --arg host "$HOST" --arg sql "$CHECK_SQL" --arg js "$SCRIPT" \
      '{containerOverrides: [{name: "app", command: ["-e", $js], environment: [{name: "PGHOST", value: $host}, {name: "SQL", value: $sql}]}]}')" \
  --query 'tasks[0].taskArn' --output text)
aws ecs wait tasks-stopped --cluster "$CLUSTER" --tasks "$TASK"
CODE=$(aws ecs describe-tasks --cluster "$CLUSTER" --tasks "$TASK" \
  --query 'tasks[0].containers[0].exitCode' --output text)

case "$CODE" in
  0) log "PASS: restored ledger is balanced. RTO=${RTO}s, RPO target=${MINUTES_AGO}m. Record in docs/runbooks/backup-restore.md" ;;
  2) die "FAIL: restored ledger contains unbalanced journal entries" ;;
  *) die "FAIL: integrity check task exited $CODE (see /ledgerops/$SERVICE logs)" ;;
esac
