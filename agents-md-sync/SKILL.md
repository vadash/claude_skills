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

At session end, before staging or wrap-up, persist only stable, reusable
knowledge learned during the complete implementation.

## Timing

- If named within a longer task, defer until implementation and verification
  finish.
- A casual mention of commit or docs is not a trigger.
- Use `agents-md-init` for broad hierarchy rewrites.

## Discover and verify

1. Glob and read every tracked `AGENTS.md`; never assume root is alone.
2. Read every `agent_docs/**/README.md` index.
3. Select relevant leaves from changed paths and candidate learnings; do not
   load the whole knowledge base by default.
4. Check candidates against current code, diff, tests, failures, and decisions.

## Persistence filter

Persist only content that is:

1. reusable beyond current task;
2. non-obvious from code, types, tests, or configuration;
3. not owned by formatters, linters, generators, or task tracking;
4. stable enough for future sessions.

When uncertain, omit it. Never copy Beads state, handoffs, session chronology,
or ignored local evidence into agent docs.

## Place narrowly

| Content | Owner |
|---|---|
| Universal project identity or boundary | Root `AGENTS.md` |
| Domain instruction or routing | Nearest nested `AGENTS.md` |
| Architecture, invariant, evidence, runbook | Relevant leaf |
| New leaf in existing domain | Leaf and category index |
| New top-level domain | Category index and one root link |

Topical ownership beats location where knowledge was discovered.

## Edit, prune, validate

- Merge duplicates and replace contradictions; never append blindly.
- Remove dead paths, obsolete workarounds/behavior/TODOs, and tool-owned prose.
- When changing a router or leaf, check its index and siblings for stale routes.
- Keep routers short; move detail into leaves.
- Re-glob tracked `AGENTS.md`; verify changed indexes and all relative links.
- Review diff for duplicate or task-specific prose.
- Report additions, removals, moves, and rejected candidates.

Edit directly at the correct end-of-session moment for inclusion in the same
authorized commit. Never mutate Beads, handoffs, commits, or deployments.
