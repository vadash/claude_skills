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

## Place Narrowly
Topical ownership beats the location where the knowledge was discovered.

| Content Type | Target File | Action |
|---|---|---|
| Universal project identity or global boundary | Root `AGENTS.md` | Keep it brief. |
| Domain instruction or routing logic | Nearest nested `AGENTS.md` | Add conditional pointer to a leaf. |
| Specific Gotchas, Runbooks, or Details | Relevant leaf in `agent_docs/` | Append or update existing lists. |
| Entirely new domain | Root Map + `agent_docs/` | Create directory, `README.md` router, and leaf. |

## Edit, Prune, Validate
- **Never append blindly.** Replace contradictions and merge duplicates.
- **Keep routers lean.** If a nested `AGENTS.md` is getting too long, move the details into a `gotchas.md` leaf and leave a pointer.
- Prune dead paths, obsolete workarounds, and TODOs.
- Re-glob to ensure all relative links between routers and leaves are valid.
- Report what was added, removed, or rejected (e.g., "Skipped saving styling rule because ESLint enforces it").

Edit directly at the correct end-of-session moment for inclusion in the same authorized commit. Never mutate external state tools (like Beads) or trigger deployments.
