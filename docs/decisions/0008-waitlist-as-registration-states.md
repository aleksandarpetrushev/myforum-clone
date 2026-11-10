# The waitlist is two registration states, and freed seats are offered, not given

Status: accepted, 2026-11-10, for MF-202.

## Summary

People queuing for a full event are stored as registrations in a `waitlisted` state, and a freed seat moves the first of them to `offered`, holding the seat until they confirm it within min(24 hours, half the time until the start). Positions are computed from join order when read, never stored. We will revisit this when the waitlist needs data of its own beyond a join time and an offer deadline, or when computing positions shows up in slow queries.

## Context

A full event answered 409, and MF-201 hid full events from recommendations for that reason. The ticket asks for an idempotent join with a visible position, promotion that never oversells even when two cancellations race, and a waitlist count for organizers. My Forum sends in-app notifications only, so a person may not see an offer for hours.

## Decision

- **Storage:** two new `Registration` states, `waitlisted` and `offered`, and three timestamps (`waitlisted_at`, `offered_at`, `offer_expires_at`). One row per user and event, as today.
- **Seats:** `reserved_spots` counts `confirmed` and `offered`, so the existing row lock and the `reserved_spots <= capacity` check also guard offers.
- **Promotion:** in the transaction that frees seats, under the event lock, the first waiting rows by join order are offered in one batch, as many as there are free seats.
- **Offers:** they expire after min(24 h, half the time to start). An expired offer cancels that place in line and passes the seat on. No offers and no joins in the last hour before the start.
- **Position:** computed when read from `waitlisted_at` and `id`, served by an index.

## Alternatives

| Option | Why not |
|---|---|
| A separate `waitlist_entries` table | A second place that says whether someone holds or wants a seat. If the waitlist later needs it, it can be introduced then; moving rows out of `registrations` later was judged the bigger risk than moving them into a new table |
| Confirm the freed seat automatically | Books people who joined days ago and may no longer want or be able to come, and with in-app notifications only they may not notice |
| Store each position | Every departure rewrites the position of everyone behind it: thousands of writes for a long line, and numbers that lag while a recompute runs |
| Promote one person per freed seat in a follow-up job | A seat sits free between the cancel and the job, where a direct registration can take it from the line |

## Consequences

- Every query that reads registrations must account for the two new states: the organizer-cancellation cascade, My registrations, recommendations, and "already registered" checks.
- Offers need a scheduled expiry and a safety net for lost jobs (`waitlist:expire_overdue`).
- Two new outbox event types (`WaitlistOffered`, `WaitlistOfferExpired`) extend the Rails–Go contract; Go deploys first.
- A seat freed in the last hour goes to whoever registers first, not to the line.

## Reverse if

- **The waitlist needs its own data:** for example priorities, groups, notes or several lines per event. Then move waitlist entries to their own table.
- **Positions get slow:** if counting earlier joiners shows up in slow-query logs (very long lines on popular sessions), store a sequence number per event instead.
- **Offers go unanswered:** if most offers expire unanswered, the window or the in-app-only channel is wrong for this audience, and automatic confirmation becomes worth reconsidering.
