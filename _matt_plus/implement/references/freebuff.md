# Freebuff mode

`freebuff` replaces both reviewer subagents with the freebuff Instance: a different model on its own allowance, holding the same `skill://` skills. Everything else in the run is identical. Used when the invocation or the dispatching skill says `freebuff`; the mode applies to every review in the run.

## Mechanics

- One `freebuff_run` per axis, both submitted in one turn, then one `freebuff_wait` each.
- The target is the session cwd's git root; there is no path argument.
- One Task owns the Instance at a time, and only its owner session is answered — another session gets `not_owner`. Keep the tree untouched while Tasks run: a commit landing mid-review moves the range under the reviewer.
- Prompt: the template in `skill://implement/references/review.md`, verbatim, ending with:

  ```
  Review only: run git, read, report; do not edit files or commit.
  ```

## Fallback

Any failure — no quota, `busy`, `lock_busy`, `not_owner`, a missing tool, a `failed` verdict — reruns the unfinished axes with harness `reviewer` agents (both when neither ran), then switches the rest of the run to harness mode and notes the switch in the report.

A freebuff failure never blocks: the run's reviews still happen, on the harness, and the report says which model produced them.
