# AI journal

What the AI (Claude Code, and Cursor before it) got wrong in Sprints 1–2, how it was caught, and the rule or check it became. Reconstructed on 2026-11-13 for MF-301 from review findings, the MF-204 postmortem and the session history; kept going from here at each sprint retro.

"Became" points at the rule in `CLAUDE.md`, `backend/CLAUDE.md`, `frontend/CLAUDE.md`, `personalization/CLAUDE.md`, the hook, or a test.

## Mistakes and what they became

| Date | Ticket | What went wrong | Caught by | Became |
|---|---|---|---|---|
| 2026-10-29 | MF-103 | Design showed Cancel on events already in progress, though the server refuses it | `/code-review` | Root: check each decision against every other before calling a design done |
| 2026-11-09 | MF-201 | `Personalization::Unavailable` defined inside another file; a `rescue` naming it could raise `NameError` before that file loaded | The AI, before commit | Backend: one constant per file (Zeitwerk) |
| 2026-11-09 | MF-201 | `Net::HTTP` retries an idempotent GET once after a read timeout, doubling the "1 s" timeout | `/code-review` | Backend: calls to Go go through `Personalization::Http` (retries off) |
| 2026-11-09 | MF-106 | `capacity_raised?` read after `@event.reload`, which forgets what the save changed, so it was always false | The AI, before commit | Backend: read `saved_changes` before any `reload` |
| 2026-11-09 | MF-106 | Local Postgres 18 rewrote every check constraint in `schema.rb`, burying the one real change | The AI, in the diff | Backend: keep only real lines in `schema.rb` |
| 2026-11-09 | MF-106 | Only organizer edits bumped `events.revision`; cancellations and seat changes did not, so Go could not order those snapshots | `/code-review` | Backend: every change to an event row bumps `revision` |
| 2026-11-09 | MF-203 | Design answered an unsupported contract version with 204 and skipped it, so Rails marked it published and the change was lost | `/code-review` | Personalization: never 2xx a payload you did not apply; `unsupported_contract` + `deferred` |
| 2026-11-09 | MF-203 | Ingest decoded into a typed struct, so a wrong field type became 422, which stops the outbox | `/code-review` | Personalization: decode loosely, log contract problems, never refuse them |
| 2026-11-09 | MF-203 | Rollout order "Rails first" proposed (by the engineer); would have lost every new-version row | Challenge in refinement | Root and contract README: consumer deploys first |
| 2026-11-09 | MF-104 / MF-203 | A `;` inside Mermaid sequence messages breaks the diagram | The AI, by hand-check | `/trace-flow` command note |
| 2026-11-10 | MF-202 | A spec simulated a race with a second DB connection while the service held the event row lock: the suite deadlocked | Hung test run | Backend: never make a second connection wait on a lock the test holds; run suites with a timeout |
| 2026-11-10 | MF-202 | `freeze_time` rounds to whole seconds, and lazy `let` records created inside `travel_to` got past start times: two false failures | The AI, reading failures | Backend: create time-sensitive records inside the frozen or travelled time |
| 2026-11-10 | MF-202 | Concurrency spec passed even with each lock removed: several guards overlapped, so it proved nothing about any one | Mutation check | Root: after writing a test for a guard, remove the guard and watch it fail |
| 2026-11-10 | MF-202 | An offered seat whose expiry job had not run yet stayed actionable in Upcoming after the event started | The AI, via a failing spec | Backend: derive "still actionable" from times, not only from status |
| 2026-11-10 | MF-202 | `Personalization::DeliveryError` lived inside `deliver_event.rb` (same mistake as `Unavailable`), so a spec failed about two runs in three | Flaky suite | Backend: one constant per file (repeat offender, so it is in the hook's path) |
| 2026-11-10 | MF-201–MF-202 | End-to-end cleanups deleted test users and events while their jobs were still queued, leaving 12 jobs retrying forever | Sidekiq log in MF-202 run | Root: clean up queued and retrying jobs with test data |
| 2026-11-10 | MF-201 / MF-203 | `ProcessOutboxJob` enqueued by hand in development while a chain already ran: four chains in Redis | Inspecting Sidekiq in MF-202 run | Root: never enqueue `ProcessOutboxJob` by hand; check the scheduled set |
| 2026-11-10 | MF-202 | psql compared `timestamp without time zone` columns with `now()` in the session zone (Europe/Skopje): an offer looked 60 minutes short | The AI, by checking in Rails | Backend: compare times in Rails, or `AT TIME ZONE 'UTC'` in SQL |
| 2026-11-12 | MF-204 | Recommendations loaded every eligible event per request (1.6 GB at 50 requests); Go was OOM-killed | Incident | Personalization: stream candidates, keep the top N |
| 2026-11-12 | MF-204 | One failed delivery failed the whole outbox poller; Sidekiq backoff turned 30 min of crashes into 63 min of silence | Incident | Backend: per-row failure handling in `Outbox::Publisher` (PR #10) |
| 2026-11-12 | MF-105 | Review suggested `status_changed?` for new records; a new event defaults to `published`, so it never fires | The AI, by measuring | Backend: a new record's default does not count as a change |
| 2026-11-12 | MF-105 | Event page kept one draft's publish errors when the route switched to another event | `/code-review` | Frontend: reset per-record state when the route param changes |
| 2026-11-12 | MF-204 | Merged own PRs without review approval (GitHub refuses self-approval) | `gh` | `docs/ai-working-agreement.md`: a human other than the author approves |

## Retro notes

Add one paragraph per sprint here: what the AI did well, where it misled us, and the one change to `CLAUDE.md`, the hook or a prompt it led to.
