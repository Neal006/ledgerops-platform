# Runbook: reconciliation breaks or stale reconciliation

**Alerts:** `ReconBreaksDetected` / `<stack>-recon-breaks`, `ReconStale` / `<stack>-recon-stale`
**Severity:** start at **SEV2**. Escalate to **SEV1** if a break is unexplained after 2 hours or
is over the materiality threshold agreed with Finance.

## Stale (the job didn't succeed)
1. ECS → cluster → **Tasks** (stopped) → filter by family `<stack>-recon-worker`. Read the stopped reason.
2. Logs: `/ledgerops/<stack>-recon-worker`. Common causes:
   - `NoSuchKey`: the broker's EOD statement hasn't landed in `s3://<stack>-broker-statements-*/statements/latest.csv`. Chase the broker or ingestion job.
   - `statement must have columns`: the broker changed the file format. Don't edit the file by hand; fix the parser and add a test.
   - DB connection errors → [db-connection-exhaustion](db-connection-exhaustion.md).
3. Re-run by hand once fixed:
   ```bash
   aws ecs run-task --cluster ledgerops-<env> --task-definition ledgerops-<env>-recon-worker \
     --launch-type FARGATE --network-configuration '<copy from the service>'
   ```

## Breaks
Each break is logged as a structured line:
```
fields @timestamp, break_type, account_code, currency, ledger_minor, broker_minor, difference_minor
| filter msg = "reconciliation break"
```
| `break_type` | Usually means |
|---|---|
| `amount_mismatch` | Timing (a deposit booked after the broker's cut-off), fees or FX not yet posted, or a genuine error |
| `missing_in_ledger` | The broker holds a position we never booked: a missed webhook or a failed posting |
| `missing_at_broker` | We booked something the broker never executed: **highest risk** |

**Never fix a break by editing ledger rows.** The tables are append-only and the database rejects
updates. Corrections are new, balanced journal entries with `external_ref` set to the ticket ID,
reviewed by a second person.
