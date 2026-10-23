# Runbook: database connection exhaustion

**Alerts:** `DbPoolSaturated`, CloudWatch `<stack>-db-connections-high`
**Symptoms:** `timeout exceeded when trying to connect`, rising latency, `db_pool_connections{state="waiting"} > 0`

## How connections are budgeted
`tasks × DB_POOL_MAX (10)` client connections → **RDS Proxy** → at most 80% of the instance's
`max_connections`. The other 20% is kept for migrations, the recon job and operators.

## Diagnose
1. Grafana → *DB pool connections*: is `waiting` high on every task or only some?
   - Every task: the database side is slow, or the proxy is at its cap. Check the RDS
     `DatabaseConnections` and proxy `DatabaseConnectionsBorrowLatency` metrics.
   - Some tasks: a leak (a client that is never released). Look for a recent code change that added
     `pool.connect()` without `release()` in a `finally`.
2. In Postgres:
   ```sql
   SELECT application_name, state, count(*) FROM pg_stat_activity GROUP BY 1, 2 ORDER BY 3 DESC;
   ```
   Many `idle in transaction` from `ledger-api` points to a code path that doesn't commit or roll back.

## Mitigate
- Roll back if a deploy introduced it.
- **Don't** scale out ECS tasks to "add capacity": every new task adds 10 more connections.
- If the instance is genuinely saturated, scale the instance class (Multi-AZ failover, about 60s of
  errors). Plan it; don't do it in a panic.
