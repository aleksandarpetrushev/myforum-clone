# Architecture

My Forum V1 is a modular monolith plus one recommendation service. It is meant to be joined, reviewed, and extended. It is not a microservice platform.

## System context

```mermaid
flowchart LR
  Browser[Angular] --> API[Rails API]
  API --> DB[(PostgreSQL)]
  API --> Redis[(Redis cache and Sidekiq)]
  API --> Outbox[outbox_events]
  Outbox --> Worker[Sidekiq]
  Worker --> Notify[notifications]
  Worker --> Analytics[analytics_events]
  Worker --> Go[Go personalization]
  Go --> ReadModel[(personalization schema)]
```

## Responsibilities

Rails is the system of record for users, organizations, topics, events, registrations, notifications, and the outbox. Controllers stay thin. `Events::Register` and `Topics::Follow` own multi-step workflows. Models own relationships and validations. PostgreSQL unique indexes and check constraints own the hard invariants, including `reserved_spots <= capacity`.

Pundit answers authorization. Any authenticated user can read events, because every event is public in this version. Only an organization admin can update or delete that organization's events. Anonymous requests stop at authentication with 401. A future organization-restricted catalog should extend `EventPolicy::Scope`, not scatter checks through controllers.

Redis caches event detail JSON for 10 minutes and the unfiltered first page of upcoming events for 1 minute. Filtered searches are not cached. Updating an event deletes those keys and enqueues `RebuildEventCacheJob`. Redis is not required for readiness. If Redis is down, cached reads fail, but the database is still the source of truth.

Sidekiq queues are `default`, `notifications`, and `analytics`. `ProcessOutboxJob` claims pending outbox rows, dispatches them, and reschedules itself. Handlers are safe to run again: notifications and analytics rows are unique on an idempotency key, and the Go ingest stores processed keys.

The Go service keeps a read model in the `personalization` schema. Rails posts domain events to `POST /internal/events`. Ranking is deterministic: followed topics, location, a near-term boost, and a simple popularity fraction. There is no model training.

## Sync and async

Registration commits the registration, the capacity increment, and the outbox row in one transaction. Notification delivery, analytics, and the recommendation update happen after commit. Search is a synchronous `ILIKE` query. That is intentional: it is correct at this size and is the seam where a later search service would attach.

## Observability

Request logs are JSON and include `request_id`, `user_id`, `duration_ms`, and `event_id` or `registration_id` when the request has them. Passwords and tokens are not logged.

`Metrics` keeps in-process counters for request count, request duration, and registration success or failure. Outbox lag is `Metrics.outbox_pending_age_seconds`. Sidekiq queue depth is available from Sidekiq's own API when Redis is up. These are names to scrape later. This version does not run Prometheus.

## What this version leaves open

PostgreSQL text search, a hand-written ranker, a polled outbox instead of a broker, analytics stored as rows, and registration still inside the Rails process. Those are the extension points. They are not broken behavior.
