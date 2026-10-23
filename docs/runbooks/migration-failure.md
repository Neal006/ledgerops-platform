# Runbook: a migration failed during deploy

The deploy pipeline runs migrations **before** touching the running service, so a failed
migration means the old version is still serving traffic on the old schema. There is no outage.
Don't rush.

1. Read the migration task's logs: the deploy job prints the log stream name.
2. `lock timeout` → something held a lock for over 5s (the migrator's `lock_timeout`). That's working
   as intended: we failed instead of queueing every request behind us. Find the blocker
   ([high-latency](high-latency.md) step 2) and re-run the deploy at a quieter time.
3. A transactional migration that failed has rolled back completely. Fix it in a **new** commit.
   (If the file was never applied anywhere, editing it is fine; the CI immutability check only
   protects files already on `main`.)
4. A `-- migrate:no-transaction` migration (e.g. `CREATE INDEX CONCURRENTLY`) that failed can leave an
   `INVALID` index behind:
   ```sql
   SELECT indexrelid::regclass FROM pg_index WHERE NOT indisvalid;
   ```
   Drop it with `DROP INDEX CONCURRENTLY` and re-run.
5. `migration X was modified after being applied` → someone edited a merged migration. Revert that
   edit and add a new migration instead.
