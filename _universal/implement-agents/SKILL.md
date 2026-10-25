---
name: implement-agents
description: "[SUB AGENTS | freebuff] Implement a spec or tickets: scout, slice, commit per slice, two-axis review. First arg `freebuff` runs reviews in the freebuff Instance."
disable-model-invocation: true
---

Invocation: `/skill:implement-agents [freebuff] <spec | issue://N>`.

- **Mode**: `freebuff` as the first word of the args sends reviews to the freebuff Instance — a different model, its own allowance. Every other phase is identical. All other args are spec text.
- **Read as `skill://`** (a dispatch says "run implement-agents on issue://N"): default mode, spec from the dispatch prompt.

The root session is the **Orchestrator**: coordination and context hygiene only. Source reading, diffs, and long logs stay in subagents.

- **Agents**: pick by `agent` field — `scout` read-only, default `task` Writer, `reviewer` reviewer. NEVER pass `tools` on a dispatch: it whitelists eval-kernel `@tool`s and strips the native set.
- **Dispatch shape**: batch variant only — top-level `context` (shared goal + constraints, non-empty) + `tasks[]`, one item per agent (single agent = one-item array); each item needs `task` + `solutionSpace`.
- **Spec**: chat brief, repo path, or `issue://<N>`. Phase 0 fetches it. The requirement list rides into every reviewer prompt.
- Invoking this skill authorizes local commits and `git push` (no merges) on the current branch.

Flow: [Scouts if cold] → plan → per slice [Write → wall → commit → review] → end review → push → report.

## Phase 0: Preflight

- `git status --porcelain`: dirty tree → stop and report. The run must be attributable to its own commits.
- `git rev-parse HEAD` → **run base**. The end review diffs from it.
- **Spec**: fetch `issue://<N>` — or `issue://<owner>/<repo>/<N>` for another repo — with the `read` tool; read the root issue too when the ticket has one. `gh` is the fallback only when the URI fails. Distill the requirement list.
- **Warm** — target files, seams, and contracts already in this conversation (invoked after `grilling`, `grill-with-docs`, `to-spec`, or a detailed brief): skip Phase 1.
- **Cold** — ticket reference or fresh session: run Phase 1.

**Done**: clean tree, run base recorded, requirement list distilled, start branch known.

## Phase 1: Scout (cold only)

Dispatch 2 parallel Scouts (`scout` task):

- **Scout A — Codebase**: locate files, functions, callers, signatures for `<ticket>`; read `package.json` and configs for exact test, lint, typecheck, format commands; name the coding-standards docs (`CONTRIBUTING.md`, `CODING_STANDARDS.md`, `AGENTS.md`).
- **Scout B — Domain**: read `CONTEXT.md`, relevant `docs/`, and this feature's test fixtures; report canonical terms, constraints, and test patterns to emulate.

**Done**: two reports naming target files, seams, standards docs, and verification commands.

## Phase 2: Plan

Synthesize:

1. **Public seam** — the boundary where tests observe behavior without internals.
2. **Slices** — 1–3 tracer-bullet vertical slices, each verifiable end-to-end. **Green-complete**: each slice's file list carries every file the full suite needs at its boundary — fixtures, migrated tests. A slice only green together with its successor is not a boundary: merge or move files.
3. **Plan rows** — per slice: files, verification command, commit message. The last slice is the end-review slice.
4. **Review budget** — one review invocation per slice after its commit, except the last slice; the end review covers the last slice and the whole run. An invocation runs both axes (Standards, Spec).
5. **Writers** — one fresh Writer per slice when slices touch disjoint modules; one Writer for all when the next re-reads most of the earlier diff. Pass file boundaries and contracts into prompts; the Writer reads primary sources.

**Done**: plan names each slice's files, commit boundary, verification command, and review boundary.

## Phase 3: Slice loop

### 3a Write

Trivial edits: the Orchestrator edits directly. Otherwise dispatch one Writer (general `task`):

```markdown
Target slice: <description>
Public seam: <interface contract>
Target files: <paths>
Verification command: <targeted test command>

Before any work, read and follow: skill://tdd, skill://ponytail, skill://documenting-code, skill://caveman.
1. TDD: failing test at the public seam first; run it to RED.
2. Minimal code to GREEN: stdlib before custom, shortest working diff, no speculative abstractions.
3. Self-documenting code; comments only for a non-obvious "why".
4. Run the verification command. Report the diff summary plus RED/GREEN proof.
```

Writers run sequentially, never parallel.

**Done**: targeted test green, RED/GREEN proof in the report.

### 3b Wall

Run typecheck, lint, and format, then the full regression suite. When a pre-commit hook already runs the static checks, run the suite only.

Failures: trivial fixes the Orchestrator does directly; otherwise one Writer fixer with the failure output.

**Done**: static checks and the full suite green.

### 3c Commit

Remove temp and throwaway files; update `.gitignore` when needed. Record `git rev-parse HEAD` as **`<base>`** for this slice. Stage the slice's files by path, then check `git status` — `git add -A` only when the tree holds nothing unrelated.

```bash
git add <slice paths>
git commit -m "<type>(<scope>): <summary>"
```

`closes #<issue>` rides the run's last commit.

**Done**: the slice is one commit on `git log -1`; working tree clean.

### 3d Slice review (every slice but the last)

Review the committed range: `git diff <base>...HEAD` and `git log <base>..HEAD --oneline`. Read `skill://code-review` and follow its steps 1–5 as the Orchestrator; the spec is the Phase 2 requirement list, so skip its issue-tracker lookup. Dispatch its two axes, Standards and Spec, as one parallel batch. Paste its smell baseline verbatim into both prompts, so each axis prompt is self-contained.

```markdown
Review the committed range <base>..HEAD in <repo>.
Run: git log <base>..HEAD --oneline; git diff <base>...HEAD
Read and follow skill://code-review. Axis: <Standards | Spec>.
Standards sources: <repo standards file paths>.
<full smell baseline from skill://code-review>
Spec: <Phase 2 requirement list>
Report under 400 words: clean = `PASS`; findings cite file:line and quote the hunk or standard.
```

**Freebuff mode**: the freebuff Instance replaces the two `reviewer` subagents — a separate agent, a different model, no `skill://` access.

- Submit both axes in one turn (`freebuff_run` twice), then drain with two `freebuff_wait` calls.
- Target is the session cwd git root; there is no path parameter. Only the owning root session gets answers; subagents are refused `not_owner`.
- Keep the tree clean and untouched while the Tasks run.
- Prompt: the same template without the `skill://` line, plus the code-review step-4 brief for the axis, the baseline, the spec, and the standards paths. End with: "Review only: run git, read, report; do not edit files or commit."
- A `failed` Task returns its Verdict and a screen excerpt: record it as an unresolved finding, never a `PASS`.

**Behaviour**: `PASS` from both axes → next slice. Findings → fix big blockers with one Writer, small ones directly → rerun the wall (3b) → commit the fixes (`fix(<scope>): address review findings`) → next slice. This is the slice's only review invocation.

**Done**: both axes `PASS`, or the fix commit is green.

## Phase 4: End review (at most two invocations)

The range is `<run base>...HEAD` and covers every commit of the run. Review 1 uses the same template and axis dispatch as 3d.

- **Fixes** → wall → commit, as in 3d.
- **Review 2** runs only after review 1 produced fixes. It is confirmation: re-check every review-1 finding against the fix commits and scan the fix diff. A finding there gets one fix, not a third invocation.
- **No third invocation.** Unresolved findings are recorded verbatim for the final report; the run does not loop.

**Done**: both axes `PASS` on the last invocation, or every remaining finding has a fix commit and a report line.

## Phase 5: Push and report

```bash
git push
git status -sb
```

Final report: one row per slice — slice, commit hash, review result, test evidence. Then the unresolved findings, verbatim.

**Completion criterion**: working tree clean, branch synced with origin, `git log --oneline <run base>..HEAD` shows the slice commits.
