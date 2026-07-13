# Handoff Information-Quality Validation

Run every applicable check after writing. There is no line target and a handoff
must never be split by size.

## Policy and authorization

- [ ] Applicable repository and user policy was read before mutation.
- [ ] The repository has an active Beads workspace and issue.
- [ ] No unauthorized commit, push, sync, deployment, archival, issue closure,
      file deletion, or move occurred.
- [ ] The output contains no links to `AGENTS.md`, `AGENT.md`, or `agent_docs/`.
- [ ] Durable rules and documentation were not copied into the checkpoint.

## Issue and checkpoint integrity

- [ ] Every listed issue exists and its status matches `bd show`.
- [ ] The next action agrees with current acceptance and dependency state.
- [ ] The filename uses the primary issue and does not imply a chain or parent.
- [ ] Beads notes contain current state and next action, not the handoff path.
- [ ] No `bd remember` entry was created for the handoff.

## Delta quality

- [ ] Changes contain only current-session deltas.
- [ ] Decisions and failed approaches include reasons.
- [ ] Routine mechanics and completed history are omitted.
- [ ] No fact is repeated without a concrete resumption reason.

## Evidence and state

- [ ] Claims were observed this session or marked inherited/unverified.
- [ ] Verification emphasizes changed results and decision-driving evidence.
- [ ] Git HEAD, branch, staged, unstaged, and untracked state are accurate.
- [ ] Incomplete or broken edits are explicit.
- [ ] The first next action can be executed without guessing.

## Security and readability

- [ ] No secrets, credentials, private hostnames, deployment IDs, or ignored
      configuration contents are exposed.
- [ ] Raw output is filtered to required resumption facts.
- [ ] The core checkpoint stands alone without an optional appendix.
- [ ] The temporary/deletion notice is present.

Fix every failed check. Expand only for a missing fact; shorten whenever
duplication or durable-project restatement is found.
