# Backend (Rails 7.1 API)

Rules the AI has got wrong here before. Each one is in `docs/journal.md` with the incident behind it.

## Invariants

- **Visibility:** every read of events goes through `policy_scope(Event)` (in services, `Pundit.policy_scope!(user, Event)`), then `authorize`. A record the caller cannot see answers 404, never 403. Rails filters anything the Go service returns; Go never decides visibility.
- **Seats:** `reserved_spots <= capacity` is a check constraint. Change `reserved_spots` only under the event row lock (`lock!` / `FOR UPDATE`), lock the event before the registration, and count `offered` seats as reserved.
- **Outbox:** a change others must hear about writes its outbox row in the same transaction. Registration changes go through `Registrations::ChangeEvent.record!`. Idempotency keys name one change; registration keys include `lifecycle_version`. A new `event_type` goes into `personalization/contract/v1/events.schema.json` first; `spec/support/personalization_contract.rb` validates every row a spec writes.
- **Revision:** every change to an event row, including cancellation and seat counts, bumps `events.revision`, so Go can order snapshots.
- **Cache:** `Events::Cache` holds the shared event detail. Per-viewer fields (`my_registration`, admin counts) are merged per request, never cached. Invalidate after commit.
- **Calls to Go** go through `Personalization::Http` (timeouts set, `Net::HTTP` retries off).
- **Time rules from the PO:** no waitlist offers or joins in the last hour; publishing a draft is allowed until its start. Derive "still actionable" from times, not only from status: a job that expires something may not have run yet.

## Ruby and Rails traps

- **One constant per file.** Zeitwerk loads `Personalization::Unavailable` only from `personalization/unavailable.rb`. Defining an error class inside another file makes `rescue` raise `NameError` depending on load order (it made a spec flaky).
- **`reload` forgets `saved_changes`.** Read `saved_change_to_x?` and similar before any `reload`.
- **A new record's default is not a change.** A new `Event` defaults to `published`, so `status_changed?` is false for it.
- **`schema.rb`:** local Postgres 18 rewrites every check constraint and adds `create_schema "personalization"` (Go's schema lives in the same database). After a migration, `git checkout db/schema.rb` and re-apply only the real lines.

## Tests

- `timeout 600 bundle exec rspec`, or one file: `bundle exec rspec spec/path_spec.rb`.
- `freeze_time` rounds to whole seconds; `travel` keeps sub-seconds. Create time-sensitive records inside the frozen or travelled block, and reference a lazy `let` before `travel_to` if it must exist in the present. Compare times with `be_within`.
- Never open a second database connection that waits on a lock the example's transaction holds: the suite deadlocks. Concurrency specs use threads with `self.use_transactional_tests = false` and clean up after themselves (see `spec/services/events/update_concurrency_spec.rb`).
- In transactional examples a service's transaction is a savepoint: rolling it back also undoes rows the example inserted inside it.
- Request specs cover the happy path, 404 for an invisible record, 401 signed out, and each error code.
- If the test database is broken: `RAILS_ENV=test bin/rails db:schema:load`.

## Operations

`bin/rails outbox:redeliver_deferred`, `bin/rails events:resume_cancellations`, `bin/rails waitlist:expire_overdue`. Metrics are in `app/services/metrics.rb`; a new background guarantee gets a metric and a rake task to repair it.
