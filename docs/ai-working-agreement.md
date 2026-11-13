# AI working agreement

How the team uses AI coding tools (Claude Code, Cursor) on My Forum. Agreed for MF-301 on 2026-11-13; revisit at each sprint retro with `docs/journal.md`.

## The engineer owns the change

Whoever opens the PR answers for every line in it, whoever typed it. "The AI wrote it" is never a reason in review or in a postmortem.

## What the AI may do alone

- Read the code, run tests, linters, benchmarks and local services.
- Write code, tests and docs on a feature branch, and commit there.
- Draft design notes and ADRs from decisions the engineer or PO already made, and list the decisions still open.
- Review a diff and propose fixes.
- Run end-to-end checks against the local environment, and clean up the data they create.

## What needs a human first

| Action | Who |
|---|---|
| Any product decision (rules users see, wording of notifications, what counts as in scope) | PO |
| Any design decision left open in a design note or ADR | Engineer |
| Merging a PR | A human reviewer other than the author; CI green |
| Migrations that rewrite or delete data, and any script run against shared or production data | Engineer, with a dry run reviewed first |
| A change to the Rails–Go contract | Engineer; Go deploys first |
| Pushing to `main`, force-pushing a shared branch, deleting branches or data | Engineer, explicitly |
| Messages to organizers, users, support or ops | PO or incident commander |
| Changing `CLAUDE.md`, `.claude/settings.json`, hooks or CI | Engineer, in a reviewed PR |

## What never goes into a prompt

- Production data, database dumps, logs with user data, real names or email addresses. Use the seed or benchmark data; anonymize anything copied from an incident.
- Secrets: `.env`, credentials, API keys, tokens, `config/master.key`.
- Customer or partner documents not already in this repository.

`.claude/settings.local.json` holds personal settings and stays out of git. The CI AI review sends the PR diff and repository files to Anthropic's API under the company's agreement; nothing else leaves the runner.

## Checks that run without anyone remembering

| Check | Where | Blocks? |
|---|---|---|
| Matching spec, Go package or type-check after every AI edit | `.claude/hooks/run-matching-tests.sh` | Feeds failures back to the AI |
| RSpec, Go tests (including the Postgres store), Angular build and Karma | `.github/workflows/ci.yml` | Yes |
| AI review comment on the PR | `ci.yml`, job `ai-review` | No. Findings are advisory; the reviewer decides which become fixes. Promote a category to blocking only after a sprint of it being right. Decided by the engineer, 2026-11-13: tests block, the AI review advises |
| Outbox row matches the Rails–Go contract | `spec/support/personalization_contract.rb` | Yes, through RSpec |

## Learning from mistakes

When the AI gets something wrong that review, a test or an incident catches, add a row to `docs/journal.md` and, if it could happen again, a rule in the right `CLAUDE.md` or a check. Keep `CLAUDE.md` to rules the model actually gets wrong; remove a rule that has not mattered for two sprints.

## GitLab

The team's production CI is GitLab. This repository is on GitHub, so CI is GitHub Actions. The mapping is one-to-one: each job becomes a `.gitlab-ci.yml` job with the same `services:` (Postgres 16, Redis 7) and scripts; `continue-on-error: true` becomes `allow_failure: true`; the AI review becomes a merge-request job using a masked `ANTHROPIC_API_KEY` CI variable, limited to `rules: - if: $CI_PIPELINE_SOURCE == "merge_request_event"`.
