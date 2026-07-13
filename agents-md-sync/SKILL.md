---
name: agents-md-sync
description: >-
  Incrementally sync session learnings into every applicable tracked AGENTS.md
  and agent_docs file immediately before a commit or explicit session wrap-up.
  Use only after implementation is complete; keep root and nested routers lean,
  update relevant indexed leaf documentation, and prune obsolete guidance.
  Full hierarchy audits or rewrites belong to agents-md-init.
---

# AGENTS.md Sync

Run at the end of an implementation session, immediately before staging a
commit or wrapping up. Capture only stable, reusable knowledge learned during
the complete session.

## Timing guard

- If named inside a longer task, defer until implementation and verification are
  complete.
- A casual mention of commit or docs is not a trigger.
- For a broad hierarchy rewrite, stop and use `agents-md-init` instead.

## Discover the hierarchy

1. Glob every tracked `AGENTS.md` in the repository and read all of them. Never
   assume the root is the only instruction file.
2. Read every `agent_docs/**/README.md` category index.
3. Use changed paths and candidate learnings to select only the relevant leaf
   documents. Do not load the entire knowledge base on every commit.
4. Inspect the session diff, tests, failures, decisions, and current code before
   treating a candidate learning as true.

## Persistence filter

Add a learning only when all are true:

1. **Reusable** — useful in future work, not merely today's implementation.
2. **Non-obvious** — not clear from code, types, tests, or configuration.
3. **Not tool-owned** — not formatting, lint, generated output, or task state.
4. **Stable** — unlikely to be obsolete soon.

When uncertain, leave it out. Do not copy Beads status, handoff content,
chronological session history, or ignored local evidence into agent docs.

## Place at the narrowest scope

| Learning | Destination |
|---|---|
| Universal project identity or boundary | Root `AGENTS.md` |
| Stable domain-specific instruction or routing | Nearest tracked nested `AGENTS.md` |
| Detailed architecture, invariant, evidence, or runbook | Relevant agent-doc leaf |
| New leaf within an existing domain | Leaf plus its category index |
| New top-level domain | New category index plus one root link |

Topical ownership wins over the module where the learning happened.

## Edit and prune

- Merge duplicates and replace contradictions; never append blindly.
- Prune dead paths, obsolete workarounds, removed behavior, stale TODOs, and
  prose duplicated by tools.
- When changing a leaf or router, check its siblings and index for stale routing.
- Keep root and nested routers short; move detail downward instead of expanding
  always-loaded context.
- Never mutate Beads, handoffs, commits, or deployments from this skill.

## Validate and report

1. Re-glob all tracked `AGENTS.md` and verify their relative links.
2. Verify each changed category index and leaf link.
3. Review the diff for duplicated or task-specific prose.
4. Report what was added, removed, moved, and considered but rejected.

Apply edits directly at the correct end-of-session moment so they can be
included in the same authorized commit.
