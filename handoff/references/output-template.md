# Handoff Output Template

Use this compact structure. Capture deltas and resumption facts, not a second
copy of the project's durable documentation.

```markdown
# {One-line session outcome and immediate continuation}

**Date:** {YYYY-MM-DD}
**Session outcome:** {completed | paused | blocked}
**Bead(s):** {active Beads issue IDs}
**Epic:** {epic ID, or none}
**Chain:** `{chain_tag}` seq `{N}`
**Parent:** `{exact relative path}` or `none — new Beads workstream`
**Git:** `{branch}` at `{short HEAD}`; {clean or concise dirty-state summary}

---

## Resume at a Glance

{A short paragraph or 3-6 bullets covering:
- the user-visible goal of this workstream;
- the current working state;
- what is complete versus incomplete;
- the single action the next session should perform first.}

## Changes This Session

{Only deltas introduced during this session. Group when useful:

### Behavior and implementation
- `path` / `identifier` — what changed and why.

### Task state
- Bead status, dependency, blocker, or acceptance change.

Do not restate stable architecture, repository rules, or historical scope.}

## Decisions and Failed Approaches

{Include only non-obvious decisions, rejected alternatives, and failures that
would otherwise be expensive to rediscover. For each, state the reason or
observed failure. Omit routine file reading, formatting, import fixes, and
ordinary edit/test cycles. Write `None` when there were no material decisions
or failed approaches.}

## Verification

{Keep this short. Include only:
- failures or regressions and their final state;
- new or changed test results relevant to acceptance;
- measurements that affected a decision;
- one concise summary line for an otherwise unchanged passing gate suite.

Do not enumerate every crate, test count, formatting check, or unchanged gate.
Use at most one small table when comparison is materially clearer than prose.
Clearly mark inherited or unverified claims. Link only task-specific raw
evidence needed for continuation. Do not link `AGENTS.md`, `AGENT.md`, or
anything under `agent_docs/`.}

## Worktree State

{Record:
- staged changes;
- unstaged changes;
- untracked or deleted files;
- known incomplete/broken edits;
- whether the handoff itself is committed.

For each relevant changed path, give one concise delta. Write `Clean` when the
worktree is clean.}

## User Direction Delta

{Only directions introduced, changed, or revoked this session. Do not repeat
longstanding preferences or repository policy. Write `None` when unchanged.}

## Risks and Open Questions

{Combine active blockers, material risks, and unanswered questions. Omit
resolved or generic risks. Write `None` when there are none.}

## Next Action

**First action:** {one concrete action tied to a Beads issue}

{Optionally list 1-4 ordered follow-ons. Include only the minimum commands and
task-specific files required to resume. Start with `bd show {id}` and claim the
issue when appropriate. Do not list general repository instruction files or
durable project documentation.}

## Appendix: Detailed Evidence or Chronology

{OPTIONAL. Include only when raw measurements, a complex failure timeline, or
other detailed evidence is necessary to resume. Keep it in this same file.
Omit the entire section otherwise.}
```
