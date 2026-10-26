---
name: issue-chain
description: Run a queue of issues through implement-agents one at a time, gating each ticket on a real commit and a clean tree. Args `10` (epic) or `11-20` (range). Optional `freebuff` first word.
disable-model-invocation: true
---

# Issue Chain

You are a queue with a git gate, not an implementer. Every ticket goes to one
`implement-agents` subagent that owns scouting, writing, the wall, review,
commit, and push. You hold the queue, read git between tickets, and keep the line
moving. Nothing else.

Invocation:

- `/issue-chain 10` — epic. Its open sub-issues are the queue, in the epic's order.
- `/issue-chain 11-20` — literal range, inclusive, ascending. No epic needed.
- `/issue-chain 11 13 14` — same thing, explicit.

Optional first word `freebuff` sends each ticket's reviews to the freebuff
Instance. Tickets run strictly one at a time, in queue order, assumed
sequential — no dependency analysis, no reordering, no parallelism.

Why so thin: `implement-agents` already runs typecheck, lint, the full suite, an
end review, and a smoke of the changed surface for the ticket it was given. A
second verify pass here would re-run the same commands on the same tree and prove
nothing the worker's own wall did not. The one thing a worker cannot fake is git
state, so that is the only gate you run.

## Phase 0 — Build the queue

- Range → expand inclusive, ascending. Ask
  `gh issue list --state all --limit 200 --json number,state` once for the repo,
  drop closed numbers (already done), report the skips. `--state all` is not
  optional: the default listing shows open issues only, so a closed ticket would
  vanish and the range would look complete when it is not. A number in the range
  with no issue at all is a typo, not a skip — stop and say which one, because
  silently shrinking the queue is how tickets get forgotten.
- Epic → `gh api repos/<owner>/<repo>/issues/<N>/sub_issues` **plus** a body scan
  for a `Parent` section pointing at `#<N>`; union, drop closed. The API returns
  `[]` for body-linked sub-issues and the scan misses feature-linked ones. Keep
  the returned order — do not sort.
  Nothing found either way → it is a single ticket, not an epic. Run it as a
  one-item queue and say so in the report; asking the user to retype it as
  `51-51` costs a turn and buys nothing.
- Preflight: `git status --porcelain` empty; `git rev-parse HEAD` is the chain
  base and `git rev-parse --abbrev-ref HEAD` the expected branch. Dirty tree →
  report and stop, because a chain cannot attribute failures on top of
  uncommitted work it does not own.
- Todos: one `Implement issue://<N>` per ticket, queue order.

Empty queue → say so and stop. That is a complete run.

## Phase 1 — Dispatch, one at a time

One `task` subagent per ticket, named `Ticket<N>`, whose entire task text is one
line:

```
Read skill://implement-agents; follow it for issue://10.
```

With `freebuff` on the invocation, the line reads
`Read skill://implement-agents; follow it in freebuff mode for issue://10.` A slash line
(`/implement-agents issue://10`) means the same thing, but subagent prompts are
plain text rather than a command line, so the `skill://` form is the one that
reliably resolves.

Nothing else goes in. No acceptance criteria, no repo path, no branch, no
standards paste: the worker fetches the issue and the repo's `AGENTS.md` itself,
so anything you add is dead weight in a prompt nothing downstream can see. Wait
for the result before dispatching the next ticket — tickets build on each other's
commits. Never pass `tools`; it strips the worker's native toolset. Never
dispatch `scout` or `reviewer` — the chain has no review phase of its own.

Freebuff is an Instance one Task owns at a time, so a chain does not retry it per
ticket: the first ticket that reports a fallback to harness reviewers settles the
mode for the rest of the chain, and every later line drops `in freebuff mode`.
Mixing modes across tickets is fine — reviews are per-ticket — but re-probing a
dead Instance on all twenty is just twenty waits.

## Phase 2 — Gate (git only)

The worker's report is a claim. Check the tree, not the prose:

```bash
git log --format='%h %s%n%b' <base>..HEAD   # ≥1 commit, and some commit names #<N>
git merge-base --is-ancestor <base> HEAD   # base still in history
git rev-parse --abbrev-ref HEAD            # the branch you started on
git status --porcelain                     # empty
git status -sb                             # ahead → push; diverged → fail
```

`implement-agents` commits one slice at a time and puts `closes #<N>` only on the
run's last commit, so several commits per ticket is normal — search the whole
range for the reference rather than demanding it on every line.

The ancestry and branch checks exist because a clean `status` and a plausible
`log` still pass when a worker rebased, reset, or switched branches: the range
looks fine, the commits underneath it are gone.

Rewritten history is the one red gate that never goes to Phase 3. There is
nothing for a worker to finish, and a fresh one would amend on top of the already
rewritten base and stack a second rewrite. `--force` is worse — it publishes a
history the earlier tickets' commits are no longer part of. Stop, and hand the
human both commits: the original base (still in `git reflog` / `git log --all`)
and the rewritten tip, so they choose which one is the truth.

`git push` of commits the worker already made is mechanical and allowed — but
only when the branch is simply ahead. A rejected push is never retried with
`--force`; it means the base moved, so treat it like rewritten history and stop.
Committing, amending, resetting, staging, or editing tracked files is not —
never in the orchestrator.

Green → mark the todo done, set `<base>` to `HEAD`, dispatch the next ticket.

Two reds never reach Phase 3. Rewritten history stops the chain (above). A clean
tree with no new commit and a worker report saying the ticket was already
satisfied — a code path that landed with an earlier ticket, or one someone did by
hand — is not a failure either: retrying cannot fix it, so record it as `already
satisfied` with the worker's sentence as evidence, keep `<base>` where it is, and
move on. Judge it by whether the tree got *dirtier*: leftovers or a partial commit
mean the work did start, and that is a real red.

Everything else → Phase 3. No tests, lint, or smoke here.

## Phase 3 — Recover a ticket

`implement-agents` stops on a dirty tree at its own preflight (its run must own
every commit it reports), so a fresh worker inherits the leftovers only if you
say so out loud. That is the one thing worth adding to a recovery line — it is a
fact the worker cannot discover without being told, not a restatement of the
issue.

1. Worker returned, tree dirty or commit missing, no quota failure → nag it once
   through `write agent://Ticket<N>`, one line:
   `Finish issue://<N>. <the git status lines>`
   A completed child often refuses delivery; then it is unavailable — step 2.
2. Quota, crash, unavailable, or a nag that did not clear the gate → dispatch
   `Ticket<N>b`:
   ```
   Read skill://implement-agents; follow it for issue://<N>. That dirty tree is
   yours to adopt: <git status lines>. Do not stop on preflight, and do not leave
   a partial state behind.
   ```
3. Still red → stop the chain, report, leave the rest queued.

Never clean the tree yourself. What a dead worker left behind is either partial
work worth keeping or scaffolding worth seeing, and `git checkout`, `git reset
--hard`, `git clean` destroy the only record of which.

Cap: one nag plus one fresh worker per ticket. A third attempt is the same
failure with more commits stacked on top.

## Phase 4 — Report

| Issue | Commit | Gate | Note |
|---|---|---|---|

Use `already satisfied` in the Gate column for the clean-no-commit case, with the
worker's sentence as the Note. Then: where the chain stopped and why, with the
worker's reason verbatim, and the tickets that never ran. Whole queue gated → say
so and name the base..HEAD range.

## Anti-patterns

- Re-running tests, lint, or smoke "just to be sure" — duplicate work on a tree
  `implement-agents` already walled, and not a gate.
- Appending criteria, repo paths, branch names, or a restatement of the mode to
  the dispatch line — `implement-agents` reads its own invocation.
- Restating the issue body instead of letting the worker fetch it.
- Sorting an epic's sub-issues or inferring dependencies; the order is given.
- Parallel or speculative dispatch of later tickets.
- Trusting the worker's "done" without reading git.
- Fixing worker output yourself, including `git add`/`git commit`/`git reset`.
- Passing a slash-command line into a subagent prompt and hoping it expands.
- Continuing past a red ticket because the rest "look independent".
- Treating a clean tree with no commit as a failure without checking whether the
  worker said the ticket was already satisfied.
- Accepting `git log <base>..HEAD` as proof of history when `<base>` is no longer
  an ancestor — that range prints something even after a rebase.
- Passing `in freebuff mode` to tickets after one already fell back to harness
  reviewers.
