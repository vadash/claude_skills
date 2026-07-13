# Handoff Output Template

Use this compact structure. Capture deltas and resumption facts, not a second
copy of durable documentation.

```markdown
# {One-line session outcome and immediate continuation}

**Date:** {YYYY-MM-DD}
**Session outcome:** {completed | paused | blocked}
**Bead(s):** {active Beads issue IDs}
**Epic:** {epic ID, or none}
**Temporary:** Delete after the continuation session no longer needs this checkpoint.

---

## Resume at a Glance

{A short paragraph or 3-6 bullets covering the goal, current state, what is
complete versus incomplete, and the first action for the next session.}

## Changes This Session

{Only current-session deltas. Group behavior/implementation and task-state
changes when useful. Do not restate stable architecture or historical scope.}

## Decisions and Failed Approaches

{Include only non-obvious decisions, rejected alternatives, and expensive
failures with reasons. Write `None` when there were none.}

## Verification

{Include failures or regressions and their final state, changed acceptance
results, decision-driving measurements, and at most one summary of an otherwise
unchanged passing suite. Mark inherited or unverified claims.}

## Worktree State

{Record staged, unstaged, untracked, and deleted files; incomplete edits; and
whether the handoff itself is committed. Write `Clean` when appropriate.}

## User Direction Delta

{Only directions introduced, changed, or revoked this session. Write `None`
when unchanged.}

## Risks and Open Questions

{Only active blockers, material risks, and unanswered questions. Write `None`
when there are none.}

## Next Action

**First action:** {one concrete action tied to a Beads issue}

{Optionally list 1-4 ordered follow-ons. Include only task-specific commands and
files required to resume.}

## Appendix: Detailed Evidence or Chronology

{OPTIONAL. Include only necessary raw measurements or a complex failure timeline.
Omit the section otherwise.}
```

Do not link `AGENTS.md`, `AGENT.md`, or anything under `agent_docs/`.
