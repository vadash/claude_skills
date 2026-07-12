# Deep and Chunked Delta Mining

Use this procedure when a session is long, multi-topic, or contains many tool
calls. Its purpose is to prevent lost decisions and failures, not to make the
handoff longer.

## Deep Pass

1. Extract current-session changes, decisions, failed approaches, verification,
   worktree state, user-direction changes, and unresolved questions.
2. Re-scan the middle of the conversation for details missed by recency bias.
3. Compare every candidate fact with the parent handoff, current Beads state,
   Git, and durable project documentation.
4. Remove anything already authoritative elsewhere unless its change is needed
   to resume this session.

## Chunked Pass

1. Divide the conversation into natural chronological segments based on topic
   or implementation phase.
2. Apply the same delta checklist independently to each segment.
3. Merge chronologically. Later decisions override earlier ones; preserve an
   earlier approach only when its failure explains the current design.
4. Deduplicate against the parent handoff and between output sections.
5. Verify final claims against current files, Git, tests, and Beads.

## Evidence Selection

Keep evidence that changes what the next session should believe or do:

- exact failing and passing test results;
- measurements that drove a decision;
- error messages needed to recognize a recurring failure;
- paths to task-specific raw evidence;
- unresolved state that cannot be reconstructed cheaply.

Prefer the failure-to-fix transition over a complete passing-test inventory.
Summarize an unchanged quality-gate suite once. Omit routine command transcripts,
repeated full quality-gate tables, file-read chronology, and evidence already
recorded in durable project documentation.
Use an optional appendix in the same handoff only when raw evidence is necessary.
