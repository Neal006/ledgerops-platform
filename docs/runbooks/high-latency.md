# Runbook: ledger API latency

**Alerts:** `LedgerApiLatencySloBurn`, CloudWatch `<stack>-api-latency-p99`

1. **Is it everyone or one route?** Grafana *Ledger API* → latency panel, split by `route`.
2. **Database?** RDS Performance Insights → database load by wait event.
   - `Lock:transactionid` / `Lock:relation`: something is holding locks, often a migration or a
     long manual session. Find it:
     ```sql
     SELECT pid, now() - xact_start AS age, state, left(query, 120)
       FROM pg_stat_activity WHERE xact_start IS NOT NULL ORDER BY age DESC LIMIT 10;
     ```
     `idle_in_transaction_session_timeout` (60s) kills idle holders automatically. For an active
     holder that is clearly the cause, `SELECT pg_cancel_backend(<pid>)` first, and only
     `pg_terminate_backend` if that doesn't work.
   - `CPU`: check top SQL for a missing index or a plan regression.
3. **Application?** `nodejs_eventloop_lag_p99_seconds` > 100 ms means CPU-bound tasks: scale out
   (`aws ecs update-service --desired-count`) and find the hot path.
4. **Pool waiting > 0?** → [db-connection-exhaustion](db-connection-exhaustion.md).
