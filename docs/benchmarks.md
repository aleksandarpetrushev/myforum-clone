# Discovery benchmark

Measured on 20 October 2026. The JSON files under `backend/tmp/bench/` are generated and are not committed.

## Commands

```bash
cd backend && bin/rails bench:prepare
cd backend && bin/rails bench:discover
cd backend && bin/rails bench:traffic
WEB_CONCURRENCY=2 bin/rails bench:traffic
```

`bench:prepare` loads `my_forum_benchmark` at the ticket scale. `BENCH_SCALE=smoke` loads a smaller copy of the same shape. `bench:discover` times one request at a time with the response cache disabled. `bench:traffic` offers a fixed arrival rate to production-mode Puma.

`completed_rps` is the count of HTTP 200 responses whose finish time falls inside the measurement window, divided by the window length. The generator keeps serving for one more second. Completions in that drain, and requests still queued or in flight at the deadline, are separate counters. They are not part of `completed_rps`.

## Environment

| | |
|---|---|
| Machine | Apple M1 Max, 10 cores, 32 GB |
| Postgres | 18.6, Homebrew, local socket |
| Ruby / Rails / Puma | 3.2.2 / 7.1.6 / 8.0.2 |
| Redis | `localhost:6379`, cache on database 1 |
| Dataset | seed 42; 100,000 events, 50,000 users, 5,000 organizations, 150,000 memberships |
| Indexes | `pg_trgm` GIN on `events.title` (8,376 kB) and `events.description` (29 MB) |
| Discovery | development, null cache, 20 samples, 2 warmup |
| Traffic | production, 300 requests/sec, 5 s warmup, 20 s window, 1 s drain, 2 s client timeout |

On this dataset the concurrent build took 1.0 s for `title` and 5.1 s for `description`.

## Single request

Outsider, published, upcoming, limit 20. Times are the Rails request p50 / p95.

| Scenario | Before indexes | After indexes | Plan after |
|---|---:|---:|---|
| `lumenforge` | 111 / 130 ms | 8.8 / 10 ms | Bitmap heap scan, 0.5 ms execution |
| `practitioners` | 7.7 / 12 ms | 10 / 15 ms | Ordered `starts_at` scan, `ILIKE` filter, 0.9 ms |
| missing token | 102 / 106 ms | 4.3 / 5.8 ms | Bitmap heap scan, 0.3 ms |
| keyword + Berlin + topic | 19 / 21 ms | 27 / 31 ms | Bitmap heap scan, 18 ms |

Before the indexes, `lumenforge` read about 6,060 heap pages and rejected 61,348 rows with `ILIKE`. After the indexes, the same statement uses a `BitmapOr` of `index_events_on_title_trgm` and `index_events_on_description_trgm` and the discovery plan reports 0.5 ms of execution time. `practitioners` still walks `starts_at` and stops after 20 matches. The combined filter got slower: its plan changed from that ordered scan to a bitmap heap scan.

## Traffic at 300 requests/sec

Each row is one run. In-window rate uses only HTTP 200 responses that finished before the deadline.

| Run | In-window | Drain completions | Queued at deadline | In flight at deadline | Abandoned after drain | In-window service p95 |
|---|---:|---:|---:|---:|---:|---:|
| No trigram indexes, 1 worker | 171.4 rps | 502 | 2,271 | 300 | 2,069 | 1,602 ms |
| Trigram indexes, 1 worker | 179.2 rps | 495 | 2,115 | 300 | 1,920 | 1,502 ms |
| Trigram indexes, 2 workers | 299.6 rps | 7 | 0 | 7 | 0 | 37 ms |

One worker still queues. The five threads stay busy, so client service time stays near 1.5 s even after the rare-keyword scan drops from about 100 ms to under 1 ms. Two workers, five threads each, finish 5,993 of the 6,000 window arrivals inside the window. The other seven were in flight at the deadline and finished during the drain. None were abandoned.

An earlier two-worker report of 300.0 rps counted completions from the drain second in the same rate. The 299.6 rps row above replaces that figure.

## Limitations

These runs are one local machine, one sample each, with a warm Postgres cache. They do not measure a deployed fleet, a cold cache, or a rate above 300 requests/sec. Two workers absorbed the offered load, so this run does not show where that configuration saturates.

`service_ms` starts when the client sends the request and includes time spent waiting for a Puma thread. Searches shorter than three characters do not use a trigram index. The list is still ordered only by `starts_at`. On this seed the largest shared start is 5,001 events, and the two page reads in `bench:discover` did not overlap.

## Deploying the indexes

`AddEventTextTrigramIndexes` disables the migration transaction, enables `pg_trgm`, and creates both indexes with `CREATE INDEX CONCURRENTLY`. Reads and writes continue during the build. The build takes longer than a blocking `CREATE INDEX`, and it cannot run inside a transaction. Build time grows with the table and with description length. The 1.0 s and 5.1 s figures above are for this 100,000-row local table.

A failed concurrent build can leave an `INVALID` index. `if_not_exists` does not replace it. Drop the invalid index with `DROP INDEX CONCURRENTLY` and run the migration again.

Rollback drops the description index, then the title index, both concurrently, and then drops `pg_trgm` when nothing else depends on it. Rollback stops if another object still uses the extension.

Databases that already applied the first version of this migration already have the indexes. That version built them with a blocking `CREATE INDEX`. The version timestamp did not change, so those databases will not rebuild the indexes.
