## Postmortem: Notifications stopped for 63 minutes, and 63 waitlist offers expired unseen

**Date:** 2026-11-12 | **Duration:** 64 min of user impact (07:32–08:36 UTC); 4 h 9 min from first failure to both fixes deployed | **Severity:** SEV2
**Authors:** Aleksandar Petrushev (incident commander), Lena (responder) | **Status:** Draft
**Ticket:** MF-204 | **Fixes:** PR #10 (outbox), PR #11 (personalization memory)

Times are UTC. Local time (CET) was one hour later: the outage ran 08:32–09:36 CET.

### Summary

On the morning the programme was published, the personalization service ran out of memory six times in 30 minutes. Each time it was down, delivery to it failed. One failed delivery stopped the outbox poller, which delivers every notification, so My Forum sent no notifications for 63 minutes. Waitlist offers kept being made in order but nobody was told, and 63 offers expired before their owners saw them. Nobody lost a confirmed seat. 52 of the 63 people were restored to their place in line the same morning.

### Impact

- **Every user:** no notifications from 07:32 to 08:36. That covers registration confirmations, cancellations and waitlist offers: 1,412 outbox rows, delayed by up to 63 minutes.
- **Waitlists:** 63 offers on 11 sessions expired unseen, and their seats passed further down the line.
  - 22 of those seats were then accepted by later people, and 31 were offered to later people.
  - 52 of the 63 people were restored to their original place in line at 09:04, and 4 were offered a seat immediately.
  - 11, on three 09:30 sessions whose waitlist had closed, received an apology.
- **Notification bursts:** when the backlog drained, the 63 received "A seat opened" and "Your seat offer expired" at the same moment.
- **Delayed but not lost:** analytics, and personalization's read model.
- **Not affected:** registrations, cancellations, discovery and event pages, which worked throughout. No confirmed seat was lost.

### Timeline

| Time (UTC) | Event |
|------------|-------|
| 07:30 | Programme email goes out; discovery traffic doubles, and with it calls to recommendations |
| 07:32:50 | Personalization is OOM-killed (512 Mi limit) |
| 07:32:51 | Last outbox row delivered |
| 07:32:57 | `ProcessOutboxJob` fails delivering row 88412 (`Errno::ECONNREFUSED`). The job only reschedules itself after a successful pass, so it is now in Sidekiq's retry backoff and nothing polls the outbox |
| 07:33–08:01 | Seven retries, at growing intervals, each landing while the pod is down or restarting; the next interval reaches 40 minutes |
| 07:58 | `outbox_pending_age_seconds` alert fires (threshold 300 s) |
| 08:02:30 | Personalization stable after its sixth restart. The outbox stays frozen: the next retry is at 08:41 |
| 08:05 | First participant receives "Your seat offer expired" for an offer never announced |
| 08:14 | Alert reaches on-call (routed through a channel, 16 minutes after firing) |
| 08:16–08:19 | Support, ops and the PO report. Incident declared, SEV2 |
| 08:22 | Second engineer joins; roles agreed at 08:31 (incident commander, responder) |
| 08:26 | Personalization memory raised to 1 Gi |
| 08:27 | Cause of the stall identified: the failed job is in retry backoff, and nothing polls in between |
| 08:29 | Impact quantified: 63 offers expired unseen, and 41 offers outstanding but unannounced |
| 08:34 | "Retry now" on the existing job (no second polling chain) |
| 08:36:41 | Backlog of 1,412 rows delivered; the alert resolves. **User impact ends** |
| 08:44 | First update to organizers: what happened, no promises, next update at 09:00 |
| 08:53 | Remediation decided: restore people to their place in line, and ask organizers about extra seats |
| 08:57 | Remediation script dry run: 52 rows, 0 over capacity |
| 09:01 | Second update to organizers |
| 09:04 | Remediation run: 52 restored, 4 offered seats. **Mitigated** |
| 09:06 | Apology sent to the 11 people on closed waitlists |
| ~09:50 | Benchmark shows the old code peaking at 1,630 MB at 50 concurrent requests, so 1 Gi is not enough |
| 09:57 | Personalization memory raised to 2 Gi |
| 10:00 | Status update to organizers, support and ops |
| 10:24 | PR #11 deployed: personalization memory under the same traffic drops to 41 MB |
| 10:41 | PR #10 deployed: outbox failures stay with their row. Stall alerts page on-call directly. **Resolved** |

### Root Cause

Two weaknesses in the system turned a recoverable crash into a long, silent outage.

1. **The outbox poller stopped for every consumer when one consumer failed.**
   - `Outbox::Publisher` delivered rows in one loop, so a failed delivery to personalization failed the whole `ProcessOutboxJob`.
   - The job only rescheduled itself after a successful pass. After a failure it ran again only when Sidekiq retried it, with exponential backoff: 15 s, 16 s, 31 s, 1.5 min, 4.5 min, 11 min, 22 min, 40 min.
   - Every retry started with the same oldest row, so any downtime failed the whole pass.
   - A 30-minute personalization outage therefore became a 63-minute stop for notifications, analytics and waitlist announcements. That 63 minutes ended only because the job was retried by hand.
   - This weakness was recorded as an open item in the MF-102 review ("the outbox poller stalls on dispatch errors") but had no ticket.
2. **Recommendations used memory in proportion to every eligible event.**
   - Each `GET /recommendations` loaded all eligible events (up to 49,000 on the benchmark set), their ids, a topic map and a scored copy into memory.
   - It also sent all the ids back to Postgres in one parameter.
   - Memory grew with events × concurrent requests. Since MF-201 (9 November), every discovery page view calls it.
   - Doubled traffic took it past 512 Mi.

**Why a delay became lost seats:** waitlist offers (MF-202, live since 10 November) last as little as 30–90 minutes on the day. They assume the offer is announced when it's made. During the stall the offers' clocks kept running while nobody was told.

### 5 Whys

1. **Why did 63 people miss their waitlist offer?** → They were never notified before it expired.
2. **Why weren't they notified?** → No outbox row was delivered for 63 minutes, and notifications are sent through the outbox.
3. **Why was no row delivered?** → One delivery to personalization failed. That failed the poller, which then sat in Sidekiq's growing retry backoff instead of carrying on with other rows.
4. **Why did delivery to personalization fail?** → The service was OOM-killed six times under the programme-day traffic.
5. **Why did it run out of memory, and why did that stop everything?** → **Root cause:** recommendations held every eligible event in memory per request. Separately, the outbox let any single consumer's failure stop all consumers. Both were known risks without tickets: the poller stall since MF-102; memory was never load-tested.

### What Went Well

- **Roles were set early:** one incident commander making decisions and running comms, one responder hands-on. Communication never stalled while someone was in a terminal.
- **The poller was restarted without making things worse.** "Retry now" on the existing job restarted it without creating a second polling chain.
- **Data was changed carefully.** The remediation script was dry-run first, with row-level output reviewed before it ran against live data. It touched exactly the 52 intended rows.
- **The organizer messages said only what was true.** The PO caught an early draft that promised to "add" people back before that was possible.
- **Safeguards from earlier tickets held:**
  - MF-106's revision guard kept personalization's read model correct while four outbox pollers were catching up.
  - MF-203's contract reported no invalid payloads.
  - The waitlist never overbooked.
- **The fixes were measured, not assumed.** The memory fix was benchmarked against the old code on 100,000 events, which also showed that the first mitigation was not enough.

### What Went Poorly

- **A 30-minute outage caused a 63-minute stall** because of how the poller failed and retried.
- **Detection was slow:** the stall started at 07:32, the alert fired at 07:58 and reached on-call at 08:14. Customers noticed before we did.
- **The first mitigation, 1 Gi of memory, was not enough.** It held only because traffic eased. Measurement later showed the old code needed about 1.6 GB.
- **A known risk had no owner.** The poller stall had been recorded in the MF-102 review on 28 October and never scheduled.
- **The waitlist design has no safeguard for an announcement outage.** An offer's clock runs whether or not the person was told.
- **Draining the backlog sent confusing notification pairs** ("seat opened" plus "offer expired") to the 63 affected people.
- **Development hygiene:** four duplicate outbox polling chains run in the development environment, and jobs for deleted test data were left retrying. Neither caused this incident, but both hide real failures in logs.

### Action Items

| Action | Owner | Priority | Due Date |
|--------|-------|----------|----------|
| A failed delivery stays with its row and backs off on its own; the poller carries on, keeping order per event and per user (PR #10) | Aleksandar | P0 | Done 2026-11-12 |
| Recommendations stream candidates and keep only the top results (PR #11) | Aleksandar | P0 | Done 2026-11-12 |
| Page on-call directly when `outbox_stall_seconds` > 120 or `outbox_rows_failing` > 0 | Tomás | P0 | Done 2026-11-12 |
| Find out why the pending-age alert fired 26 minutes after the stall began and reached on-call 16 minutes later; remove the channel hop for all paging alerts | Tomás | P1 | 2026-11-13 |
| Return personalization's memory limit to 512 Mi after 24 h on the new build; alert at 70% of the limit | Tomás | P1 | 2026-11-13 |
| Waitlist safeguard: decide with the PO whether an offer's clock should pause or extend when its notification is late, then ticket it | PO, Aleksandar | P1 | 2026-11-17 |
| Load-test recommendations and the outbox under a programme-day rush, including memory (fold into MF-302) | Aleksandar | P1 | Sprint 3 |
| Make the outbox poller a single scheduled job, so it can't run as several chains | Lena | P2 | Sprint 3 |
| Turn the restore-to-waitlist script into a reviewed rake task with a dry-run mode, plus a runbook "outbox stalled" | Lena | P2 | Sprint 3 |
| Every open item recorded in a review gets a ticket or an explicit "won't do" before the PR merges | PO | P2 | From 2026-11-13 |
| Run the `EachCandidate` Postgres test in CI (fold into MF-301) | Aleksandar | P2 | Sprint 3 |

### Lessons Learned

- **A dependency's failure should stay with that dependency.** Notifications and analytics had no reason to wait for personalization, but one loop tied them together. Isolating failures per row and per consumer is cheaper than any amount of uptime.
- **Exponential backoff on a heartbeat job turns a short outage into a long one.** A job that keeps the system moving should never be left to a retry schedule. It should keep running and report failures as data.
- **Short deadlines need reliable announcements.** Any feature with a timer, like waitlist offers, must say what happens to the timer when the message announcing it is late.
- **Measure the mitigation, not just the fix.** The emergency memory raise looked sufficient and wasn't. A quick benchmark found that within the hour.
- **Recorded risks need owners.** This incident's main cause had been written down two weeks earlier.
