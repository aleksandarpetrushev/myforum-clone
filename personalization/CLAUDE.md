# Personalization (Go)

Ranks events for a user from a read model in the `personalization` schema, fed by Rails' outbox through `POST /internal/events`. Rails remains the source of truth and filters every result for visibility.

## Contract (`contract/`, ADR and README there)

- `contract/v1/events.schema.json` is the single list of event types and fields; the validator reads the enum from it. Every enum entry needs an example in `contract/v1/examples/` (a test enforces it).
- New fields and new event types are additive: no version bump. Go deploys before Rails writes them.
- **Never answer 2xx for a payload you did not apply.** An unsupported `schema_version` is 422 `unsupported_contract`, which Rails stores as `deferred`. Over 10 MiB is 413.
- **Decode loosely.** A payload that breaks the schema is applied as far as possible and logged (`contract.invalid`), never refused: a refusal stops Rails' outbox for that ordering key.
- Snapshot upserts are guarded by `revision`: an older snapshot never overwrites a newer one. Ingest is idempotent by key (`processed_events`).

## Memory

Recommendations stream candidates (`EachCandidate`) and keep the top N in a heap (`ranking.TopK`). Never load every eligible event into memory or send all ids back in one parameter: that is what OOM-killed the service on 12 November (MF-204 postmortem).

## Tests

- `go test ./...`. The memory store mirrors the Postgres store; change both together.
- The Postgres store test runs only with `PERSONALIZATION_TEST_DATABASE_URL` set, against a database that has the Rails schema loaded (it joins `public.events`). CI runs it.
