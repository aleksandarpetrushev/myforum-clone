---
description: Add a Rails API endpoint with EventPolicy authorization and a request spec
argument-hint: <METHOD /api/path — what it does>
---

Add this endpoint: $ARGUMENTS

Follow the rules in `backend/CLAUDE.md`, and in particular:

1. **Authorization first.** Every read of events goes through `policy_scope(Event)` (or `Pundit.policy_scope!(user, Event)` in a service), then `authorize event, :<action>?`. A record the caller cannot see is 404, never 403. Write the policy method in `app/policies/` if it is new.
2. **Thin controller.** Business rules go in a service under `app/services/<area>/` (one class per file, so Zeitwerk can load it). The controller finds, authorizes, calls the service, renders.
3. **Writes that others must hear about** record an outbox row in the same transaction: registration changes through `Registrations::ChangeEvent.record!`, others with `OutboxEvent.create!` and a key that names one change. A new `event_type` must be added to `personalization/contract/v1/events.schema.json` first, and the Go service deployed before Rails writes it.
4. **Errors** use `render_error(code:, message:, status:)` with a stable snake_case `code`; validation failures go through the existing `render_validation_failed`.
5. **Request spec** in `spec/requests/`: the happy path, a caller who cannot see the record (404), a signed-out caller (401), and each error code. If the change has a rule that could be removed by mistake, revert it temporarily and confirm a spec fails.
6. Add the route under `namespace :api` and document the endpoint in `README.md` if the README lists endpoints for that area.
