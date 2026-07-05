---
name: writing-plans
description: Convert a design document into a sequential TDD implementation plan.
disable-model-invocation: true
argument-hint: [design-doc-path]
---

# Writing Plans

Convert a design document into a sequential implementation plan using the TDD red-green methodology. 

Your goal as the Planner is to map the design to specific file paths and outline the tasks, **without writing the actual implementation code**.

## Test Convention
Use native `Glob` to find, and `Read` to consume, the test directory's `CLAUDE.md` (e.g., `test/CLAUDE.md` or `tests/CLAUDE.md`). This ensures the downstream execution agents follow the right testing patterns.

## Execution Model Context
The generated plan will be executed chunk-by-chunk by separate, **zero-context execution agents**. 
A script will feed the agent: `[Plan Header] + [Task X]`. 
Therefore, every Task must contain the exact file paths and specific instructions on *what* to build, so the execution agent doesn't have to guess.

## The Workflow
Copy this checklist into your internal scratchpad to track your progress:
- [ ] 1. **Read Inputs:** Read the design document provided in `$ARGUMENTS`.
- [ ] 2. **Read Test Rules:** Glob for and Read the testing `CLAUDE.md` to understand testing conventions.
- [ ] 3. **Efficient Mapping:** Use `jCodemunch` outline/symbol tools to map design concepts to exact file paths.
- [ ] 4. **Draft Plan:** Break the work into sequential Tasks (Task 1, Task 2...) using the format below.
- [ ] 5. **Review & Commit:** Ask the user for review, then commit the plan.

## Output Format Template

Save to `docs/plans/YYYY-MM-DD-<feature-name>.md`:

```markdown
# [Feature Name] Implementation Plan

**Goal:** [One sentence summarizing the design doc]
**Testing Conventions:** [1-2 sentences summarizing rules found in the test CLAUDE.md]

---

### Task 1: [Component / Feature Name]

**Objective:** [1-2 sentences explaining what this task achieves]

**Files to modify/create:**
- Create: `src/exact/path/to/new_file.ts` (Purpose: [Brief description])
- Modify: `src/exact/path/to/existing.ts` (Purpose: [Brief description])
- Test: `src/exact/path/to/new_file.test.ts` 

**Instructions for Execution Agent:**
1. **Context Setup:** Read the outlines of the files listed above to orient yourself.
2. **Write Failing Test:** In the test file, write tests that verify `[Specific behavior/edge cases expected]`. Run the test to ensure it fails.
3. **Implement Minimal Code:** Modify the target files to satisfy the tests. Focus on `[specific function/class names identified during planning]`.
4. **Verify:** Run the tests and ensure they pass.
5. **Commit:** Commit with message: `feat: [descriptive message]`

---

### Task 2: [Next Component]
[Repeat the structure above...]
```

## Task Design Rules
1. **Numbering:** Use flat, sequential numbering: **Task 1, Task 2, Task 3...** No hierarchical numbers.
2. **No Code in Plan:** Do NOT write actual code (not even test code) in the plan document. Provide exact file paths, target symbol names, and describe the *logic* to the execution agent.
3. **Independence:** Tasks should be logically separate. If Task 2 depends on Task 1, state that clearly in the Objective.

## User Review & Commit
After generating the markdown file, ask:
> "Plan written to `<path>`. I have mapped the exact file paths using efficient outline exploration. Please review and let me know if you want changes."

Once the user approves, commit the plan and the design document. **Stop after committing.** Do not execute the plan.
