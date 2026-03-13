---
name: auto-execute
description: Executes a single task from a plan in headless automated mode. Use when running automated plan execution via the auto-execute.ps1 wrapper with no human present.
disable-model-invocation: true
argument-hint: <plan-path> do task <N>
---

# Auto-Execute: Headless Task Execution

Execute exactly one task from an implementation plan in automated/headless mode. This skill is invoked by the `auto-execute.ps1` wrapper script — not by humans directly.

<HARD-GATE>
Execute ONLY the single task specified. Do NOT continue to the next task. The PS1 wrapper decides what's next.
</HARD-GATE>

## Input

Parse `$ARGUMENTS` to determine:
1. **Plan path** — the plan file to read
2. **Task number** — which single task to execute (e.g., "do task 3")

Example: `/auto-execute docs/plans/2026-03-13-auth.md do task 3`

## Headless Operation Rules

You are running headless in an automated loop with no human present.

- DO NOT ask the user for clarification.
- DO NOT wait for user input.
- IF BLOCKED by a missing dependency, failing test you cannot solve in 3 attempts, or unclear instruction: STOP immediately with the failure output format below.

## Assumptions

Before starting, these MUST be true:
- All previous tasks in the plan are already completed
- All tests are currently passing
- The git working tree is clean

If any assumption is violated, output the failure format and stop. Do not prompt.

## Execution

1. Read the specified task from the plan
2. Follow the TDD red-green cycle exactly as written:
   - Write the failing test
   - Run it — verify it fails as expected
   - Write the minimal implementation
   - Run tests — verify they pass
3. Commit after the completed task

**If a test fails unexpectedly:** Apply systematic debugging. You have 3 attempts to fix it. After 3 failed attempts, stop with the failure output.

**If blocked:** Stop immediately with the failure output. Do not guess or work around.

## Structured Exit Output

Your FINAL line of output MUST be exactly one of:

**Success:**
```
[AUTO-EXECUTE] Task N COMPLETE. Commit: <hash>
```

**Failure:**
```
[AUTO-EXECUTE] Task N FAILED. Reason: <description>
```

## Completion

After outputting the structured exit line, STOP. Do not suggest next steps. Do not continue to the next task.
