# Registration flow

Registering commits the business change and the outbox row together. Side effects run after that commit.

```mermaid
sequenceDiagram
  autonumber
  participant Client as Angular
  participant API as RegistrationsController
  participant Reg as Events::Register
  participant DB as PostgreSQL
  participant Redis
  participant Poll as ProcessOutboxJob
  participant Notify as SendNotificationJob
  participant Stats as RecordAnalyticsJob
  participant Go as Personalization

  Client->>API: POST /api/registrations {event_id}
  API->>DB: policy_scope(Event).find + authorize show?
  Note over API,DB: not visible → 404
  API->>Reg: call
  rect rgb(235, 242, 255)
    Note over Reg,DB: one transaction
    Reg->>DB: SELECT event FOR UPDATE (must be published)
    Reg->>DB: SELECT registration FOR UPDATE
    Note over Reg,DB: confirmed → 409 duplicate · full → 409 event_full
    Reg->>DB: INSERT registration, or reconfirm a cancelled one
    Reg->>DB: UPDATE events SET reserved_spots + 1
    Reg->>DB: INSERT outbox_events RegistrationCreated
  end
  Reg->>Redis: after commit: delete event detail, bump list epoch
  API-->>Client: 201 registration

  loop every 1–5 s
    Poll->>DB: pending rows, oldest first, lock each row
    Poll->>Redis: enqueue SendNotificationJob, RecordAnalyticsJob
    Poll->>Go: POST /internal/events
    Go->>DB: skip if key processed, else update personalization schema
    Poll->>DB: mark row published
  end

  Notify->>DB: lock user, lock outbox row
  alt notification_outcome already set
    Notify-->>Notify: do nothing
  else allowed by preferences
    Notify->>DB: INSERT notification, outcome = delivered
  else muted
    Notify->>DB: outcome = suppressed
  end
  Stats->>DB: INSERT analytics_events (unique key)
```

Steps 1–10 happen before the response; everything after is asynchronous. If the POST to the Go service raises, the row stays pending, but the exception also fails `ProcessOutboxJob`, which reschedules itself only after a pass completes, so polling stops until the job is started again. That is a known open issue. The notification branch is ADR 0007; the cache step is ADR 0005.

`Events::Register` locks the event row, rejects a registration that is already confirmed, and rejects the call when `reserved_spots` is already at `capacity`. A cancelled registration for the same user and event is confirmed again and reserves another spot. The unique index on `(user_id, event_id)` is the backstop for a duplicate insert. The check constraint `reserved_spots <= capacity` is the backstop for an oversell. A failed outbox insert rolls the registration back.

`POST /api/registrations/cancel` locks the same event. A confirmed registration can be cancelled only while `starts_at` is still in the future. It then becomes `cancelled`, frees one spot, and writes `RegistrationCancelled`. Cancelling at or after the start returns 422 `event_started` and leaves the spot reserved. A second cancel of an already cancelled row does not free another spot. If a confirmed row exists while `reserved_spots` is already zero, the transaction fails and the counter is left unchanged. Cancelling when there is no row returns 404 `user_not_registered` for an event the caller can still see, and 404 `not_found` when they cannot see it. Losing visibility does not block cancel. The cancel response and `GET /api/me/registrations` include event title, time, and location only while the caller can still view the event.

Outbox idempotency keys include `lifecycle_version`, so a later create or cancel cycle writes a new row and a retry of the same cycle does not.

Duplicate registration returns 409 `duplicate_registration`. A full event returns 409 `event_full`. There is no payment step. New registrations are stored as `confirmed`. `failed` remains on the column and cannot be cancelled or reopened.

`ProcessOutboxJob` marks a row published only after dispatch returns. If dispatch raises, for example because the personalization service is down, the row stays pending with `attempts`, `last_error` and a `next_attempt_at` that backs off from 2 seconds to 5 minutes, and the pass carries on with other rows. Later rows with the same ordering key (the same event, or the same user's topic follows) wait behind it, so they still arrive in order (MF-204). Notification and analytics inserts ignore a repeated idempotency key. The Go service does the same with `processed_events`.

## Organizer cancellation

An organizer admin cancels a published event that has not started with `POST /api/events/:id/cancel`. `PATCH` cannot cancel, and neither can any plain status write: only the state machine's `cancel` event, fired by `Events::Cancel`, may. `Events::Cancel` locks the event, moves it to `cancelled` through the `Event` state machine, sets `cancelled_at`, and writes one `EventCancelled` outbox row (key `event_cancelled:<id>`). Cancelling an already cancelled event returns it unchanged. A draft cannot be cancelled; delete it instead.

The dispatcher hands `EventCancelled` to `CancelEventRegistrationsJob`. For each confirmed registration, in its own transaction, the job locks the registration, then the user. It cancels the registration with `cancelled_by: "organizer"` and, unless the user switched off `event_cancelled_enabled`, writes one `event_cancelled` notification keyed `notification:event_cancelled:<registration id>`. A registration that is no longer confirmed is skipped, so reruns and a participant's own earlier cancel are left alone. No `RegistrationCancelled` row is written, so registrants get one notification, not two. The event row is not locked per registration; after the loop, one statement sets `reserved_spots` to the count of registrations still confirmed, and the cache is invalidated once. The job does nothing for an event that is not cancelled.

Until the job reaches a registration it still reads `confirmed`; clients use the event's `status` in the registration's `event` summary to show the event as cancelled. Stuck cascades show up in `Metrics.cancelled_events_with_confirmed_registrations` and are resumed with `bin/rails events:resume_cancellations`.

## Waitlist

A full event has a waitlist (MF-202, ADR 0008). A place in line is a registration in the `waitlisted` state, and a seat offered from the line is `offered`. An offered seat counts in `reserved_spots`, so it is held: a direct registration finds the event full.

```mermaid
stateDiagram-v2
  [*] --> waitlisted: join (event full)
  cancelled --> waitlisted: join again
  waitlisted --> offered: a seat frees up
  offered --> confirmed: accept before the deadline
  offered --> cancelled: decline, or the offer expires
  waitlisted --> cancelled: leave the line
  waitlisted --> confirmed: register directly in the last hour
  confirmed --> cancelled: cancel
```

`POST /api/registrations/waitlist` joins the line: 201 for a new place, 200 when already waiting or offered, 409 `seats_available` when a seat is free, 409 `duplicate_registration` for a confirmed registrant, and 422 `waitlist_closed` within an hour of the start. The position is computed from `waitlisted_at` (then `id`) on each read.

A seat freed by a cancelled registration, a declined offer, an expired offer or a capacity increase is offered in the same transaction, under the event lock, to as many people as there are free seats, first in line first. The offer lasts min(24 hours, half the time until the start), and nothing is offered in the last hour: a seat freed then goes to whoever registers first, including someone still in line. Each offer writes `WaitlistOffered` (the person is notified) and schedules `ExpireWaitlistOfferJob` at its deadline after the transaction commits.

`POST /api/registrations/accept_offer` confirms an offer that has not lapsed and writes `RegistrationCreated`; the seat count does not change. `POST /api/registrations/cancel` leaves the line or declines an offer; neither notifies anyone. An expired offer becomes `cancelled` with `cancelled_by: "offer_expired"`, writes `WaitlistOfferExpired` (the person is notified), and offers the seat on. If an expiry job is lost, `Metrics.overdue_waitlist_offers` rises above 0; run `bin/rails waitlist:expire_overdue`.

When an organizer cancels the event, the cascade cancels waitlisted and offered registrations too and tells each person once.
