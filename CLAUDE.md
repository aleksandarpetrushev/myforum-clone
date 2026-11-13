# My Forum

Rails API (`backend/`) owns all business data and authorization. Angular (`frontend/`) is the client. A Go service (`personalization/`) ranks events from a read model fed by Rails' outbox. PostgreSQL is the source of truth; Redis is the cache and the Sidekiq broker. Each app has its own `CLAUDE.md` with the rules for that code; read it before editing there.

Design notes are in `docs/design/`, decisions in `docs/decisions/` (ADRs), flows in `docs/registration-flow.md` and `docs/architecture.md`. The docs can lag the code: when they disagree, the code wins and the doc gets fixed in the same PR.

## Tests

```bash
cd backend && timeout 600 bundle exec rspec
cd personalization && go test ./...
cd frontend && npm test -- --watch=false --browsers=ChromeHeadless
```

A PostToolUse hook (`.claude/hooks/run-matching-tests.sh`) runs the matching spec, Go package or type-check after every edit. It is a fast check, not the suite: run the full suite for the apps you touched before calling a change done. CI runs all three on every PR.

## How we work

- **Design before code** on a ticket with decisions in it: a note in `docs/design/MF-xxx.md` with the decisions as a table (choice, and what goes wrong otherwise). Check each decision against every other before calling the design done.
- **Do not decide for the engineer.** When a choice is not settled in the conversation or a design note, ask. Product questions go to the PO.
- **Prove each test guards something.** After writing a test for a rule (a lock, a validation, a filter), remove the rule, watch the test fail, put it back.
- **Cross-service changes:** the consumer deploys first. Go must understand a new contract field or `event_type` before Rails writes it (`personalization/contract/README.md`).
- **Commits:** one logical change, all suites green. The message is one sentence saying what changed for a user or an operator, not "update X". Branch per ticket (`mf-301-...`).
- **Pull requests:** what changed, decisions with reasons, how it was tested, open items. Every open item gets a ticket or an explicit "won't do" before merge. A human other than the author approves (`docs/ai-working-agreement.md`).

## Local environment pitfalls

- Development Sidekiq runs one `ProcessOutboxJob` chain. Never enqueue it by hand; check the scheduled set first, and use "Retry now" on the existing job.
- End-to-end runs create test users and events. Clean them up together with their queued, scheduled and retrying jobs, and delete `analytics_events` before outbox rows (foreign key).
- psql sessions use the Europe/Skopje time zone; timestamp columns are UTC without zone. Compare times in Rails, or use `AT TIME ZONE 'UTC'`.

## Never

- Put production data, user personal data, secrets or `.env` contents into a prompt, a test fixture or a commit.
- Push to `main`, force-push a shared branch, or merge without approval.
- Run `db:reset`, `db:drop` or destructive SQL against anything but a local or test database.
