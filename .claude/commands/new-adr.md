---
description: Draft the next architecture decision record in docs/decisions
argument-hint: <the decision, in a few words>
---

Draft an ADR for: $ARGUMENTS

1. Number it one above the highest file in `docs/decisions/` (four digits). Name the file `NNNN-<decision-in-kebab-case>.md`. If a ticket already reserved a number that is now taken (MF-303 planned 0008; 0008 went to the waitlist), use the next free one and say so.
2. Use the structure of `docs/decisions/0005-…` to `0008-…`:
   - Title: the decision as a sentence ("The waitlist is two registration states…"), not a topic.
   - `Status: accepted, <date>, for <ticket>.` (or `proposed` until the PO or team agrees).
   - **Summary**: exactly three sentences a product owner can read: what we decided, the main reason, and when we would revisit.
   - **Context**: the facts from the code that forced a decision, with file paths. Read the code; do not describe it from memory.
   - **Decision**: bullets, concrete enough that a reviewer can check the code against them.
   - **Alternatives**: a table, one row per option, with "why not" naming the failure each would cause.
   - **Consequences**: what changes for other code, ops and tests, including costs.
   - **Reverse if**: measurable triggers (a metric and a threshold, or a product need), never "if it gets slow".
3. Do not decide for the engineer. If a choice in the ADR is not already settled in the conversation or a design note, list it under a "Decisions needed" heading at the end and stop.
