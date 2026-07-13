---
name: handoff
description: Create one compact temporary session checkpoint for an active Beads-tracked workstream when context is running low or work is pausing. Capture current deltas, verified state, and the next action for the immediately following session without creating handoff chains, archives, durable memories, or duplicated project documentation.
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

Create one compact, evidence-backed checkpoint for the immediately following
session. The Beads issue is the durable workstream identity; the handoff file is
temporary and may be deleted after the continuation session no longer needs it.

**Arguments:** $ARGUMENTS

## Guards

- Run only when the user explicitly asks for a handoff now.
- Require an active Beads workspace and an issue representing the work. Create
  and claim one only when no suitable issue exists.
- Treat the request as authority to write one handoff and update current issue
  notes. Do not infer authority to commit, push, sync, deploy, archive, close
  issues, delete older handoffs, or move files.
- Never create a chain, parent link, sequence, archive, or Beads memory.

## Gather current state

Read applicable repository policy, the active issue, Git state, changed files,
tests and measurements actually observed, unresolved failures, and user
direction introduced or changed this session.

Repository instructions and durable project documentation are inputs, not
handoff content. Do not link or copy `AGENTS.md` or `agent_docs/`. Never expose
secrets, ignored configuration, real deployment identifiers, or unfiltered logs.

For long or tool-heavy sessions, read `references/mining-deep-chunked.md` and use
its multi-pass procedure.

## Write one temporary file

Use the first existing directory, creating `plans/handoffs/` only when neither
exists:

1. `plans/handoffs/`
2. `.claude/handoffs/`

Name the file:

`HANDOFF_{primary_issue}_{2-4-word-slug}_{YYYY-MM-DD}.md`

Append `_2`, `_3`, and so on only on collision. Existing handoffs are not
parents and do not define a chain.

Read `references/output-template.md`, write the complete checkpoint, then read
it back and remove duplication. Add an appendix only when raw evidence is
genuinely necessary to resume.

## Update Beads without linking the file

Update the active issue notes with a concise current outcome and next action.
Preserve still-relevant issue context, but replace stale progress rather than
appending a diary.

Do not store the handoff path, filename, resume prompt, or a copy of its body in
issue notes. Never call `bd remember` for handoff discovery.

## Validate and report

Read `references/validation.md` and fix every failed check. Report:

- handoff path;
- active Beads issue;
- validation result;
- exact next action;
- uncommitted state or separately authorized actions.

If the user asks to close the session, read `references/close-session.md`.
Return its resume prompt. The user may delete the handoff after the continuation
session has safely incorporated it.
