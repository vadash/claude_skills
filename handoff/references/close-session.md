# Close Session Flow

Use only after the handoff has been written and the user asks to close or wrap
up the session.

## 1. Re-check Policy and Authority

Read current repository and user instructions again. A handoff request or a
request to close the session does not automatically authorize a commit, push,
Beads remote sync, archive, issue closure, or deployment.

Inspect current Git and Beads state with the available shell and tools. Do not
assume a particular operating system or shell.

## 2. Close Beads Work Only When Complete

Close an issue only when its acceptance criteria are actually satisfied and
current policy permits closure. Otherwise leave it open or in progress and
ensure its notes point to the handoff.

## 3. Commit Only With Authority

If commit authority is explicit:

1. Review staged, unstaged, untracked, and deleted files.
2. Stage only files belonging to this session.
3. Include the handoff in the same commit when policy expects it to be tracked.
4. Use the repository's commit-message conventions.
5. Report the resulting commit hash and any remaining dirty files.

Do not append a commit hash to the handoff after committing unless the user also
authorizes a follow-up commit or amend. Record the hash in Beads notes when a
durable pointer is needed.

If commit authority is absent, do not commit. Report the exact dirty state and
the proposed next command or ask for authorization when the user wants a commit.

Never add product-specific AI attribution or co-author trailers unless current
repository policy explicitly requires them.

## 4. Do Not Archive Automatically

Do not move, rename, delete, or archive handoffs during ordinary session
closure. Archival is separate repository maintenance and requires explicit
authority plus reference validation.

## 5. Produce the Resume Prompt

Provide a concise prompt using the active Beads issue and handoff path:

```text
Read `{handoff_path}` (chain `{chain_tag}` seq `{N}`), then run
`bd show {primary_issue}` and continue from “Next Action”. Verify the recorded
Git/worktree state before editing and report any drift.
```

Do not include links to general repository instruction files or durable project
documentation. The next session must discover and obey repository policy through
its normal startup process.
