---
name: writing-plans
description: Convert a design document into a sequential TDD implementation plan.
disable-model-invocation: true
argument-hint: [design-doc-path]
---

# Writing Plans

Read the design document and produce a detailed, sequential implementation plan using TDD red-green methodology.

Write the plan assuming the implementer has zero context about the codebase or problem domain. Document everything: which files to touch, complete code, exact test commands, expected output.

<HARD-GATE>
Do NOT write implementation code. Your ONLY output is a plan document. Stop after the plan is committed and the user approves it.
</HARD-GATE>

## Input

Read the design document at the path provided in `$ARGUMENTS`.

If the design covers multiple independent subsystems, suggest breaking it into separate plans — one per subsystem.

## Task Numbering Rule

Number tasks sequentially: **1, 2, 3, 4, 5, ...**

Do NOT use hierarchical numbering such as 1.1, 1.2, 2.1, 2.2. Every task is a top-level number.

## File Structure

Before defining tasks, map out which files will be created or modified:
- Each file should have one clear responsibility
- Prefer smaller, focused files over large ones
- In existing codebases, follow established patterns

**File Structure Overview:**
- Create: `path/to/new/file.js` - brief description
- Modify: `path/to/existing.js` - brief description

## Plan Format

Save to `docs/plans/YYYY-MM-DD-<feature-name>.md`:

````markdown
# [Feature Name] Implementation Plan

**Goal:** [One sentence]
**Architecture:** [2-3 sentences]
**Tech Stack:** [Key technologies]

---

### Task 1: [Component Name]

**Files:**
- Create: `exact/path/to/file.py`
- Modify: `exact/path/to/existing.py`
- Test: `tests/exact/path/to/test.py`

- [ ] Step 1: Write the failing test

```python
def test_specific_behavior():
    result = function(input)
    assert result == expected
```

- [ ] Step 2: Run test to verify it fails

Run: `pytest tests/path/test.py::test_name -v`
Expected: FAIL with "function not defined"

- [ ] Step 3: Write minimal implementation

```python
def function(input):
    return expected
```

- [ ] Step 4: Run test to verify it passes

Run: `pytest tests/path/test.py::test_name -v`
Expected: PASS

- [ ] Step 5: Commit

```bash
git add -A && git commit -m "feat: add specific feature"
```

### Task 2: [Next Component]
...
````

## Task Granularity

Each step is one action (2-5 minutes):
- "Write the failing test" — one step
- "Run it to verify it fails" — one step
- "Write minimal implementation" — one step
- "Run tests to verify they pass" — one step
- "Commit" — one step

Every task follows the TDD red-green cycle: start with a failing test, then write the minimal code to make it pass.

## Plan Requirements

- Exact file paths in every task
- Complete code in the plan — never "add validation here"
- Exact commands with expected output
- DRY, YAGNI, frequent commits

## Common Pitfalls (Optional)

For complex tasks, add a pitfalls section after **Purpose**:

```markdown
**Common Pitfalls:**
- Don't forget to import `defaultSettings` from `src/constants.js`
- Mock `confirm()` in tests - it blocks execution
- Remember to await async functions in tests
```

## User Review

After writing the plan, ask the user to review:

> "Plan written to `<path>`. Please review and let me know if you want changes."

Revise as needed until the user approves.

## Commit

When the user approves, commit:
1. The plan file
2. The design document — if it was not already committed

**Stop after committing.** Do not write implementation code. The user will invoke `/executing-plans` manually after running `/clear`.
