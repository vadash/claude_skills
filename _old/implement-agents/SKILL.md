---
name: implement-agents
description: Executes implementation plans using specialized subagents for scouting, TDD coding, verification, and two-axis review. Use when building a feature or bug fix from a spec, issue, or grilled plan.
disable-model-invocation: true
---

# Implement Agents

The root session is the **Orchestrator**. Its objective is high-level coordination and context hygiene (<150k tokens in the Smart Zone). Heavy source-code reading, implementation diffs, and verification logs are delegated to isolated subagents.

---

## Skill Delegation

Pass skills explicitly into subagent prompts so they load inside isolated context windows.

Bare `/skill:` tokens auto-load inside a **subagent** prompt; backticked names do not load anywhere. Keep names backticked in prose/tables so the orchestrator never auto-loads them, and paste the bare copy-verbatim block into every dispatch prompt.

### Reference table (informational — do NOT copy from this table)

- **Orchestrator**: `/skill:caveman`
- **Scouts** (Cold only): `/skill:caveman`
- **Writer** (Coder): `/skill:caveman`, `/skill:tdd`, `/skill:ponytail`, `/skill:documenting-code`
- **Verifiers**: `/skill:caveman`
- **Reviewers**: `/skill:caveman`

Dont read or find skill, just treat it as magic strings. Sub agents will find it

### Subagent Skill Headers (copy verbatim, never edit)

Dispatch prompts MUST begin with the exact matching line from these blocks. Copy the ENTIRE line. Never retype, reorder, add, or drop entries.

```text
Scout / Verifier / Reviewer:
Load skills: /skill:caveman.

Writer:
Load skills: /skill:tdd, /skill:ponytail, /skill:documenting-code, /skill:caveman.
```

---

## Concurrency and Subagent Rules

- **Execution Capabilities**: Verifiers and Writers **require shell/bash execution**. Never dispatch them as read-only scouts.
- **Read-Only / Verification Tasks**: Up to **2 concurrent subagents** (`Max Concurrent Tasks: 2`).
- **State-Modifying Tasks (Writers)**: Strictly **1 writer at a time**. Never run parallel editing agents.
- **Reporting Contract**: Subagents must return plain markdown directly in their response body. Never bury reports inside nested JSON keys or external payloads that risk truncation.

---

## Process

### Phase 0: Context Evaluation (Cold vs. Warm)

Evaluate context state before calling tools:

- **Warm Context**: Target files, public seams, and behavioral contracts are already established in the current conversation (e.g., invoked immediately after `grill-with-docs`, `grilling`, `improve-codebase-architecture`, or `to-spec`).
  - **Action**: **Skip Phase 1 entirely.** Proceed directly to Phase 2.
- **Cold Context**: Invoked from an issue reference, ticket path, or fresh session (e.g., `/implement-agents #42` or `.scratch/issues/01.md`).
  - **Action**: Proceed to Phase 1.

---

### Phase 1: Scout & Frame (Cold Only — 2 Parallel Subagents)

Never dump raw source files into the Orchestrator. Dispatch two parallel Scout subagents:

- **Scout A (Codebase & Verification Commands)**:
  - *Prompt*: "Load /skill:caveman. Locate target files, functions, callers, and signatures for `<ticket/issue>`. Inspect package.json and config files for exact test, lint, typecheck, and format commands. Report under 200 words."
- **Scout B (Domain & Prior Art)**:
  - *Prompt*: "Load /skill:caveman. Read `CONTEXT.md`, relevant `docs/adr/`, and test fixtures in `tests/` for this feature area. Report canonical domain terms, constraints, and test patterns to emulate. Report under 200 words."

**Completion criterion**: Orchestrator receives two structured markdown reports identifying target files, seams, and verification scripts.

---

### Phase 2: Seam & Slices (Orchestrator)

Synthesize context into:
1. **The Public Seam**: The boundary where tests observe behavior without inspecting internals.
2. **Vertical Slices**: Outline 1–2 minimal tracer-bullet vertical slices. Each slice must be verifiable end-to-end.

**Anti-Drift Rule**: Do **not** inspect or grep full source files in the Orchestrator. Pass target file boundaries and contracts into the Writer's prompt; let the Writer read primary sources.

---

### Phase 3: Write & TDD (Strictly 1 Writer)

- **Trivial edits (<30 lines, 1 file)**: Orchestrator edits directly (`ponytail` rule).
- **Substantive changes**: Dispatch a single **Writer subagent** with execution access.

#### Writer Subagent Prompt Template:
```markdown
Load skills: /skill:tdd, /skill:ponytail, /skill:documenting-code, /skill:caveman.

Target slice: <description of slice>
Public seam: <interface contract>
Target files: <paths>
Verification command: <targeted test command>

Rules:
1. TDD: Write failing test first at the public seam. Run test to verify RED.
2. Ponytail: Write minimal code to turn test GREEN. Use stdlib/native solutions, shortest working diff, no speculative abstractions.
3. documenting-code: Self-documenting code only. Absolutely NO line-by-line comments, NO section banners. Comments allowed only for non-obvious "Why".
4. Run targeted verification.

Report in plain markdown under 200 words: diff summary and RED/GREEN test output proof.
```

**Completion criterion**: Targeted test asserting the new behavior passes.

---

### Phase 4: Fast Verification (Up to 2 Parallel Subagents)

Run verification commands using **execution-capable subagents** (never read-only scouts):

- **Verifier A (Static Checks)**: Run typecheck (`tsc`), linting, and format checks.
  *(Note: If the repository enforces a pre-commit hook that already executes these checks, Verifier A can be skipped).*
- **Verifier B (Test Suite)**: Run full regression test suite (`npm test`, `pytest`, etc.).
- **Contract**: If clean, report `PASS`. If failing, report only the file, line, and concise error (under 10 lines).

#### Handling Failures:
- For trivial syntax, formatting, or type adjustments (<10 lines), the Orchestrator fixes directly.
- For substantive logic errors, dispatch a single Writer fixer with the failure output.

**Completion criterion**: Both static checks and regression suite confirmed green.

---

### Phase 5: Two-Axis Review (2 Parallel Subagents)

Review the uncommitted diff against `HEAD` using two parallel subagents:

- **Standards Subagent**:
  - *Prompt*: "Load /skill:caveman. Review `git diff HEAD`. Check adherence to repo coding standards, `CONTEXT.md` vocabulary, ADR constraints, and Fowler code smells (feature envy, primitive obsession, speculative generality). Report findings with file:line citations under 200 words. If clean, report PASS."
- **Spec Subagent**:
  - *Prompt*: "Load /skill:caveman. Compare `<originating issue/contract>` against `git diff HEAD`. Check for missing requirements, behavioral drift, or scope creep. Report findings with citations under 200 words. If clean, report PASS."

If blockers are identified, return to Phase 3 for a surgical fix.

**Completion criterion**: Both reviews pass with zero blocker findings.

---

### Phase 6: Commit (Orchestrator)

1. Verify working tree status:
   ```bash
   git status --porcelain
   ```
2. Explicitly stage modified files:
   ```bash
   git add -A
   ```
3. Commit with a conventional commit message referencing the issue/task:
   ```bash
   git commit -m "<type>(<scope>): <summary> (closes #<issue>)"
   ```
4. **Safety Guardrail**: Invocation of this skill authorizes local commits on the current branch. **Never push or sync to remotes** unless the user explicitly commands it.

**Completion criterion**: Working tree is clean and local commit is recorded on `git log -1`.
