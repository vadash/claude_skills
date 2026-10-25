---
name: implement-agents
description: "Implement a spec or issue as reviewed, committed slices. First arg `freebuff` sends reviews to the freebuff Instance."
disable-model-invocation: true
---

Invocation: `/skill:implement-agents [freebuff] <spec | issue://N>`.

`freebuff` as the first arg sends reviews to the freebuff Instance — another model, its own allowance; every other phase is identical, and a freebuff failure never blocks (see Review mechanics). Another skill dispatching here names the mode (default: harness) and supplies the spec. Invoking this skill authorizes local commits and `git push` (never a merge) on the current branch.

The root session is the **Orchestrator**: coordination and context hygiene only. Source reading, diffs, and long logs stay in subagents.

Dispatch through `task` as one batch per phase: top-level `context` (shared goal and constraints) plus `tasks[]`, each item with `task` and `solutionSpace`; `scout` reads, `task` writes, `reviewer` reviews. Never pass `tools` — it whitelists eval-kernel tools and strips the native set.

Flow: [Scout if cold] → Plan → per slice [Write → Wall → Commit → Review] → end review → push → report.

## Phase 0: Preflight

- `git status --porcelain` dirty → stop; the run must own every commit it reports.
- `git rev-parse HEAD` → **run base**; the end review diffs from it. Stay on the current branch.
- **Spec**: `read` `issue://<N>` (or `issue://<owner>/<repo>/<N>`), plus the root issue when the ticket has a parent; `gh` only if the URI fails. Distill **R1…Rn** — the list every reviewer gets.
- A spec gap that changes the design → one question before Phase 2; a small one → take the boring option, report it.
- **Warm** (design already in this conversation, e.g. after `grilling` or `to-spec`) → skip Phase 1; **cold** (ticket reference, fresh session) → run it.

**Done**: clean tree, run base recorded, numbered requirement list distilled.

## Phase 1: Scout (cold only)

One batch, two `scout` tasks:

- **Codebase**: files, functions, callers, signatures for `<ticket>`; exact test, lint, typecheck, and format commands from `package.json` and configs; paths of the standards docs (`CONTRIBUTING.md`, `AGENTS.md`).
- **Domain**: canonical terms and constraints from `CONTEXT.md` and `docs/`; test fixtures and the patterns to emulate.

**Done**: target files, seams, standards paths, and verification commands named.

## Phase 2: Plan

1. **Public seam** — where tests observe behavior without internals.
2. **Slices** — 1–3 tracer bullets, each green end-to-end, each with its files, verification command, and commit message. A slice's file list carries every file the suite needs at its boundary; a slice that needs its successor to go green is not a boundary — merge or move files.
3. **Writers**: fresh per slice when slices touch disjoint modules, one throughout when each re-reads the previous diff. Boundaries and contracts go in the dispatch.
4. **Reviews**: one after each slice commit except the last — the end review covers the last slice and the run.

**Done**: every slice has files, a commit boundary, a verification command, and a review point.

### Edit ownership

The Writer owns first edits — every slice, the end-reviewed one included, even when the Orchestrator already holds the design. Context economy is why the handoff is written, not a reason to self-implement. No Writer dispatch for a slice → stop before 3c and dispatch.

After that, the Orchestrator touches tracked files only for a **mechanical** fix (stateable in one line: format, import, typo, lint nit), for findings from a review of that slice once a reviewer has reported, or to stage, commit, edit `.gitignore`, clean `.work/`, dispatch reviews. No design work, no first implementation between Writer and commit.

## Phase 3: Slice loop

### 3a Write

One Writer (`task`) per slice, sequentially — never in parallel.

```markdown
Target slice: <description>
Public seam: <interface contract>
Files: <paths>
Verification command: <targeted test command>

First read and follow: skill://tdd, skill://ponytail, skill://documenting-code, skill://caveman.
1. Failing test at the public seam first; run it to RED.
2. Shortest diff to GREEN: stdlib before custom, no speculative abstraction; comments only for a non-obvious "why".
3. Run the verification command and report the diff summary plus the RED/GREEN output.
```

**Done**: targeted test green, RED→GREEN proof in the report.

### 3b Wall

**Wall** = typecheck, lint, format, then the full suite, using the commands Phase 1 found (a warm run takes them from the repo's scripts or the brief); when a pre-commit hook covers the static checks, the suite alone. No suite in the repo → say so and rely on the targeted test.

Fix and rerun: a mechanical fix the Orchestrator makes itself, anything else one Writer fixer with the failure output.

**Done**: static checks and the full suite green.

### 3c Commit

Clear temp files, update `.gitignore` if needed. `HEAD` before this commit is the slice's review **base**. Stage by path, then check `git status` — `git add -A` only when the tree holds nothing unrelated.

```bash
git add <slice paths>
git commit -m "<type>(<scope>): <summary>"   # `closes #<issue>` on the run's last commit
```

**Done**: one commit, working tree clean, base recorded.

### 3d Review the slice (every slice but the last)

Review `<base>..HEAD` under [Review mechanics](#review-mechanics). Both axes `PASS` → next slice. Otherwise fix (design or multi-site: Writer; mechanical: direct), rerun the wall, commit `fix(<scope>): address review findings`, next slice — no second review of that slice.

**Done**: both axes `PASS`, or the fix commit is green.

## Phase 4: End review (at most two invocations)

Range `<run base>..HEAD` — every commit of the run. Review 1 is the same two-axis invocation; fixes → wall → commit as in 3d.

**Review 2** runs only after review 1 produced fixes: re-check each review-1 finding against the fix commits, scan the fix diff. A finding here gets one fix, not a third invocation; whatever stays open is recorded verbatim in the report.

**Done**: both axes `PASS` on the last invocation, or every open finding has a fix commit and a report line.

## Phase 5: Push and report

```bash
git push          # no upstream → git push -u origin HEAD
git status -sb
```

One row per slice, then the open findings and any freebuff fallback:

| Slice | Commit | Review | Tests |
|---|---|---|---|

**Done**: tree clean, branch synced, `git log --oneline <run base>..HEAD` shows exactly the slice commits.

## Review mechanics

Run `skill://code-review` steps 1–5 as the Orchestrator, skipping its issue-tracker lookup: the spec is the R-list. Dispatch Standards and Spec as one parallel batch, each prompt self-contained with the smell baseline pasted verbatim.

```markdown
Review the committed range <base>..HEAD in <repo>.
Run: git log <base>..HEAD --oneline; git diff <base>...HEAD
Read and follow skill://code-review. Axis: <Standards | Spec>.
Standards sources: <repo standards paths>
<full smell baseline from skill://code-review>
Spec: <R1…Rn>
Report under 400 words: clean = `PASS`; findings cite file:line and quote the hunk or standard.
```

Findings are judgement calls, not a score.

**Freebuff mode**: the Instance replaces both `reviewer` subagents — a different model, no `skill://` access.

- One `freebuff_run` per axis in one turn, then one `freebuff_wait` each. The target is the session cwd's git root (no path argument); one Task owns the Instance at a time and only its owner session is answered (`not_owner` otherwise). Keep the tree untouched while Tasks run.
- Prompt: the template above minus the `skill://` line, plus code-review's step-4 brief, the baseline, the spec, and the standards paths. End with: "Review only: run git, read, report; do not edit files or commit."
- Any failure — no quota, a tool error (`busy`, `lock_busy`, `not_owner`), a missing tool, a `failed` verdict — reruns the unfinished axes (both when neither ran) with harness `reviewer` agents, then switches the rest of the run to harness mode. Note it in the report.
