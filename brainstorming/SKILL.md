---
name: brainstorming
description: Explore user intent, requirements, and design before implementation. Use for features, components, or behavioral changes.
disable-model-invocation: true
argument-hint: [@context or description]
---

# Brainstorming

Collaborative design through dialogue. Understand the idea, explore approaches, present a design, write a design document.

<HARD-GATE>
Do NOT write code, scaffold projects, or invoke any implementation skill. Your ONLY output is a design document. Stop after the document is written and the user approves it.
</HARD-GATE>

## Process

```
- [ ] 1. Explore project context
- [ ] 2. Ask clarifying questions (one at a time)
- [ ] 3. Propose 2-3 approaches with trade-offs
- [ ] 4. Present design, get user approval
- [ ] 5. Write design doc to docs/designs/
- [ ] 6. User reviews written doc — stop when approved
```

### 1. Explore Project Context

Review files, docs, and recent commits to understand the current state. If the user provided context via `$ARGUMENTS`, review it first.

If deep codebase exploration is needed, use the Agent tool with the Explore agent type and specify model Haiku 4.5 (`claude-haiku-4-5-20251001`). Do not use any other sub-agents or worktrees.

### 2. Ask Clarifying Questions

- One question per message
- Prefer multiple choice when possible
- Focus on: purpose, constraints, success criteria
- If the request spans multiple independent subsystems, flag it immediately and help decompose into sub-projects first. Each sub-project gets its own design → plan → implementation cycle.

### 3. Propose Approaches

- Present 2-3 approaches with trade-offs
- Lead with your recommendation and reasoning
- Apply YAGNI ruthlessly — cut features that aren't needed

### 4. Present Design

- Scale each section to its complexity — a few sentences if straightforward, more if nuanced
- Cover: architecture, components, data flow, error handling, testing strategy
- Ask after each section if it looks right
- Revise until the user is satisfied

**Design principles:**
- Break the system into units with one clear purpose and well-defined interfaces
- For each unit: what does it do, how do you use it, what does it depend on?
- Prefer smaller, focused units — they are easier to reason about, test, and modify
- In existing codebases, follow established patterns. Include targeted improvements only where they serve the current goal.

### 5. Write Design Document

Save to `docs/designs/YYYY-MM-DD-<topic>.md` and commit.

### 6. User Review

Ask the user to review the written document:

> "Design written and committed to `<path>`. Please review and let me know if you want changes."

If the user posts a review:
- Read the feedback carefully
- If the feedback is sound, implement the requested changes and re-commit
- If something seems technically questionable, discuss before changing

**Stop when the user approves the document.** The user will invoke `/writing-plans` manually when ready.
