# Handoff Output Template

Capture deltas and resumption facts, not durable documentation.

```markdown
# {Session outcome and immediate continuation}

**Date:** {YYYY-MM-DD}
**Session outcome:** {completed | paused | blocked}
**Bead(s):** {active issue IDs}
**Epic:** {epic ID, or none}
**Temporary:** Delete after continuation no longer needs this checkpoint.

---

## Resume at a Glance

{Short paragraph or 3-6 bullets: goal, current state, complete/incomplete work,
and first next-session action.}

## Changes This Session

{Current-session deltas only. Group implementation and task-state changes when
useful. Omit stable architecture and historical scope.}

## Decisions and Failed Approaches

{Only non-obvious decisions, rejected alternatives, and expensive failures,
with reasons. Otherwise `None`.}

## Verification

{Failures/regressions and final state; changed acceptance results;
decision-driving measurements; at most one summary of unchanged passing suite.
Mark inherited/unverified claims.}

## Worktree State

{Staged, unstaged, untracked, and deleted files; incomplete edits; whether this
handoff is committed. Use `Clean` when applicable.}

## User Direction Delta

{Directions introduced, changed, or revoked this session. Otherwise `None`.}

## Risks and Open Questions

{Active blockers, material risks, unanswered questions. Otherwise `None`.}

## Next Action

**First action:** {one concrete action tied to a Beads issue}

{Optional 1-4 ordered follow-ons. Include only task-specific commands/files.}

## Appendix: Detailed Evidence or Chronology

{Optional; only necessary raw measurements or complex failure timeline. Omit
section otherwise.}
```

Do not link `AGENTS.md`, `AGENT.md`, or `agent_docs/`.
