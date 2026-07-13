---
name: agents-md-init
description: Manually bootstrap a repository AGENTS.md and agent_docs hierarchy, or explicitly audit and refactor an existing hierarchy for progressive disclosure. Use only when the user directly requests initialization, a full memory/documentation rewrite, or a structural AGENTS.md optimization; routine end-of-session maintenance belongs to agents-md-sync.
disable-model-invocation: true
---

# AGENTS.md Init and Refactor

Build or deliberately restructure the repository's agent-memory hierarchy. This
is the manual, high-judgment counterpart to `agents-md-sync`, which handles
small pre-commit updates.

## Select the operation

- **Bootstrap** — no root `AGENTS.md` exists. Create the initial hierarchy.
- **Refactor** — a root `AGENTS.md` exists and the user explicitly requested an
  audit, rewrite, reorganization, or progressive-disclosure improvement.

If a root file exists without an explicit refactor request, stop and direct the
user to `agents-md-sync`.

## Establish truth

1. Read user-provided or existing narrative documentation for intent and
   vocabulary.
2. Discover every tracked `AGENTS.md`, documentation index, and agent-doc leaf.
3. In refactor mode, read the complete existing hierarchy once so no durable
   rule, decision, evidence item, or runbook is silently lost.
4. Explore code, manifests, scripts, and configuration to verify claimed facts.
5. Trust code for current mechanical facts; surface unresolved intent conflicts
   as questions rather than silently choosing.

Classify material as:

- **Verified and stable** — safe to persist.
- **Inferred or conflicting** — ask the user; do not assert it as a rule.
- **Mutable work state** — move to Beads, not repository documentation.
- **Tool-enforced mechanics** — point to the tool or command; do not restate rules.

## Design progressive disclosure

Use the smallest hierarchy that routes future agents reliably:

1. **Root `AGENTS.md`** — universal WHAT, WHY, HOW, critical boundaries,
   top-level repository map, verification entry points, and short links to
   documentation categories. Aim for roughly 60 lines when practical.
2. **Nested `AGENTS.md`** — add only at stable, high-risk domain boundaries where
   automatic scoped loading materially improves correctness. Keep each one a
   concise router; do not copy the leaf documentation into it.
3. **Category indexes** — use self-describing `agent_docs/<domain>/README.md`
   files to route from a broad domain to focused leaves.
4. **Leaf documents** — store cohesive architecture, invariants, evidence, and
   runbooks. Split large chronological or multi-domain files; avoid tiny files
   that cannot stand alone.

Prefer pointers to authoritative code and configuration over copied snippets.
Do not list every nested router or leaf from the root file.

## Draft before writing

Present an approval-ready proposal containing:

- the exact root and nested router structure;
- the category/leaf tree and routing descriptions;
- a migration map from old files to new owners;
- content to prune, with reasons;
- open questions and conflicts.

Do not write until the user approves the structure. In refactor mode, preserve
substantive existing content by default and make deletions explicit.

## Apply and validate

After approval:

1. Write the new hierarchy and update all relative links.
2. Remove superseded files only after their content has a verified owner.
3. Search repository and durable task text for stale paths.
4. Validate every tracked `AGENTS.md` and agent-doc link.
5. Confirm root and nested routers remain concise and non-duplicative.
6. Compare migrated historical/evidence content with the pre-refactor version.
7. Report additions, moves, pruning, rejected candidates, and unresolved items.

Do not commit, push, deploy, or mutate Beads beyond the task explicitly
authorized for the refactor.
