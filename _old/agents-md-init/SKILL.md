---
name: agents-md-init
description: Manually bootstrap a repository AGENTS.md and agent_docs hierarchy
disable-model-invocation: true
---

# AGENTS.md Init and Refactor

Build or deliberately restructure repository agent memory. Maximize context efficiency through **Progressive Disclosure**.

## Apply the rules
Read `../agents-md-sync/references/rules.md` and apply it to every entry. Summary: ASD-STE100, one fact per bullet, ≤ 2 lines / 25 words, no history, strip code identifiers.

## Choose Mode
- **Bootstrap:** No root `AGENTS.md` exists; create the hierarchy from scratch.
- **Refactor:** Root exists and user explicitly requested an audit, rewrite, reorganization, or bloat-reduction.

If root exists without an explicit refactor request, stop and direct the user to `agents-md-sync`.

## 1. Establish truth and classify
1. Read supplied narrative docs, existing `AGENTS.md`, and `agent_docs/` leaves.
2. Verify claims against code, tests, and configuration. Trust code for mechanics.
3. Classify each item:
   - **Stable knowledge (gotchas, runbooks, ADRs):** persist in leaves, written per `rules.md`.
   - **Tool-enforced (linters, formatters, types):** delete.
   - **Mutable state (tasks, logs, chronology):** delete. Leave to task trackers.
   - **Redundant lore or bloat:** condense or delete.
   - **Code references (function names, paths, line numbers, expressions):** strip.

## 2. Design the hierarchy
Use the smallest possible hierarchy to route future agents.

- **Root `AGENTS.md` (the map).** < 60 lines. WHAT, WHY, global boundaries, universal commands, documentation map. No deep architectural detail.
- **Nested `AGENTS.md` (the routers).** Conditional pointers: "If modifying X, read `agent_docs/<domain>/x_gotchas.md`." Few strict domain bullets max, no prose.
- **`agent_docs/<domain>/<domain>.md` (domain indexes).** Named after the domain, never `README.md` — multiple `README.md` files collide and a glob-driven edit lands on the wrong one.
- **Leaves (`*_gotchas.md`, `*_runbooks.md`, `decisions.md`).** The actual knowledge. Consolidate tiny fragmented files. Group by cohesion.

## 3. Propose before writing
Present a plan for approval:
- Exact tree (root, routers, domain indexes, leaves).
- Old-to-new migration map; flag consolidations and deletions.
- Tool-enforced rules you intend to drop.

## 4. Apply and validate
1. Write the hierarchy. Apply `rules.md` to every bullet — including during refactor of existing prose.
2. Repair relative links.
3. Confirm no router (`AGENTS.md`) contains leaf content.
4. Report additions, moves, consolidations, deletions. Do not commit or push.
