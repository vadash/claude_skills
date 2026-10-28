---
name: implement
description: Implement a spec or issue as reviewed, committed slices, then push.
disable-model-invocation: true
---

You are the **Orchestrator** (`[YOU]`) for one ticket. `[YOU]` means this thread: it holds the plan, the git state, and the report, and that is the run's memory. `[AGENTS]` marks a phase that must be a subagent dispatch — source reading, diffs, and long logs live there, so the memory survives the whole run.

Dispatch through `task`, one batch per phase: top-level `context` (shared goal and constraints), `tasks[]` each with `task` and `solutionSpace`; `scout` reads, `task` writes, `reviewer` reviews. Never pass `tools` — it whitelists eval-kernel tools and strips the native set.

Invocation: `/skill:implement [freebuff] <spec path | issue://N>`. Another skill dispatching here supplies the spec and names the mode (default: harness). Invoking authorizes local commits and `git push` on the current branch, never a merge.

Flow: `[Scout if cold] → Plan → per slice [Worker → Wall → Commit → review?] → end review → push → report`. When the mode is `freebuff`, the review phases run per `skill://implement/references/freebuff.md`.

## [YOU] Phase 0: Preflight

- `git status --porcelain` dirty → stop. The run must own every commit it reports.
- `git rev-parse HEAD` → **base**, the end review's fixed point. Stay on the current branch.
- **Spec**: `read` `issue://<N>` (`issue://<owner>/<repo>/<N>` when needed), plus the parent issue when the ticket has one; `gh` only if the URI fails.
- Distil **R1…Rn** — the numbered requirements every reviewer receives. Written down, not remembered.
- A spec gap that changes the design → one question before Plan. A small one → take the boring option and report it.
- **Warm** run (design already in this conversation, e.g. after `to-spec` or a `grilling`) skips Phase 1. **Cold** run (a bare ticket reference) takes it.

**Done**: clean tree, base recorded, R1…Rn written.

## [AGENTS] Phase 1: Scout (cold only)

One batch, two `scout` tasks. Each brief carries R1…Rn verbatim, the repo root, and an explicit question list — a weak model left to "understand the codebase" returns prose the plan cannot use.

- **Repo** scout, loads `skill://codebase-design`: which files and callers does the ticket touch; where are the seam candidates; what are the exact verification commands (from `package.json` and configs); where do the standards docs live (`AGENTS.md`, `CONTRIBUTING.md`).
- **Domain** scout, loads `skill://domain-modeling`: canonical terms; constraints from `CONTEXT.md` and ADRs; which fixtures and test patterns the new tests should emulate.

Output contract, identical for both: ≤500 words, fixed shape `Files / Seams / Commands / Standards`, every claim as `path:line`, no code. Why fixed: the plan consumes four named things, and a shape that names them fails loudly when one is missing.

**Done**: target files, seams, verification commands, and standards paths named, each with a `path:line`.

## [YOU] Phase 2: Plan

1. **Public seam** — the interface where tests observe behaviour without internals.
2. **Slices** — 1–3 tracer bullets, each green end to end. Each carries its files, its verification command, its commit message, and a **review flag**. A slice's file list holds every file the suite needs at its boundary; a slice that needs its successor to go green is not a boundary — merge it or move the files.
3. **Workers** — one fresh Worker per slice when the slices touch disjoint modules; one Worker throughout when each slice re-reads the previous diff.
4. **Review points** — the flagged slices and the end review.

Flag a slice for review when it touches the public seam or a contract a later slice consumes, or when it spans more than one file or is non-mechanical. Decide here, once: a flag set mid-flight bends to whatever the run already wrote, and seam or shared-contract is exactly the property that makes a late discovery expensive.

**Done**: every slice has files, a commit boundary, a verification command, a review flag; the seam is named.

## [YOU] Phase 3: Slice loop

### [AGENTS] 3a Worker

One Worker (`task`) per slice, sequentially — never in parallel.

```markdown
Target slice: <description>
Public seam: <interface contract>
Files: <paths>
Verification command: <targeted test command>

First read and follow: skill://tdd, skill://ponytail, skill://documenting-code, skill://caveman.
```

**Done**: the targeted test is green, with RED→GREEN proof in the report.

### [YOU] 3b Wall

**Wall** = typecheck, lint, format, then the full suite, using the commands Phase 1 found (a warm run reads them from the repo's scripts). When a pre-commit hook already runs the static checks, the suite alone is the Wall. No suite in the repo → say so and let the targeted test stand.

Fix and rerun: a **mechanical** fix — stateable in one line, e.g. format, import, typo, lint nit — you make yourself; anything else goes to one Worker fixer with the failure output.

**Done**: static checks and the full suite green.

### [YOU] 3c Commit

Clear temp files; update `.gitignore` when the slice produced debris. `HEAD` before this commit is the slice **base**. Stage by path, then read `git status`; `git add -A` only when the tree holds nothing unrelated. One commit per slice.

```bash
git add <slice paths>
git commit -m "<type>(<scope>): <summary>"   # `closes #<issue>` on the run's last commit
```

**Done**: one commit, clean tree, slice base recorded.

### [AGENTS] 3d Review the slice (flagged slices only)

Run `skill://implement/references/review.md` over `<slice base>..HEAD`. Both axes `PASS` → next slice. Otherwise fix, Wall, commit `fix(<scope>): address review findings`, then next slice — a reviewed slice gets no second review.

**Done**: both axes `PASS`, or the fix commit is green.

## [AGENTS] Phase 4: End review

Range `<base>..HEAD` — every commit of the run — at most two invocations, per `skill://implement/references/review.md`.

**Done**: both axes `PASS` on the last invocation, or every open finding has a fix commit and a report line.

## [YOU] Phase 5: Push and report

```bash
git push          # no upstream → git push -u origin HEAD
git status -sb
```

One row per slice, then the open findings, any freebuff fallback, and any question the run deferred:

| Slice | Commit | Review | Tests |
|---|---|---|---|

**Done**: tree clean, branch synced, and `git log --oneline <base>..HEAD` lists only this run's commits — the slices and their fix commits.

## Edit ownership

The **Worker** makes the first edit on every slice, the end-reviewed one included. The design living in your head is why the handoff is written well, not a reason to type it yourself: your context is the run's memory and a Worker's is disposable — spend the disposable one on the code.

After a Worker reports, you touch tracked files for three things only: a mechanical fix, the findings from that slice's review, and the git and cleanup work — stage, commit, `.gitignore`, `.work/`. Design and implementation go back out as a dispatch.
