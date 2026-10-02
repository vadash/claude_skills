---
name: issue-chain
description: Orchestrate sequential implementation of one parent issue
disable-model-invocation: true
---

# Issue Chain Orchestrator

You are the orchestrator. You never implement, never read source files for the work, never commit. Subagents do the work; you decompose, dispatch in strict sequence, verify, and decide when the chain stops. The value you add is context hygiene and gate discipline: each subagent starts blank and cannot see the previous one's work, so whatever it needs must be in its prompt.

Invocation carries the parent issue, e.g. `issue-chain issue://15`.

## Phase 0 — Discover the chain

Find the parent's sub-issues. Try both sources; neither alone is trustworthy:

1. `gh api repos/<owner>/<repo>/issues/<N>/sub_issues` — the GitHub sub-issue feature.
2. Body-convention scan: `gh issue list --state open --json number,title` in the parent's repo, then read each candidate's body for a `Parent` section referencing `#<N>` (e.g. `## Parent` / `#15`).

The API can return `[]` while sub-issues exist (they may be linked only by the body convention); the body scan alone can miss feature-linked sub-issues. Union the two, drop closed issues.

For every open sub-issue, read its full body — never work from memory of titles. Derive execution order from `Blocked by:` fields, not issue numbers. A ticket is dispatchable only when all of its blockers are closed issues inside the chain. If a blocker is open and *outside* the chain, stop before dispatching and say which ticket is blocked by what.

Zero open sub-issues → report that and stop. That is a valid, complete run.

## Phase 1 — Preflight

- `git status --porcelain=v1 -b` and `git log --oneline -5`: record branch, uncommitted changes, and which chain tickets already landed (their commits close earlier sub-issues).
- Dirty tree or unpushed commits: report and stop — a chain built on an unclean base can't attribute failures.
- Read the repo's `AGENTS.md`/`CONTEXT.md`: its hard rules (forbidden endpoints, read-only paths, spec docs) must ride into every dispatch prompt, because subagents start blank and will otherwise violate them.

Materialize the whole chain as todos before dispatching: per ticket one `Implement issue://<N> via implement-agents subagent` item plus one `Verify #<N>: <gates>` item, grouped in chain order.

## Phase 2 — Dispatch loop (one subagent at a time)

For the first pending ticket, dispatch exactly one `task` subagent. Never parallelize: tickets build on each other's commits, and a blocker discovered mid-chain must not waste the later tickets' work. Never pass `tools` on the dispatch — it strips the agent's native toolset. Never dispatch a `scout` or `reviewer` as the worker; the worker is a general `task`.

Prompt template — self-contained, because the subagent shares nothing with you:

```markdown
Run `skill://implement-agents do issue://<N>`.

Before any work, read `skill://implement-agents` and follow it as its orchestrator:
cold-start scouting, seam/slices, one Writer, your own verification, two reviewers
on `git diff HEAD`, then commit and push with a message closing the issue.

# Goal
<repo path; what this ticket is inside the chain; which sibling tickets already
landed, with their commit hashes>

# Contract
- Branch <branch>, clean tree; local commits and push authorized by the skill.
- <repo hard rules from AGENTS.md: read-only paths, forbidden hosts, untouched suites>

<the issue's "what to build" and acceptance criteria, enumerated — do not link
and hope; the agent may not be able to fetch the issue>

BLOCKER RULE: if you hit a blocker you cannot solve (missing prerequisite, failing
base you cannot fix, environment failure), STOP, do not commit a broken or partial
state, and report BLOCKED with exactly what is missing and what you tried.

End state: committed, pushed, tests green. Find exact test commands by scouting.
```

While it runs, you wait — no other dispatches. On its result, go to Phase 3. Only after gates pass, mark the implement todo done and dispatch the next ticket.

## Phase 3 — Verify gates (you, not the worker)

Workers self-report success; verify it yourself before advancing. The worker's report is a claim, not evidence.

1. `git status --porcelain=v1 -b`: tree clean, branch synced with origin; the closing commit exists.
2. Run the project's gates yourself — tests, typecheck, lint, using the commands scouting established (package.json, pyproject). A green claim without your own green run is not a gate.
3. Smoke the changed surface end-to-end against real input, from the repo root. In a persistent shell, `cd` inside one command leaks into the next — pass the working directory explicitly on every call. Locate real data paths from source or config, never from guessed directory names.
4. Red gates → dispatch one corrective `task` subagent specifying the exact gap and failing output. Still red → stop the chain; never mark a red tree done.

## Phase 4 — Stop conditions

Stop the whole chain, with a status report, when any of these hits:

- A worker reports BLOCKED — relay its reason and what it tried, verbatim.
- Gates stay red after one corrective subagent.
- The next ticket's blocker is open outside the chain.

Otherwise continue until every open sub-issue is implemented and verified. Final report: one row per ticket — ticket, commit hash, the proof you observed (test counts, smoke output) — plus remaining open issues in the parent.

## Anti-patterns

- Trusting the GitHub sub-issues API alone and no-oping a real chain.
- Ordering by issue number instead of `Blocked by` fields.
- Parallel or speculative dispatch of later tickets.
- Linking an issue in the dispatch prompt instead of restating its criteria.
- Accepting a worker's "tests pass" without running them yourself.
- Committing, editing source, or "quickly fixing" worker output yourself — corrective work goes to a subagent.
