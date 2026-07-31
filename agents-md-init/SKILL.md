---
name: agents-md-init
description: >-
  Bootstrap or overhaul repository AGENTS.md and agent_docs hierarchy.
  Use during initial repository setup or after major structural refactors.
  Ensures documentation stays lean, modular, and concise through progressive disclosure.
disable-model-invocation: true
---

# AGENTS.md Init & Refactor

Build or restructure repository agent memory for maximum context efficiency. **Avoid walls of text**—future agent context is precious; keep documentation dense, crisp, and actionable.

## Trigger Conditions
- **Bootstrap Mode:** No root `AGENTS.md` exists; creating from scratch.
- **Refactor Mode:** Major structural overhaul or documentation cleanup requested.
*(For routine, post-implementation maintenance, use `agents-md-sync` instead.)*

## Core Principles
1. **Zero Text Walls:** Documentation must consist of concise, high-signal bullet points. No historical essays, debug narratives, or fluff.
2. **No Tool-Enforceable Rules:** Delete prose covering things linters, Prettier, TypeScript, or CI check automatically.
3. **No Task/State Tracking:** Omit transient tasks, logs, or TODO lists (leave state to task trackers like Beads).
4. **Progressive Disclosure:**
   - **Root `AGENTS.md` (< 40 lines):** Global map only. What/Why, critical boundaries, primary workflow commands, and pointers to domain docs.
   - **Sub-Routers (`*/AGENTS.md`):** Lightweight domain directives that point agents to specific leaf files.
   - **Leaf Files (`agent_docs/*`):** Short, categorized gotchas, ADRs, or specific operational runbooks.

## Execution Workflow

### 1. Audit & Classify
- Read codebase, existing `AGENTS.md`, and `agent_docs/`.
- Identify stable knowledge (gotchas, invariants, ADRs).
- Filter out linter rules, type details, and obsolete narrative prose.

### 2. Propose Plan
Present a brief summary before writing:
- Proposed documentation tree (Root -> Routers -> Leaves).
- List of redundant/obsolete prose being removed or consolidated.

### 3. Write Lean Files
- Write or update files using compact bullet points.
- Use `file:line` pointers instead of pasting code blocks where appropriate.
- Validate all relative links across the directory tree.
