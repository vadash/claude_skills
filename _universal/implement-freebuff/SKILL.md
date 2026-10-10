---
name: implement-freebuff
description: "[SUB AGENTS + freebuff] Implement a piece of work based on a spec or set of tickets."
disable-model-invocation: true
---

The root session is the **Orchestrator**: coordination and context hygiene only. Source reading, diffs, and long logs stay in subagents

- **Agents**: select by `agent` field — `scout` is the read-only Scout, default `task` the Writer (full editing). NEVER pass `tools` on a dispatch: it whitelists eval-kernel `@tool`s and strips the native set.

- If user spec located on github run tool READ on it `Read issue://<number>`. If it has root issue then read it too.

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
2. **Slices** — 1–3 tracer-bullet vertical slices, each verifiable end-to-end

Anti-drift: pass file boundaries and contracts into prompts; the Writer reads primary sources.

## Phase 3: Write (1 Writer)

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

**Note**: you can dispatch up to 3 writers sequential, never parallel

**Done**: targeted test asserting the new behavior passes

## Phase 4: Verify (Orchestrator)

Run typecheck, lint, format. Skip if a pre-commit hook already runs them (Scout A reports this). Then run full regression suite

Failures: trivial fixes the Orchestrator does directly; else one Writer fixer with the failure output

**Done**: static checks and suite green

## Phase 5: Review (2 Reviewers via freebuff MCP)

Read and follow `skill://code-review`; distill its checklist into the reviewers lenses. Reviews run in the freebuff Instance — a separate agent with its own model. The bundled `reviewer` subagent shares this harness — not a substitute. Reviews are two sequential `run_prompt` calls with `dir` = this repo absolute path on every call

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

```bash
git add -A
git commit -m "<type>(<scope>): <summary> (closes #<issue>)"
git push
```

Invoking this skill authorizes local commits and push (no merges) on the current branch

**Completion criterion**: Working tree is clean and local commit is recorded on `git log -1`
