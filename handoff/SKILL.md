---
name: handoff
description: Create one compact temporary session checkpoint for an active Beads-tracked workstream when context is low or work pauses. Capture current deltas, verified state, and the immediate next action without chains, archives, durable memories, or duplicated project documentation.
user_invocable: true
triggers:
  - do a handoff
  - create a handoff
  - run handoff
  - save session context
  - session handoff
  - save session progress
  - running out of context
argument-hint: [optional reason, e.g. "context low", "end of day"]
---

# Session Handoff

Create one evidence-backed checkpoint for the next session. Beads owns durable
workstream identity; handoff is temporary and deletable after continuation.

**Arguments:** $ARGUMENTS

## Guards

- Run only on an explicit handoff request.
- Require a Beads workspace and issue for this work; create and claim one only
  if none is suitable.
- Authority covers one handoff and current issue notes, not commit, push, sync,
  deploy, archive, closure, deletion, or moving files.
- Never create handoff chains, parent links, sequences, archives, or Beads
  memories.

## Gather

Read repository policy, active issue, Git state, changed files, observed tests
and measurements, unresolved failures, and user-direction changes from this
session.

Repository instructions and durable docs are inputs, never handoff content. Do
not link or copy `AGENTS.md` or `agent_docs/`. Exclude secrets, ignored config,
real deployment identifiers, and unfiltered logs.

For long, multi-topic, or tool-heavy sessions, follow
`references/mining-deep-chunked.md`.

## Write checkpoint

Use first existing directory; create `plans/handoffs/` only if neither exists:

1. `plans/handoffs/`
2. `.claude/handoffs/`

Filename: `HANDOFF_{primary_issue}_{2-4-word-slug}_{YYYY-MM-DD}.md`. Add `_2`,
`_3`, etc. only on collision; existing files are not parents.

Follow `references/output-template.md`, reread output, and remove duplication.
Add an appendix only when raw evidence is required to resume.

## Update Beads

Replace stale issue progress with concise current outcome and next action while
preserving relevant context. Do not store handoff path/name, resume prompt, or
body in notes. Never use `bd remember` for handoff discovery.

## Validate and report

Follow `references/validation.md`; fix every failed check. Report handoff path,
active issue, validation result, exact next action, and uncommitted or separately
authorized state.

If user asks to close the session, follow `references/close-session.md` and
return its resume prompt. User may delete checkpoint once safely incorporated.
