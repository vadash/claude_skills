# Deep and Chunked Delta Mining

Use this procedure when a session is long, multi-topic, or tool-heavy. Its
purpose is to prevent lost decisions and failures, not to make the checkpoint
longer.

## Deep pass

1. Extract current changes, decisions, failed approaches, verification,
   worktree state, user-direction changes, and unresolved questions.
2. Re-scan the middle of the conversation for details missed by recency bias.
3. Compare candidates with the active Beads issue, Git, code, and durable docs.
4. Remove anything already authoritative elsewhere unless its current delta is
   necessary to resume.

## Chunked pass

1. Divide the conversation into natural chronological topic segments.
2. Apply the same delta checklist to each segment.
3. Merge chronologically; later decisions override earlier ones.
4. Preserve an earlier approach only when its failure explains current state.
5. Deduplicate between output sections and verify claims against current facts.

## Evidence selection

Keep only evidence that changes what the next session should believe or do:

- exact failing and passing results;
- measurements that drove a decision;
- error text needed to recognize a recurring failure;
- task-specific raw evidence needed for continuation;
- unresolved state that cannot be reconstructed cheaply.

Prefer failure-to-fix transitions over full command transcripts. Summarize an
unchanged gate suite once. Use one optional appendix only when raw evidence is
necessary.
