# Agent Memory Rules

Canonical writing rules shared by `agents-md-sync` and `agents-md-init`. Apply to every entry written into `AGENTS.md` routers or `agent_docs/` leaves.

## Succinctness
- Write in ASD-STE100 Simplified Technical English. Short sentences. Active voice. One idea per sentence.
- One fact per bullet. Hard cap: 2 lines, 25 words.
- No history, no war stories, no "used to be X, now Y", no commit-by-commit narrative.
- No prose paragraphs. Bullets only.
- If a bullet exceeds the cap, split or cut. Do not soften the cap with "unless needed".

## What to record
Record only if one holds:
- Non-obvious gotcha.
- Operational runbook step.
- Permanent architectural decision.

Skip if:
- A linter, formatter, or type system enforces it.
- It is task-state ("we tried X, it failed").
- It is obvious from types or signatures.

## Strip code, write contracts
The doc captures the durable what and why. The reader has `grep`.

Strip before writing:
- Function, method, variable, class names.
- File paths and line numbers.
- Code expressions, regex, call-site listings.
- Test file names.

Rewrite as the contract:
- BAD: `parseStateLines` (`src/core/summarizer-state.js`) re-derives the weekday via `Date.UTC(year, month-1, day).getUTCDay()` because Call #14 emitted `2024-07-07 06 Wed` when Jul 7 2024 is Sun.
- GOOD: The `[STATE] current_date_time` weekday token is unreliable. Re-derive it from the ISO date on every read.

One exception: a single module pointer when routing an agent there is the point of the entry. Name the module, not the function.
