---
name: implement-agents
description: "[SUB AGENTS] Implement a piece of work based on a spec or set of tickets."
disable-model-invocation: true
---

The root session is the **Orchestrator**: coordination and context hygiene only. Source reading, diffs, and long logs stay in subagents

- **Agents**: select by `agent` field — `scout` is the read-only Scout, default `task` the Writer (full editing). NEVER pass `tools` on a dispatch: it whitelists eval-kernel `@tool`s and strips the native set.
- **Dispatch shape**: every `task` call is the batch variant — top-level `context` (shared goal + constraints, non-empty) + `tasks[]`, one item per agent (single agent = one-item array); each item needs `task` + `solutionSpace`, `agent` optional (default `task`).

- If user spec located on github run tool READ on it `Read issue://<number>`. If it has root issue then read it too. Only read relevant issues.

# Process

## Phase 0: Cold vs Warm

Decide before calling tools:

- **Warm** — target files, seams, and contracts already in this conversation (e.g. invoked right after `grill-with-docs`, `grilling`, `improve-codebase-architecture`, `to-spec`): skip Phase 1
- **Cold** — invoked from a ticket reference or fresh session: run Phase 1

## Phase 1: Scout (Cold only)

Dispatch 2 parallel Scouts (`scout` task):

- **Scout A — Codebase**: locate files, functions, callers, signatures for `<ticket>`; read `package.json` and configs for exact test, lint, typecheck, format commands
- **Scout B — Domain**: read `CONTEXT.md`, relevant `docs/`, and this feature test fixtures; report canonical terms, constraints, and test patterns to emulate

**Done**: two reports naming target files, seams, and verification commands

## Phase 2: Seam & Slices (Orchestrator)

Synthesize:

1. **Public seam** — the boundary where tests observe behavior without internals
2. **Slices** — 1–3 tracer-bullet vertical slices, each verifiable end-to-end. **Green-complete**: each slice's file list carries every file the full suite needs at its boundary — fixtures, migrated tests. A slice only green together with its successor is not a boundary: merge or move files
3. **Boundary plan** — one row per inter-slice boundary; dials set independently:

   | Dial | Setting | Choose when |
   |---|---|---|
   | Writer | per slice | slices touch disjoint modules; the next writer re-reads little |
   | Writer | one for all | the next writer re-reads most of the earlier diff |
   | Review | per slice | drift risk high — open design inside the slice, weak spec; or review cheap |
   | Review | once at end | spec exhaustive (authored this session), review blocking, diff fits one lens |
   | Commit | per slice | slice green-complete |
   | Commit | once, at last green boundary | slices only-green-together |

   Unconditional: a **verify wall** after every writer — typecheck + full suite before the next dispatch. Mechanical checks never batch; only review and commits do. Boundaries buy error containment, paid in latency and review budget. User may override any dial at plan time

Anti-drift: pass file boundaries and contracts into prompts; the Writer reads primary sources.

**Done**: boundary plan exists — every commit row sits at a green boundary

## Phase 3: Write (Writers per plan)

Trivial edits: Orchestrator edits directly. Otherwise dispatch one Writer (general `task`) with:

```markdown
Target slice: <description>
Public seam: <interface contract>
Target files: <paths>
Verification command: <targeted test command>

Before any work, read and follow: skill://tdd, skill://ponytail, skill://documenting-code, skill://caveman skills
1. TDD: failing test at the public seam first; run it to RED
2. Minimal code to GREEN: stdlib before custom, shortest working diff, no speculative abstractions
3. Self-documenting code; comments only for a non-obvious "why"
4. Run the verification command. Report: diff summary + RED/GREEN proof
```

**Note**: dispatch writers per the boundary plan — up to 3, sequential, never parallel. Run the verify wall after every writer

**Done**: targeted test green, wall green

## Phase 4: Verify (Orchestrator)

Run typecheck, lint, format. Skip if a pre-commit hook already runs them (Scout A reports this). Then run full regression suite

Failures: trivial fixes the Orchestrator does directly; else one Writer fixer with the failure output

**Done**: static checks and suite green

## Phase 5: Review (2 Reviewers)

Cadence comes from the boundary plan: per-slice reviews run before that slice's commit; the end review runs once after the last wall. Review what is done so far — pass the diff range (`git diff <base>`) when slices already committed

Check `git diff HEAD`, stage all relevant files, remove all temp or throwaway, update git ignore if needed.

Then read and follow `skill://code-review`; distill its checklist into the reviewers lenses. Dispatch two `reviewer` subagents on `git diff HEAD`

```markdown
Review the uncommitted work: run `git diff HEAD`
Before any work, read and follow: skill://tdd, skill://ponytail, skill://documenting-code, skill://caveman skills
Spec: <Phase 2 requirement list>
Lens: <Reviewer A or B lens>
Report under 500 words: clean result = `PASS`; findings cite `file:line`
```

### Next

Big blockers → phase 3 for a surgical fix → rerun failed review (if only 1 failed rerun that one)

Small blockers → edit directly -> phase 4 for tests

**Done**: `PASS` from both reviewers

## Phase 6: Commit & push (Orchestrator)

Commit at each planned boundary. Per-slice plans commit a slice as soon as its gate passes — before the next slice touches shared files, or staging can no longer split them. `closes #<issue>` rides the last commit

```bash
git add -A
git commit -m "<type>(<scope>): <summary> (closes #<issue>)"
git push
```

Invoking this skill authorizes local commits and push (no merges) on the current branch

**Completion criterion**: Working tree is clean and local commit is recorded on `git log -1`
