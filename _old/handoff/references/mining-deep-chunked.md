# Deep and Chunked Delta Mining

Use for long, multi-topic, or tool-heavy sessions to recover important deltas,
not lengthen checkpoint.

## Deep pass

1. Extract current changes, decisions, failures, verification, worktree state,
   user-direction changes, and open questions.
2. Re-scan conversation middle for recency-missed details.
3. Check candidates against active issue, Git, code, and durable docs.
4. Remove authoritative content unless its current delta is needed to resume.

## Chunked pass

1. Split conversation into chronological topic segments.
2. Apply same delta checklist to each.
3. Merge chronologically; later decisions supersede earlier ones.
4. Keep an earlier approach only when its failure explains current state.
5. Deduplicate sections and verify claims against current facts.

## Evidence

Keep only evidence that changes next-session belief or action:

- exact failing/passing results;
- decision-driving measurements;
- error text needed to recognize recurrence;
- task-specific raw evidence needed for continuation;
- unresolved state expensive to reconstruct.

Prefer failure-to-fix transitions over transcripts. Summarize unchanged gates
once. Use one appendix only when raw evidence is necessary.
