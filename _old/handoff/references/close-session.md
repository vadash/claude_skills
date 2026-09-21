# Close Session Flow

Use only after writing handoff and user asks to close or wrap up.

## Recheck authority

Inspect Git and Beads state. Handoff/closure does not authorize commit, push,
Beads remote sync, deploy, issue closure, archive, or deletion.

Close issue only when acceptance is complete. Otherwise leave it open/in
progress with current notes; never store handoff path there.

## Commit

With explicit authority, review and stage only session-owned files, follow
repository convention, then report commit and remaining dirty state. Include a
tracked handoff only when policy or user requests it.

Without authority, do not commit; report exact state and proposed next step.

## Cleanup

Do not move, archive, or delete handoffs during normal closure. User may delete
checkpoint after continuation no longer needs it; Beads needs no cleanup because
it stores no handoff path.

## Resume prompt

```text
Read `{handoff_path}`, then run `bd show {primary_issue}` and continue from
“Next Action”. Verify the recorded Git/worktree state before editing and report
any drift. This handoff is temporary and may be deleted after it is no longer
needed.
```

Next session discovers repository policy through normal startup.
