---
description: Trace one user action through Angular, Rails, the outbox, Sidekiq and the Go service
argument-hint: <a user action, e.g. "join a waitlist" or "cancel an event">
---

Trace this flow end to end: $ARGUMENTS

Read the code; do not describe it from memory or from the docs alone (`docs/registration-flow.md` and `docs/architecture.md` may lag behind it). For each step give `path:line`.

1. **Angular**: the component and `ForumApi` method that start it, and what the page shows on success and on each error code.
2. **Rails request**: route, controller action, how `EventPolicy` is applied, and the service it calls.
3. **The transaction**: which rows are locked and in what order, which rows change, which counters (`reserved_spots`, `revision`, `lifecycle_version`) move, and which outbox rows are written with which idempotency keys.
4. **After commit**: cache invalidation (`Events::Cache`), jobs enqueued, scheduled jobs.
5. **Outbox dispatch**: `Outbox::Dispatcher` routing for each event type: notifications, analytics, the Go service. Note the contract `event_type` and whether Go applies it.
6. **Failure paths**: what happens if each external step fails (Go down, a job raising, a lock wait), and where it becomes visible (`Metrics.*`, logs).

End with a short sequence diagram in Mermaid (no `;` inside message text: it breaks the diagram), and list anything in the docs that disagrees with the code.
