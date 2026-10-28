---
name: code-review
description: Two-axis review of a branch, PR, or WIP diff. Fire it whenever the user asks to review their changes since some point, asks for a review before shipping or merging, points at a branch or pull request they want checked, or hands over a diff they just wrote and wants it looked at. It splits the review into a Standards axis and a Spec axis, runs both as parallel reviewers so neither pollutes the other, then reports them side by side.
---

Reviews the changes between `HEAD` and a **base** the user supplies, along two axes: **Standards** (does the code follow this repo's documented way of writing code?) and **Spec** (does it implement the originating issue or spec?). Both axes run as separate reviewers so their contexts stay apart; this thread aggregates.

[YOU] is this thread, the orchestrator: pins the base, finds the spec and the standards, dispatches, aggregates. [AGENTS] are subagents: every axis is a dispatch, and folding an axis into this thread defeats the separation the review exists for.

**Invocation**: `/skill:code-review [<base>] [<spec-path>]`. Base is any ref git resolves — SHA, branch, tag, `main`, `HEAD~5`; the optional path names the spec. Invoking it authorises read-only git and the subagent dispatch. The diff belongs to the user: review it, leave the tree untouched.

## [YOU] Phase 1: Pin the base

Whatever the user named is the base. No base named: ask rather than assuming `main` — a guessed base reviews someone else's commits as if they were the change.

Capture both lookups once, verbatim, so both reviewers read the same input:

- `git diff <base>...HEAD` — three dots, so the comparison runs against the merge-base and work already on the base branch stays out of the findings.
- `git log <base>..HEAD --oneline` — the change in commit-sized units.

Then validate: `git rev-parse <base>` resolves and the diff is non-empty. A bad ref or an empty diff fails here, in one place, with one readable reason; inside two reviewers it fails as two confusing reports.

**Done**: base resolves and the diff plus commit list are captured — or the run stopped here naming the bad ref or the empty diff.

## [YOU] Phase 2: Find the spec

Hunt in this order and stop at the first hit:

1. Issue references in the commit messages (`#123`, `Closes #45`, GitLab `!67`), fetched by the workflow in `docs/agents/issue-tracker.md`. That file missing: tell the user to run `/setup-matt-pocock-skills`.
2. A path passed as an argument.
3. A spec file under `docs/`, `specs/`, or `.scratch/` matching the branch name or the feature.
4. Ask the user. If they say there is no spec, record the absence.

A recorded absence skips the Spec axis and the report says so in its place. An invented spec reviews the code against fiction, so a skip reads better than a guess.

**Done**: spec contents in hand, or its absence confirmed and recorded where the aggregate can see it.

## [YOU] Phase 3: Find the standards

Collect what the repo documents about how code gets written: `CODING_STANDARDS.md`, `CONTRIBUTING.md`, `AGENTS.md`, lint configs that spell out intent.

On top of that sits the smell baseline, which applies even when the repo documents nothing. It lives in `skill://code-review/references/smells.md`. Point the Standards reviewer at that URI instead of pasting the list: one home for the baseline means each reviewer reads it fresh, and changing the baseline is one edit rather than an edit in every dispatch prompt.

**Done**: standards paths listed and skimmed for rules, or "none documented" recorded, with the baseline pointer ready to send.

## [AGENTS] Phase 4: Review one axis

Dispatch both reviewers in one batch. They share no state, so serialising them buys latency and nothing else. Both are read-only: findings travel in the report, never as edits.

**Standards reviewer** — brief: the diff command, the commit list, the standards paths, and the pointer `skill://code-review/references/smells.md`.

> Read the baseline before matching against it. Report, per file or hunk: (a) each place the diff breaks a documented standard, citing the file and the rule; (b) each baseline smell you spot, named, with the hunk quoted. A documented breach can be hard; a smell is always a judgement call, and a documented repo standard overrides the baseline wherever it endorses the pattern. Skip whatever tooling already enforces. Under 400 words.

**Spec reviewer** — brief: the diff command, the commit list, and the spec path or contents.

> Report: (a) requirements the spec asked for that are missing or partial; (b) behaviour in the diff nobody asked for, scope creep; (c) requirements that look implemented but whose implementation looks wrong. Quote the spec line behind each finding. Under 400 words.

**Done**: both briefs dispatched in one batch, each naming the diff command and its own inputs, and no axis left to a same-thread pass.

## [YOU] Phase 5: Aggregate

Present the two reports under `## Standards` and `## Spec`, verbatim or lightly cleaned. Keep them apart: no merging, no reranking, no single winner across axes. That cross-axis ranking is the move _Why two axes_ exists to block.

Close with one line per axis: how many findings, and the worst issue **within that axis**, if any.

**Done**: both headings carry their report, or `## Spec` records the skip; both closing lines carry a count and a named worst issue; no finding moved between axes.

## Why two axes

A change can pass one and fail the other:

- Follows every convention, implements the wrong thing → **Standards pass, Spec fail.**
- Does exactly what the issue asked, breaks the project's conventions → **Spec pass, Standards fail.**

One combined report lets the stronger axis mask the weaker: a clean spec match buries a convention breach, tidy code buries a missing requirement. Separate reports keep both visible.
