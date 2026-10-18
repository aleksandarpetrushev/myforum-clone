# Bootstrap plan

This repository replaces an earlier Rails prototype (articles, header-based user id, a stub event policy) with a My Forum V1 monorepo. The git root stays here. There is no nested `my-forum/` directory.

## Layout

- `backend/` — Rails 7.1 API, PostgreSQL, Redis, Sidekiq, Pundit, RSpec
- `frontend/` — Angular standalone client
- `personalization/` — Go recommendation service
- `docs/` — architecture, registration flow, ADRs
- `docker-compose.yml` — PostgreSQL and Redis only
- `Makefile` — `setup`, `dev`, `test`

## Order

1. Generate an API-only Rails app and remove the root prototype.
2. Add the domain schema, JWT auth, policies, services, outbox, jobs, cache, and APIs.
3. Seed realistic data and cover registration, follows, authorization, and the outbox with RSpec.
4. Add the Go service: health, recommendations, and event ingest into a Postgres read model.
5. Add the Angular client: login, discovery, event detail, registrations, topics, notifications.
6. Add Compose, the Makefile, README, architecture docs, and four short ADRs.
7. Run Rails, Go, and Angular checks. Record results in `docs/bootstrap-report.md`.

## Explicitly out of scope

Organization-restricted discovery, OpenSearch, Kafka, splitting events and registration into services, real payments, ML ranking, multi-region, sharding, and Kubernetes.

## Local processes

Compose starts PostgreSQL and Redis. Rails, Sidekiq, Go, and Angular run on the host.
