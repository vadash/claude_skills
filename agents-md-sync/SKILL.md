---
name: agents-md-sync
description: >-
  Incrementally sync session learnings into every applicable tracked AGENTS.md
  and agent_docs file immediately before a commit or explicit session wrap-up.
  Use only after implementation is complete; keep routers lean, update relevant
  indexed leaves, and prune obsolete guidance. Use agents-md-init for full
  hierarchy audits or rewrites.
---

# AGENTS.md Sync

At session end, before staging or wrap-up, persist only stable, reusable knowledge learned during the complete implementation. Protect the **Progressive Disclosure** architecture from context bloat.

## Timing
- Run only after implementation and verification are fully complete.
- Do not run for casual mentions of "commit" or "docs".
- If the tree requires a massive overhaul, stop and recommend `agents-md-init`.

## Discover & Filter
1. Glob and read the root `AGENTS.md`, relevant nested `AGENTS.md` routers, and targeted `agent_docs/` leaves.
2. Check your candidate learnings against the diff and tests.
3. **Strict Persistence Filter - ONLY record if:**
   - It is a non-obvious "gotcha" (e.g., "Library X silently drops connections if Y is null").
   - It is a new operational step or runbook update.
   - It is a permanent architectural decision (ADR).
4. **DO NOT record if:**
   - A tool can enforce it (Linters, Prettier, TypeScript).
   - It is task-specific chronological state ("Yesterday we tried X and it failed").
   - It is already obvious from reading the code types.

## Abstract Over Code
The recurring failure mode here is writing implementation detail into the docs — function names, file paths, line numbers, code expressions. These rot the moment the codebase refactors, and a future agent reading the doc has `grep` anyway. The doc's job is to capture the durable *what* and *why*; the agent will find the *where* itself.

**Strip from any candidate learning before writing:**
- Function, method, variable, or class names (`runElasticAutoCycle`, `parseStateLines`).
- File paths and line numbers (`src/core/summarizer-state.js`, `:142`).
- Implementation expressions (`Date.UTC(year, month-1, day).getUTCDay()`).
- Test file names.
- Call-site and callback listings ("routes through `summarizerQueue.request() -> drainOneCycle`").

**Rewrite as the durable contract:**
- BAD: `parseStateLines` (`src/core/summarizer-state.js`) re-derives the weekday via `Date.UTC(year, month-1, day).getUTCDay()` because Call #14 emitted `2024-07-07 06 Wed` when Jul 7 2024 is Sun.
- GOOD: The `[STATE] current_date_time` weekday token is unreliable — the model hallucinates it. State parsing re-derives weekday from the ISO date on every read, so a wrong day never carries forward into stored text or the next prompt. Any change to date normalization must preserve this correction.

**The one exception:** a single high-level module pointer when *the location itself is the knowledge* (e.g., "auto-cycle gating lives in the summarizer engine, not in callers"). Name the module, not the function — and only when routing an agent there is the point of the entry.

## Place Narrowly
Topical ownership beats the location where the knowledge was discovered.

| Content Type | Target File | Action |
|---|---|---|
| Universal project identity or global boundary | Root `AGENTS.md` | Keep it brief. |
| Domain instruction or routing logic | Nearest nested `AGENTS.md` | Add conditional pointer to a leaf. |
| Specific Gotchas, Runbooks, or Details | Relevant leaf in `agent_docs/` | Append or update existing lists. |
| Entirely new domain | Root Map + `agent_docs/` | Create directory, `<domain>.md` index (named after the domain — never `README.md`), and leaf. |

## Edit, Prune, Validate
- **Never append blindly.** Replace contradictions and merge duplicates. Also strip any code references that slipped in — see *Abstract Over Code*.
- **Keep routers lean.** If a nested `AGENTS.md` is getting too long, move the details into a `gotchas.md` leaf and leave a pointer.
- Prune dead paths, obsolete workarounds, and TODOs.
- Re-glob to ensure all relative links between routers and leaves are valid.
- Report what was added, removed, or rejected (e.g., "Skipped saving styling rule because ESLint enforces it").

Edit directly at the correct end-of-session moment for inclusion in the same authorized commit. Never mutate external state tools (like Beads) or trigger deployments.
