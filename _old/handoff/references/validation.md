# Handoff Validation

Run all applicable checks after writing. Never split a handoff to meet a size
target.

## Policy and authority

- [ ] Repository/user policy was read before mutation.
- [ ] Active Beads workspace and issue exist.
- [ ] No unauthorized commit, push, sync, deploy, archive, issue closure,
      deletion, or move occurred.
- [ ] No links to `AGENTS.md`, `AGENT.md`, or `agent_docs/` exist.
- [ ] Durable rules/docs were not copied into checkpoint.

## Integrity

- [ ] Listed issues exist and statuses match `bd show`.
- [ ] Next action matches acceptance and dependency state.
- [ ] Filename uses primary issue and implies no chain or parent.
- [ ] Beads notes contain current state/next action, not handoff path.
- [ ] No handoff `bd remember` entry exists.

## Delta quality

- [ ] Changes contain only current-session deltas.
- [ ] Decisions and failed approaches include reasons.
- [ ] Routine mechanics and completed history are absent.
- [ ] Repetition exists only when needed for resumption.

## Evidence and state

- [ ] Claims were observed this session or marked inherited/unverified.
- [ ] Verification favors changed results and decision-driving evidence.
- [ ] Git HEAD, branch, staged, unstaged, untracked, and deleted state are exact.
- [ ] Incomplete or broken edits are explicit.
- [ ] First next action is executable without guessing.

## Security and readability

- [ ] No secrets, credentials, private hostnames, deployment IDs, or ignored
      configuration content appears.
- [ ] Raw output is filtered to facts needed for resumption.
- [ ] Core checkpoint stands alone without appendix.
- [ ] Temporary/deletion notice exists.

Fix every failure. Expand only for missing facts; shorten duplication and
durable-project restatement.
