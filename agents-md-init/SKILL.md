---
name: agents-md-init
description: Manually bootstrap a repository AGENTS.md and agent_docs hierarchy, or explicitly audit and refactor an existing hierarchy for progressive disclosure. Use only when the user directly requests initialization, a full memory/documentation rewrite, or structural AGENTS.md optimization; use agents-md-sync for routine end-of-session maintenance.
disable-model-invocation: true
---

# AGENTS.md Init and Refactor

Build or deliberately restructure repository agent memory. `agents-md-sync`
handles small pre-commit updates.

## Choose mode

- **Bootstrap:** no root `AGENTS.md`; create the hierarchy.
- **Refactor:** root exists and user explicitly requested an audit, rewrite,
  reorganization, or progressive-disclosure improvement.

If root exists without an explicit refactor request, stop and direct user to
`agents-md-sync`.

## Establish truth

1. Read supplied and existing narrative docs for intent and vocabulary.
2. Discover every tracked `AGENTS.md`, documentation index, and agent-doc leaf.
3. For refactors, read the complete hierarchy once; preserve every durable rule,
   decision, evidence item, and runbook unless deletion is explicit.
4. Verify claims against code, manifests, scripts, and configuration.
5. Trust code for current mechanics; ask about unresolved intent conflicts.

Classify content:

- verified, stable knowledge: persist;
- inferred or conflicting claims: ask, never assert;
- mutable work state: Beads;
- tool-enforced mechanics: point to source, do not restate.

## Design progressive disclosure

Use smallest hierarchy that routes future agents reliably:

1. Root `AGENTS.md`: universal WHAT, WHY, HOW, critical boundaries, repository
   map, verification entry points, and short category links. Aim for about 60
   lines when practical.
2. Nested `AGENTS.md`: concise routers only at stable, high-risk domain
   boundaries where scoped loading improves correctness.
3. `agent_docs/<domain>/README.md`: route broad domains to focused leaves.
4. Leaves: cohesive architecture, invariants, evidence, and runbooks. Split
   multi-domain or large chronological files; avoid tiny fragments.

Prefer pointers to authoritative code/configuration over copied content. Do not
list every router or leaf from root.

## Propose before writing

Present for approval:

- exact root and nested-router structure;
- category/leaf tree with routing descriptions;
- old-to-new migration map;
- proposed pruning with reasons;
- conflicts and open questions.

Write only after approval. Preserve substantive content by default; make every
deletion explicit.

## Apply and validate

1. Write hierarchy and repair relative links.
2. Remove superseded files only after assigning all content a verified owner.
3. Search repository and durable task text for stale paths.
4. Validate every tracked `AGENTS.md` and agent-doc link.
5. Check routers stay concise and non-duplicative.
6. Compare migrated history/evidence with pre-refactor content.
7. Report additions, moves, pruning, rejected candidates, and unresolved items.

Do not commit, push, deploy, or mutate Beads beyond explicit authorization.
