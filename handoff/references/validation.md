# Handoff Information-Quality Validation

Run every applicable check after writing. There is no line target and handoffs
must never be split by size.

## 1. Policy and Authorization

- [ ] Applicable repository and user policy was read before any mutation.
- [ ] The repository has an active Beads workspace.
- [ ] The handoff performs no unauthorized commit, push, sync, deployment,
      archival, issue closure, or file move.
- [ ] The output contains no links to `AGENTS.md`, `AGENT.md`, or `agent_docs/`.
- [ ] Durable repository rules and documentation were not copied into the
      handoff unless a policy change directly affects resumption.

## 2. Beads and Chain Integrity

- [ ] Every listed Beads issue exists and its status matches `bd show`.
- [ ] The primary issue, epic, chain tag, and sequence agree.
- [ ] The parent is a direct continuation, not merely a shared bead or epic.
- [ ] The exact parent path exists when a parent is listed.
- [ ] New workstreams use an epic or Beads issue ID, never a standalone tag.
- [ ] The next action is consistent with the issue's current acceptance and
      dependency state.

## 3. Delta Quality

- [ ] “Changes This Session” contains only current-session deltas.
- [ ] Stable architecture, product scope, old preferences, and completed
      history are not repeated.
- [ ] Decisions include their reasons; failed approaches include observed
      failure causes.
- [ ] Routine mechanics are omitted unless they expose a reusable gotcha.
- [ ] No fact is repeated across multiple sections without a resumption reason.

## 4. Evidence and Current State

- [ ] Test and measurement claims were observed this session or clearly marked
      inherited/unverified.
- [ ] Verification emphasizes failures, changed results, acceptance evidence,
      and decision-driving measurements rather than every passing gate.
- [ ] An unchanged passing gate suite is summarized once; exact detail is kept
      only where it affects confidence or the next action.
- [ ] Changed paths and identifiers exist, or deletions/renames are explicit.
- [ ] Git HEAD, branch, staged, unstaged, and untracked state are accurate.
- [ ] Incomplete or broken edits are called out explicitly.
- [ ] The first next action is concrete enough to execute without guessing.

## 5. Security and Readability

- [ ] No secrets, tokens, credentials, private hostnames, deployment IDs, or
      ignored configuration contents are exposed.
- [ ] Raw command output is filtered to the facts required for resumption.
- [ ] The core handoff can be understood without reading an optional appendix.
- [ ] Any appendix contains necessary raw evidence, not overflow created by an
      arbitrary size rule.

If a check fails, fix the handoff and validate again. Expand only to add a
missing fact; shorten whenever duplication or durable-project restatement is
found.
