# Incident process

## Severity

| Sev | Definition | Examples | Response |
|---|---|---|---|
| **SEV1** | Client money at risk, or the platform is unusable in a book | Recon breaks with unexplained differences; order placement down; data exposure | Page immediately, 24×7. Founders informed within 30 min. Assess whether to notify the regulator. |
| **SEV2** | Major degradation; a workaround exists | Deposits delayed; one broker integration failing; fast-burn SLO alert | Page in business hours, otherwise next morning unless it escalates |
| **SEV3** | Minor or internal-only impact | Staging down; slow-burn alert; failed nightly job that retried and succeeded | Ticket, next business day |

## Roles

- **Incident commander (IC):** coordinates and makes decisions. Doesn't debug. The first responder
  is IC until they hand over explicitly.
- **Ops lead:** hands on keyboard. Changes production, and says so in the channel before doing it.
- **Comms lead (SEV1):** updates stakeholders every 30 min and owns customer and regulator messaging.

## Flow

1. **Acknowledge** the page within 5 minutes (SEV1/2).
2. **Declare**: open `#inc-YYYYMMDD-short-name` and post severity, impact, and who is IC.
3. **Mitigate first, diagnose second.** If a deploy went out in the last 2 hours, roll it back
   (`make rollback ENV=<env>` or the *rollback* workflow) before investigating.
4. **Keep a timeline** in the channel: every action, with UTC timestamps. It becomes the postmortem.
5. **Resolve** when the SLIs are back within the objective for 15 minutes.
6. **Postmortem** within 5 business days for every SEV1/SEV2 ([template](postmortem-template.md)).

## Regulated-incident checklist (SEV1)

- [ ] Is client money or client data affected? Which book(s)?
- [ ] Preserve evidence: don't delete logs, snapshots or task definitions; export the relevant CloudWatch logs.
- [ ] Compliance informed. They own the decision and timeline for regulator notification (IFSCA / UAE authority).
- [ ] Any manual ledger correction is a **reversing journal entry** with a ticket reference, never a direct DB edit.
