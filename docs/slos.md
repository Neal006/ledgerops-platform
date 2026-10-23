# Service level objectives

SLOs are set per **book** (IN, AE) because each is a separate regulated entity with its own
stack, and an outage in one is not offset by good numbers in the other.

| Service | SLI | Objective (30d) | Error budget | Source |
|---|---|---|---|---|
| Ledger API: availability | `/v1/*` responses that are not 5xx | 99.9% | 43 min/month | ALB + `http_server_request_duration_seconds` |
| Ledger API: latency | `/v1/*` requests served in ≤ 300 ms | 99% | 1% of requests | same histogram, `le="0.3"` bucket |
| Reconciliation: freshness | a successful run within the last 26h | 100% of days | none: any miss pages | `ReconSuccess` (EMF) / `recon_last_success_timestamp_seconds` |
| Reconciliation: correctness | runs with zero breaks | 100% | none: every break pages | `ReconBreaks` / `recon_breaks` |

## Why these numbers

- **99.9%, not 99.99%.** The upstream brokers we depend on don't offer more than that, and a
  tighter target would freeze releases without users noticing any difference.
- **300 ms** covers a journal post (one transaction, two to four inserts plus the deferred
  balance trigger) through RDS Proxy with room to spare. The histogram has a bucket edge at
  exactly 0.3 s so the SLI is exact, not interpolated.
- **4xx responses are not errors.** A rejected unbalanced entry means the API did its job.
- **Reconciliation has no error budget.** A break means client money and our books disagree,
  which matters to the regulator whatever the frequency.

## Alerting policy

We alert on **symptoms** (users failing, money not reconciling), not causes (CPU, memory).
Cause-level signals go to the `ticket` route or to dashboards.

| Alert | Condition | Route |
|---|---|---|
| Fast burn | 14.4× budget burn over 1h **and** 5m | page |
| Medium burn | 6× over 6h **and** 30m | page |
| Slow burn | 1× over 3d **and** 6h | ticket |
| Latency burn | >10% of requests slower than 300 ms over 1h and 5m | page |
| Recon breaks | any break in the latest run | page |
| Recon stale | no success for 26h (dead man's switch) | page |
| DB pool saturation | requests waiting for a connection for 5m | ticket |

The short window on each burn-rate alert makes it **reset quickly** once the problem is fixed,
so a resolved incident doesn't keep paging for an hour.

## Error budget policy

- Budget remaining **> 25%**: ship normally.
- **< 25%**: production deploys need a second approver and a rollback plan in the PR.
- **Exhausted**: freeze feature deploys for that book; only reliability fixes and security patches
  ship until the 30-day window recovers.
