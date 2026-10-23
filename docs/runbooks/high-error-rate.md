# Runbook: ledger API error rate / error budget burn

**Alerts:** `LedgerApiErrorBudgetFastBurn`, `LedgerApiErrorBudgetMediumBurn`, `LedgerApiDown`,
CloudWatch `<stack>-api-5xx-ratio`, `<stack>-api-no-healthy-hosts`

## 1. Was there a recent change? (2 min)
- GitHub → Actions → **deploy**: did a deploy finish in the last 2 hours for this environment?
- If so, **roll back first**: `make rollback ENV=prod-in` (or run the *rollback* workflow).
  Migrations are expand-only, so the previous version runs fine on the current schema.

## 2. Where are the errors coming from?
- `HTTPCode_ELB_5XX` without target 5xx → no healthy targets, or the ALB can't reach tasks.
  Check ECS → service → **Events** for tasks failing health checks.
- Target 5xx → the application. CloudWatch Logs Insights on `/ledgerops/<stack>-ledger-api`:
  ```
  fields @timestamp, msg, err.message, req.url
  | filter level >= 50
  | stats count() by err.message
  | sort count() desc
  ```

## 3. Common causes
| Symptom in logs | Likely cause | Action |
|---|---|---|
| `timeout exceeded when trying to connect` | Pool or proxy exhausted | [db-connection-exhaustion](db-connection-exhaustion.md) |
| `canceling statement due to statement timeout` | Slow query or lock contention | Performance Insights → top SQL / waits |
| `password authentication failed` | Secret rotated, tasks hold the old value | Force a new deployment: `aws ecs update-service --force-new-deployment` |
| Tasks exit with code 137 | OOM | Raise task memory in Terraform; look for a leak in `nodejs_heap_*` |

## 4. Escalate
If not mitigated within 30 minutes, or if client money movement is affected, declare **SEV1**
([incident process](../incident-process.md)).
