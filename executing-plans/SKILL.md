---
name: executing-plans
description: Execute specific tasks from an implementation plan in a clean session.
disable-model-invocation: true
argument-hint: [plan-path] do task [N or N-M]
---

# Executing Plans

Execute only the tasks explicitly requested from an implementation plan.

<HARD-GATE>
Execute ONLY the task or task range the user requested. Stop exactly when the requested scope is complete. Do not continue to the next task beyond the requested range.
</HARD-GATE>

## Input

Parse `$ARGUMENTS` to determine:
1. **Plan path** — the plan file to read
2. **Task range** — which tasks to execute (e.g., "do task 1", "do task 1-3")

Examples:
- `/executing-plans docs/plans/2025-01-15-auth.md do task 1`
- `/executing-plans docs/plans/2025-01-15-auth.md do task 2-4`

## Assumptions

Before starting, these MUST be true:
- All previous tasks in the plan are already completed
- All tests are currently passing
- The git working tree is clean

If any assumption is violated, stop and inform the user before proceeding.

## Execution

For each task in the requested range:

1. Read the task steps from the plan
2. Follow the TDD red-green cycle exactly as written in the plan:
   - Write the failing test
   - Run it — verify it fails as expected
   - Write the minimal implementation
   - Run tests — verify they pass
3. Commit after each completed task

**If a test fails unexpectedly:** Stop guessing. Apply systematic debugging — investigate the root cause methodically before attempting a fix.

**If blocked:** Stop executing and ask the user for help. Do not guess or work around missing dependencies, unclear instructions, or repeated failures.

## Verification

After completing all requested tasks:
- Run the full test suite — confirm everything passes
- Verify the git working tree is clean (all changes committed)
- Report what was completed

## Completion

> "Tasks [N-M] complete. All tests passing, working tree clean.
> Run `/clear`, then `/executing-plans [plan-path] do task [next]` to continue."

**Stop.** Do not continue beyond the requested scope.
