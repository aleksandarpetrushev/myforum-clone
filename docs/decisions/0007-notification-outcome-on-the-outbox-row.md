# The first notification decision is final, and is stored on the outbox row

Status: accepted. Recorded on 2026-10-29 for `f5e14a9`, which made the change on 2026-10-21.

## Summary

When the notification job first handles a registration event, it records on that outbox row whether it delivered the notification or suppressed it because the user had muted that kind. Every retry reads that record and does nothing, so a user who unmutes later never receives a stale notification. We will move the record to its own table when one event has to notify more than one person or use more than one channel.

## Context

The outbox delivers at least once: `ProcessOutboxJob` can dispatch a row again if it crashes before marking it published, and Sidekiq retries failed jobs. `SendNotificationJob` used to check the user's preference on every attempt. If the first attempt was suppressed because the user had muted, and the user unmuted before a retry, the retry delivered a notification about a registration from hours or days earlier.

The unique `idempotency_key` on `notifications` only stopped duplicate deliveries. A suppressed attempt wrote no row, so there was nothing for a retry to collide with.

## Decision

- Add `outbox_events.notification_outcome`, `delivered` or `suppressed`, null until decided.
- `SendNotificationJob` locks the user, then the outbox row, and returns if an outcome is already set. Otherwise it checks the preference, creates the notification or logs the suppression, and sets the outcome in the same transaction.
- If the notification insert hits its unique key, an earlier attempt delivered it without recording an outcome, so the job sets `delivered`.
- This applies to `RegistrationCreated` and `RegistrationCancelled`, where one outbox row means one notification to one user. Organizer cancellations (`event_cancelled`) are written per registration by `CancelEventRegistrationsJob` and keyed `notification:event_cancelled:<registration id>`.

## Alternatives

| Option | Why not |
|---|---|
| Re-check the preference on each attempt (before) | Sends stale notifications after an unmute |
| Write a suppressed `notifications` row hidden from the user | Puts rows in the user's notification table that are not notifications, and every read has to filter them |
| A separate `notification_deliveries` table | The general answer, but one more table and join for a case where each outbox row has exactly one recipient and one channel |

## Consequences

- A retry can never change the decision, whatever happens to preferences in between.
- The outcome lives on the outbox row, so outbox rows must be kept at least as long as the job can retry. There is no pruning today; any future pruning must respect that.
- A suppressed notification is logged (`notification.suppressed`) and recorded, so support can answer "why didn't I get it?"

## Reverse if

- **More recipients or channels:** a single domain event has to notify several users, or a notification goes out over a second channel such as email or push. One column per outbox row can no longer hold the answer. Then move it to a `notification_deliveries` table with one row per recipient and channel, unique on the same key.
