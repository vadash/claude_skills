---
name: issue-chain
description: Run a queue of issues through implement one at a time, gating each ticket on git state.
disable-model-invocation: true
---

# Issue Chain

You are the chain: a queue with a git gate. `[YOU]` is this thread, the orchestrator. `[AGENTS]` is a subagent dispatch, never inline work.

Invocation: `/skill:issue-chain [freebuff] <epic#> | <a-b> | <a c d>`. Invoking authorizes one `implement` worker per ticket, plus pushing the commits those workers make. Nothing else — the chain implements nothing.

Tickets run strictly one at a time, in queue order: no dependency analysis, no reordering, no parallelism.

Phases 1 to 3 run once per ticket: dispatch one, gate it, recover it when red, move the base, take the next.

Why this thin: `implement` already ran typecheck, lint, the full suite, an end review, and a smoke of the changed surface for its ticket. A second pass here would re-run the same commands on the same tree and prove nothing its Wall did not. Git state is the one thing a worker cannot fake, so git is the only gate.

## [YOU] Phase 0: Build the queue

- **Range** `<a-b>` / `<a c d>` → expand inclusive, ascending. Ask `gh issue list --state all --limit 200 --json number,state` once for the repo. `--state all` is load-bearing: the default listing hides closed tickets, so a closed number would vanish and the range would look complete when it is not. A closed number is a reported skip.
- A number with no issue at all is a typo, not a skip. Stop and name it; a silently shrunken queue is how tickets get forgotten.
- **Epic** `<N>` → union `gh api repos/<owner>/<repo>/issues/<N>/sub_issues` with a body scan for a `Parent` section pointing at `#<N>`, then drop closed. Both sources earn their place: the API returns `[]` for body-linked sub-issues and the scan misses feature-linked ones. Keep the returned order — never sort.
- Nothing found either way → it is one ticket, not an epic. Run it as a one-item queue and say so; making the human retype `51-51` costs a turn and buys nothing.
- **Preflight**: `git status --porcelain` empty; record `git rev-parse HEAD` as the chain **base** and `git rev-parse --abbrev-ref HEAD` as the expected branch. Dirty tree → report and stop, because the chain cannot attribute failures on top of uncommitted work it does not own.
- **Todos**: one per ticket, in queue order.

Empty queue → say so and stop. That is a complete run.

**Done**: every queued ticket exists as a todo with a number, a resolved state, and its skip or typo noted — or the chain stopped before Phase 1 naming the reason.

## [YOU] Phase 1: Dispatch

One `[AGENTS]` dispatch per ticket: a `task` subagent named `Ticket<N>` whose entire task text is one line:

```
Read skill://implement; follow it for issue://<N>. Do not do the work in this thread.
```

With freebuff on the invocation:

```
Read skill://implement; follow it in freebuff mode for issue://<N>. Do not do the work in this thread.
```

The `skill://` form is what resolves: a subagent prompt is plain text, not a command line, so a slash line there never expands.

Nothing else goes in: no acceptance criteria, no repo path, no branch, no standards paste. The worker fetches the issue and the repo's `AGENTS.md` itself, so anything you add is dead weight nothing downstream can see. Wait for the result before the next ticket — tickets build on each other's commits. Never pass `tools`; it strips the worker's native toolset. Never dispatch `scout` or `reviewer`: the chain has no review phase of its own.

Freebuff is an Instance one Task owns at a time; mechanics live in `skill://implement/references/freebuff.md`. The chain rule: the first ticket that reports a fallback to harness reviewers settles the mode for the rest of the queue, and every later dispatch drops `in freebuff mode`. Re-probing a dead Instance per ticket is twenty waits for the same answer.

**Done**: one ticket dispatched, its report read, and no second ticket in flight.

## [YOU] Phase 2: Gate (git only)

The worker's report is a claim. Read the tree:

```bash
git log --format='%h %s%n%b' <base>..HEAD   # ≥1 commit, and some commit names #<N>
git merge-base --is-ancestor <base> HEAD   # base still in history
git rev-parse --abbrev-ref HEAD            # the branch you started on
git status --porcelain                     # empty
git status -sb                             # ahead → push; diverged → fail
```

`implement` commits one slice at a time and puts `closes #<N>` only on the run's last commit, so several commits per ticket is normal. Search the whole range for the reference rather than demanding it on every line.

The ancestry and branch checks exist because a clean `status` and a plausible `log` still print after a rebase, reset, or branch switch: the range looks fine and the commits underneath it are gone.

Three outcomes:

- **Green** — clean tree, one commit naming `#<N>`, base an ancestor of `HEAD`, branch unchanged. Push if the branch is simply ahead. Mark the todo done, base := `HEAD`, dispatch the next ticket.
- **Already satisfied** — clean tree, no new commit, and the worker says the work was already there (landed with an earlier ticket, or by hand). Not a failure: retrying cannot fix it. Record `already satisfied` with the worker's sentence as evidence, keep base, move on. Judge it by whether the tree got dirtier — leftovers or a partial commit mean the work started, and that is a real red.
- **Red** — everything else, into Phase 3.

**Rewritten history stops the chain** and never reaches Phase 3: base is no longer an ancestor, or a push was rejected. There is nothing for a worker to finish, and a fresh one would amend on top of the rewritten base and stack a second rewrite. Hand the human both commits — the original base (still in `git reflog`) and the rewritten tip — so they pick which is the truth.

No tests, lint, or smoke here.

**Done**: the current ticket has a verdict from the five commands, and the base moved or the chain stopped.

## [YOU] Phase 3: Recover

`implement` stops at its own preflight on a dirty tree, because its run must own every commit it reports. A fresh worker inherits the leftovers only when told, so that sentence is the one fact worth adding — it is not restating the issue.

1. Nag once via `write agent://Ticket<N>`, one line: `Finish issue://<N>. <git status lines>`. A completed child often refuses delivery; then it is unavailable — go to 2.
2. Dispatch `Ticket<N>b` with the same contract line plus: `That dirty tree is yours to adopt: <git status lines>. Do not stop on preflight, and do not leave a partial state behind.`
3. Still red → stop the chain, report, leave the rest queued.

Cap: one nag plus one fresh worker per ticket. A third attempt is the same failure with more commits stacked on top.

**Done**: the ticket cleared the gate, or the chain stopped with the worker's reason verbatim and the remainder queued.

## [YOU] Phase 4: Report

| Issue | Commit | Gate | Note |
|---|---|---|---|

Use `already satisfied` in the Gate column for the clean-no-commit case, with the worker's sentence as the Note. Then state where the chain stopped and why with the worker's reason verbatim, and name the tickets that never ran. Whole queue gated → say so and give the `base..HEAD` range.

**Done**: every queued ticket appears exactly once in the table with its commit, verdict, and note, and the stop point or the completed range is named.

## Hard stops

- Push only when the branch is simply ahead. A rejected push means the base moved: treat it like rewritten history and stop. `--force` publishes a history the earlier tickets' commits are no longer part of.
- The chain commits, amends, resets, stages, and edits tracked files nowhere — a worker owns every commit.
- The chain never cleans a dirty tree. Leftovers are either partial work worth keeping or scaffolding worth seeing; `checkout`, `reset --hard`, and `clean` destroy the only record of which.
- A red ticket stops the line even when the rest look independent.
