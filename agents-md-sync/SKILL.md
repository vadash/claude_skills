---
name: agents-md-sync
description: >-
  Incrementally capture session learnings into AGENTS.md and agent_docs files
  at the end of a session or before a commit. Keeps context sharp and prevents bloat.
---

# AGENTS.md Sync

At session wrap-up or pre-commit, persist stable, reusable learnings discovered during implementation. Keep updates concise and targeted to protect progressive disclosure.

## Timing
- Run after implementation and verification are fully complete.
- Do not run for casual commits or minor edits.
- For full structural overhauls or initial setup, use `agents-md-init`.

## Filtering Learnings
Only document information that provides high future value:

* **PERSIST:**
  - Non-obvious API/library gotchas (e.g. silent fail states, undocumented edge cases).
  - Permanent Architectural Decision Records (ADRs).
  - Essential operational updates or environmental prerequisites.
* **DISCARD:**
  - Rules enforced by tools (linters, formatters, type checkers).
  - Transient progress notes ("Yesterday we fixed bug X").
  - Self-evident facts easily read directly from function signatures or types.

## Placement & Style Rules
- **Keep it Brief:** Add short bullet points—never append paragraphs or walls of text.
- **Topical Placement:**
  - Global project boundary -> Root `AGENTS.md`
  - Subdirectory directive -> Nearest `*/AGENTS.md` router
  - Specific gotcha / decision -> Relevant leaf in `agent_docs/`
- **Edit & Prune:** Merge with existing points, resolve contradictions, and prune outdated guidance. Never just append blindly to the end of a file.
