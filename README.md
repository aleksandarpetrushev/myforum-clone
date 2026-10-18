# My Forum

A training application for event discovery, registration, and simple recommendations. Rails owns the transactional data. Angular is the client. A Go service ranks events from a read model. PostgreSQL is the source of truth. Redis is the cache and the Sidekiq broker.

## Architecture

```mermaid
flowchart LR
  Angular[Angular] --> Rails[Rails API]
  Rails --> Postgres[(PostgreSQL)]
  Rails --> Redis[(Redis)]
  Rails --> Outbox[Outbox]
  Outbox --> Sidekiq[Sidekiq]
  Sidekiq --> Go[Go personalization]
```

See [docs/architecture.md](docs/architecture.md) and [docs/registration-flow.md](docs/registration-flow.md).

## Local setup

PostgreSQL and Redis can come from Docker Compose. The app processes run on the host. Compose publishes Postgres on port **5433** so it does not collide with a Postgres already listening on 5432.

```bash
docker compose up -d
export DATABASE_HOST=localhost
export DATABASE_PORT=5433
export DATABASE_USERNAME=postgres
export DATABASE_PASSWORD=postgres
export DATABASE_URL=postgres://postgres:postgres@localhost:5433/my_forum_development?sslmode=disable
```

If you already use a local Postgres on the default socket, skip those variables. `bin/rails db:prepare` will create `my_forum_development` and `my_forum_test` with your OS user.

```bash
cd backend
bundle install
bin/rails db:prepare
bin/rails db:seed
bin/rails server
```

In other terminals:

```bash
cd backend && bundle exec sidekiq
cd personalization && go run ./cmd/personalization
cd frontend && npm install && npm start
```

Sidekiq needs Redis on `redis://localhost:6379/0`. Rails cache uses `redis://localhost:6379/1`.

Enqueue the outbox poller once after Sidekiq is up:

```bash
cd backend && bin/rails runner "ProcessOutboxJob.perform_later"
```

The Go service listens on `:8080`. It creates a `personalization` schema in the same database.

`make setup` installs dependencies and prepares the database. `make test` runs the three test suites. `make dev` prints the process commands.

## Seed credentials

Every seeded user uses the password `password`.

| Email | Notes |
|---|---|
| `alex@example.com` | Admin of one organization, member of another |
| `member02@example.com` through `member30@example.com` | The first eight users are organization admins |

The seed creates 8 organizations, 15 topics, 100 events, speakers, follows, and a mix of empty, popular, and nearly full events.

## API

- `POST /api/session` with `email` and `password` returns a JWT
- Send `Authorization: Bearer <token>` on later requests
- `GET /api/events` supports `q`, `topic_id`, `location`, `upcoming`, and `page`. Results include public events and organization-restricted events the caller may see.
- `GET /api/events/:id`
- `POST /api/events/:id/register`
- `PATCH /api/events/:id` for an organizer admin
- `GET /api/topics`
- `POST /api/topics/:id/follow`
- `DELETE /api/topics/:id/follow`
- `GET /api/me/registrations`
- `GET /api/me/notifications`
- `GET /health` and `GET /ready`

Production requires `DATABASE_URL`, `REDIS_URL`, `JWT_SECRET`, and `RAILS_MASTER_KEY`.

## Tests

```bash
cd backend && bundle exec rspec
cd personalization && go test ./...
cd frontend && npm test -- --watch=false
```
