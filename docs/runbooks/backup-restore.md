# Runbook: backups, point-in-time recovery and restore drills

## What exists
| Layer | Setting | Gives us |
|---|---|---|
| RDS automated backups + WAL | 35-day retention | Point-in-time recovery to any second in the window |
| Multi-AZ (production) | synchronous standby | AZ failure with no data loss, about 60s of failover |
| Backup replication (IN only) | ap-south-1 → ap-south-2 | Regional DR **without leaving India** |
| Deletion protection + final snapshot | on | Protection against `terraform destroy` and console accidents |

The UAE book has no cross-region copy: me-central-1 is the only AWS region in the UAE, and
replicating to Bahrain would move client data out of the jurisdiction. This trade-off is accepted
and documented with Compliance.

## Monthly restore drill
```bash
./scripts/restore-drill.sh staging        # monthly
./scripts/restore-drill.sh prod-in 60     # quarterly, restore to an hour ago
```
The script restores to a temporary instance, checks that every journal entry still balances, prints
the measured RTO, and deletes the copy. Record the results below.

> If the RDS-managed master password rotated after the restore point, the drill's integrity task
> will fail to authenticate. Reset the drill instance's password with `modify-db-instance` and re-run
> the check.

| Date | Env | Restore point | RTO | Result | By |
|---|---|---|---|---|---|
| | | | | | |

## Real recovery (data corruption)
1. Declare SEV1. **Stop writes**: scale the API to 0 (`aws ecs update-service --desired-count 0`).
2. Find the last good timestamp (from the audit trail in `journal_entries.created_at` and the logs).
3. Restore to that time as a **new** instance (`restore-drill.sh` steps, without the cleanup).
4. Point the stack at it: change the identifier in Terraform, plan, get it reviewed, apply.
5. Replay legitimate transactions made after the restore point from the broker's records.
