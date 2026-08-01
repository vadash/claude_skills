---
name: agents-md-init
description: Manually bootstrap a repository AGENTS.md and agent_docs hierarchy, or explicitly audit and refactor an existing hierarchy for progressive disclosure. Use only when the user directly requests initialization, a full memory/documentation rewrite, or structural AGENTS.md optimization; use agents-md-sync for routine end-of-session maintenance.
disable-model-invocation: true
---

# AGENTS.md Init and Refactor

Build or deliberately restructure repository agent memory. Your goal is to maximize context efficiency through **Progressive Disclosure**. The LLM context window is a precious resource; never bloat it with redundant prose.

## Choose Mode
- **Bootstrap:** No root `AGENTS.md` exists; create the hierarchy from scratch.
- **Refactor:** Root exists and user explicitly requested an audit, rewrite, reorganization, or bloat-reduction.
*(If root exists without an explicit refactor request, stop and direct user to `agents-md-sync`.)*

## 1. Establish Truth & Classify
1. Read supplied narrative docs, existing `AGENTS.md`, and `agent_docs/` leaves.
2. Verify claims against code, tests, and configuration. Trust code for mechanics.
3. Classify content:
   - **Stable Knowledge (Gotchas, Runbooks, ADRs):** Persist in leaves — written as durable contracts (see *Abstract Over Code* below).
   - **Tool-Enforceable Rules (Linters, Formatting, Types):** DELETE. Do not write prose for things tools catch.
   - **Mutable State (Tasks, Logs, Chronology):** DELETE. Leave this to task trackers (e.g., Beads).
   - **Redundant Lore/Bloat:** CONDENSE or DELETE.
   - **Code References (function names, file paths, line numbers, implementation expressions):** STRIP during refactor. These rot on every refactor; the agent reading the doc has `grep`. Keep only one high-level module pointer per entry when *location itself is the knowledge*.

## 2. Design the Hierarchy (Strict Rules)
### Abstract Over Code
When refactoring existing prose, the most common bloat source is implementation detail: function names (`runElasticAutoCycle`), file paths (`src/core/summarizer-engine.js`), line numbers (`:142`), code expressions (`Date.UTC(year, month-1, day).getUTCDay()`), and call-site chains. Each one rots the moment the codebase changes. Rewrite these as the durable contract — the *what* and *why* — and let the agent rediscover the *where* with `grep`. Reserve a single module-level pointer for entries whose entire point is routing an agent to a location.
Use the smallest possible hierarchy to reliably route future agents:

* **Root `AGENTS.md` (The Map):** 
  - Must be **< 60 lines**. 
  - Contains only: WHAT, WHY, critical global boundaries, universal commands (e.g., test/build), and a strict Documentation Map. 
  - Never include deep architectural details here.
* **Nested `AGENTS.md` (The Routers):** 
  - Sit in major subdirectories (e.g., `frontend/AGENTS.md`).
  - Act as conditional routers: *"If modifying X, read `agent_docs/frontend/x_gotchas.md`"*.
  - May contain a few bullet points of strict domain rules, but NO heavy prose.
* **`agent_docs/<domain>/<domain>.md` (Domain Indexes):**
  - Named after the domain — e.g., `agent_docs/architecture/architecture.md`, `agent_docs/operations/operations.md`, `agent_docs/decisions/decisions.md`. Each index is uniquely identifiable, so a harness edit never lands on the wrong file. Never use `README.md` for these: multiple `README.md` files across folders collide, and agents will silently edit whichever one glob returned first.
  - Routers for specific documentation domains.
* **Leaves (`*_gotchas.md`, `*_runbooks.md`, `decisions.md`):**
  - The actual knowledge. Consolidate tiny fragmented files. Group by cohesion.

## 3. Propose Before Writing
Present a plan for approval:
- Exact tree structure (Root, Nested Routers, Domain Indexes, Leaves).
- Old-to-new migration map (especially what is being consolidated/deleted).
- List of tool-enforced rules you intend to drop.

## 4. Apply and Validate
1. Write the hierarchy. Strip code references from prose (function names, paths, line numbers, expressions); keep at most one module-level pointer per entry when location is the knowledge.
2. Repair all relative links.
3. Validate that NO router (`AGENTS.md`) contains bloated leaf content.
4. Report additions, moves, consolidations, and deletions. Do not commit or push.
