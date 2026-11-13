# Rails to personalization contract

The body Rails sends to `POST /internal/events`. Rails writes it into `outbox_events` and `Personalization::DeliverEvent` sends it; this service validates it against the embedded schema.

```json
{ "schema_version": 1, "idempotency_key": "event_updated:42:4", "event_type": "EventUpdated", "payload": { "event": { … } } }
```

- `v1/events.schema.json`: the envelope, one `$defs` entry per event type, and the event snapshot.
- `v1/examples/`: one valid envelope per event type. `go test` runs each through ingest.

Rails' specs check every outbox row they write against the schema (`backend/spec/support/personalization_contract.rb`), so a Rails change that sends something off-schema fails its own specs.

## What the version means

`schema_version` is stored on the outbox row when it is written, not when it is sent, so rows still pending after a deploy keep the version they were written with.

**No new version** for adding a field. Unknown fields are allowed everywhere and ignored by Go. If Go starts to depend on a new field, the field stays optional in the schema and in Go until no row without it remains (as `revision` in version 1).

**No new version either** for adding an event type: it is added to the `event_type` enum with an example. But this service must be deployed before Rails writes the new type. Until then it answers `unsupported_contract`, Rails keeps those rows `deferred`, and `bin/rails outbox:redeliver_deferred` sends them once this service knows the type (as for `WaitlistOffered` and `WaitlistOfferExpired` in MF-202).

**A new version** for removing or renaming a field, changing a field's type or meaning, or making an optional field required.

## How Go treats a payload

| Payload | Response | Applied | Log | Rails marks the row |
|---|---|---|---|---|
| Valid, known version | 204 | yes | none | `published` |
| Invalid against the schema, including a field of the wrong type | 204 | yes, as best it can | `contract.invalid` with the schema errors | `published` |
| `schema_version` or `event_type` this service cannot read | 422 `unsupported_contract` | no | `contract.unsupported` | `deferred` |
| No `schema_version` | read as 1 | | | |
| Body over 10 MiB | 413 `payload_too_large` | no | `contract.too_large` | stays `pending`; the poller stops on it, like any delivery error |

Go never answers an invalid payload with an error: any other non-2xx stops Rails' outbox poller, and with it notifications and analytics.

A `deferred` row has been dispatched to notifications and analytics, but the personalization service has not taken it. It is never marked published until it is, so it cannot be mistaken for a row that was delivered, nor for one nobody has touched yet. `Metrics.outbox_deferred_count` above 0 means some rows are waiting. Once a service that reads them is deployed, send them again:

```bash
cd backend && bin/rails outbox:redeliver_deferred
```

## Moving to version 2

The consumer goes first, so Rails never writes a version Go cannot read.

1. Add `v2/events.schema.json` and `v2/examples/` beside v1. Keep v1.
2. Teach this service version 2: add `v2` to the `go:embed` line in `embed.go`, and add `2` to `SupportedVersions` in `validator.go`. **`SupportedVersions` is the only list that decides which versions are accepted**: a schema that is embedded but not listed there is answered as unsupported. Each payload is validated against the schema of its own `schema_version`, and the event types come from that schema's `event_type` enum. `go test` must pass for both versions' examples.
3. Deploy this service. It now accepts versions 1 and 2.
4. In Rails, raise `Personalization::Contract::VERSION` to 2, change the payloads, and point the spec hook at `v2`. Deploy Rails. New rows are written as version 2; pending rows stay version 1 and are still accepted.
5. Wait until no version 1 row is waiting, pending or deferred:

   ```sql
   SELECT count(*) FROM outbox_events WHERE status IN ('pending', 'deferred') AND schema_version = 1;
   ```

6. Only when that is 0: remove version 1 from this service and deploy it again. Remove `v1/` in the same change.

**Before step 1, confirm the alert on `Metrics.outbox_deferred_count` is in place** (above 0 for 15 minutes; `docs/architecture.md`). Deferred rows are not retried automatically: the alert is what tells someone to deploy the right build and redeliver.

If step 4 runs before step 3, or this service is rolled back to a build without version 2, it answers every version 2 row with `unsupported_contract`. Rails keeps those rows as `deferred`, and nothing is lost: deploy a service that reads version 2, then run `bin/rails outbox:redeliver_deferred`.
