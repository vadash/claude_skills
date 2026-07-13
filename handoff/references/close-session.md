# Close Session Flow

Use only after the handoff is written and the user asks to close or wrap up.

## Re-check policy and authority

Inspect current Git and Beads state. A handoff or close-session request does not
automatically authorize a commit, push, Beads remote sync, deployment, issue
closure, archival, or deletion.

Close an issue only when acceptance is actually complete. Otherwise leave it
open or in progress with concise current-state notes; never put the handoff path
in those notes.

## Commit only with authority

If commit authority is explicit, review and stage only session-owned files,
follow repository conventions, and report the commit plus remaining dirty
state. Include the tracked handoff only when repository policy or the user wants
it in that commit.

Without authority, do not commit. Report the exact state and proposed next step.

## Keep cleanup manual

Do not move, archive, or delete handoffs during ordinary session closure. The
user may delete the checkpoint after the continuation session no longer needs
it. Because Beads stores no handoff path, that deletion requires no task-memory
cleanup.

## Resume prompt

```text
Read `{handoff_path}`, then run `bd show {primary_issue}` and continue from
“Next Action”. Verify the recorded Git/worktree state before editing and report
any drift. This handoff is temporary and may be deleted after it is no longer
needed.
```

The next session discovers repository policy through its normal startup path.
