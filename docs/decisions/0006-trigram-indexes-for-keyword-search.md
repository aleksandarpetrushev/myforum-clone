# Keyword search uses Postgres trigram indexes, not a search service

Status: accepted. Recorded on 2026-10-29 for `0613372` and `39ed42c`, which made the change on 2026-10-20.

## Summary

Event keyword search stays an `ILIKE` query in Postgres, made fast by trigram indexes on title and description. On 100,000 events the slowest keyword search dropped from 111 ms to 9 ms, without running and syncing a second datastore. We will add a search service when the product needs ranking, typo tolerance or facets, or when search gets slow at ten times today's data.

## Context

`Event.matching_text` filters with `title ILIKE '%term%' OR description ILIKE '%term%'`. A leading wildcard cannot use a B-tree index, so a rare term scanned the table: on the benchmark dataset, `lumenforge` read about 6,060 heap pages and rejected 61,348 rows.

The benchmark ([benchmarks.md](../benchmarks.md)) used 100,000 events, 50,000 users and 5,000 organizations on one local machine.

## Decision

- Enable `pg_trgm` and add GIN trigram indexes on `events.title` and `events.description`.
- Build them with `CREATE INDEX CONCURRENTLY`, so reads and writes continue during the build.
- Keep the query unchanged: `ILIKE`, ordered by `starts_at, id`. Search stays synchronous, with no copy of the data to keep in sync.

## Alternatives

| Option | Why not |
|---|---|
| Elasticsearch or OpenSearch | A second datastore to run, secure and keep in sync through the outbox; visibility filtering would have to be reproduced there. Nothing asked for its features yet |
| Postgres full-text search (`tsvector`) | Matches whole words after stemming, so a partial term like `lumen` would stop matching. Changes search behaviour, not only its speed |
| No index | 111 ms p50 for a rare term at 100,000 events, growing with the table |

## Consequences

| Measure, 100,000 events | Before | After |
|---|---:|---:|
| Rare term (`lumenforge`), p50 / p95 | 111 / 130 ms | 8.8 / 10 ms |
| Missing term, p50 / p95 | 102 / 106 ms | 4.3 / 5.8 ms |
| Keyword + location + topic, p50 / p95 | 19 / 21 ms | 27 / 31 ms |
| Index size | none | 8.4 MB title, 29 MB description |

- The combined filter got slower: the planner now picks the trigram bitmap scan over the ordered `starts_at` scan. Acceptable at 31 ms; watch it.
- Terms shorter than three characters cannot use a trigram index and still scan.
- Every event insert and description update also updates two GIN indexes.
- Results are in date order, not by relevance. That is a product limit, not a speed limit.

## Reverse if

- **Features:** the product asks for relevance ranking, typo tolerance, synonyms, faceted counts, or search in more than one language. Trigram `ILIKE` cannot do these, and this is the more likely trigger.
- **Scale:** keyword search p95 goes above 200 ms at production load, or the `events` table passes 1,000,000 rows (ten times the measured size) without a new benchmark showing it is still under that budget.
