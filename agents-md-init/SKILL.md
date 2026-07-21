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
   - **Stable Knowledge (Gotchas, Runbooks, ADRs):** Persist in leaves.
   - **Tool-Enforceable Rules (Linters, Formatting, Types):** DELETE. Do not write prose for things tools catch.
   - **Mutable State (Tasks, Logs, Chronology):** DELETE. Leave this to task trackers (e.g., Beads).
   - **Redundant Lore/Bloat:** CONDENSE or DELETE. 

## 2. Design the Hierarchy (Strict Rules)
Use the smallest possible hierarchy to reliably route future agents:

* **Root `AGENTS.md` (The Map):** 
  - Must be **< 60 lines**. 
  - Contains only: WHAT, WHY, critical global boundaries, universal commands (e.g., test/build), and a strict Documentation Map. 
  - Never include deep architectural details here.
* **Nested `AGENTS.md` (The Routers):** 
  - Sit in major subdirectories (e.g., `frontend/AGENTS.md`).
  - Act as conditional routers: *"If modifying X, read `agent_docs/frontend/x_gotchas.md`"*.
  - May contain a few bullet points of strict domain rules, but NO heavy prose.
* **`agent_docs/<domain>/README.md` (Domain Indexes):**
  - Routers for specific documentation domains (e.g., `/architecture`, `/operations`, `/decisions`).
* **Leaves (`*_gotchas.md`, `*_runbooks.md`, `decisions.md`):**
  - The actual knowledge. Consolidate tiny fragmented files. Group by cohesion.

## 3. Propose Before Writing
Present a plan for approval:
- Exact tree structure (Root, Nested Routers, Domain Indexes, Leaves).
- Old-to-new migration map (especially what is being consolidated/deleted).
- List of tool-enforced rules you intend to drop.

## 4. Apply and Validate
1. Write the hierarchy. Replace inline code snippets with `file:line` pointers where possible.
2. Repair all relative links.
3. Validate that NO router (`AGENTS.md`) contains bloated leaf content.
4. Report additions, moves, consolidations, and deletions. Do not commit or push.
