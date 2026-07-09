---
name: agents-md-sync
description: Sync session learnings into the repo root AGENTS.md and agent_docs/ files at the very end of a coding session - add new gotchas, remove obsolete lines, and keep the docs lean. Use this skill ONLY at the moment a commit is about to happen (after all implementation work for the session is finished), or when the user explicitly asks to wrap up the session. Timing matters: this skill runs in the same breath as `git commit`, never earlier. If the user mentions this skill by name inside a longer multi-step instruction (e.g., "implement X, agents-md-sync, then commit"), treat the mention as a scheduling instruction, NOT as a trigger - finish the implementation work first, then invoke this skill only when you are about to run the commit. Do NOT trigger just because the user said "commit", "agents-md-sync", "update docs", or named this skill mid-task; those words in isolation are not the signal. The signal is: implementation is done AND a commit/finish is imminent. Trigger examples: "ready to commit, do the agents-md sync first", "wrap up the session", "before we commit, anything to update?", "session done, sync docs".
---

# AGENTS.md Sync

You are at the end of a coding session, about to commit or wrap up. Your job is to decide what the agent (you, in future sessions) genuinely needs to know that isn't already in the code, the linter, or git - and to persist *only that* into the repo `AGENTS.md` and `agent_docs/` files.

## Why this matters

The `AGENTS.md` ecosystem goes into **every single future session**. It the highest-leverage context in the repo. Research on frontier LLMs shows instruction-following decays uniformly as instruction count grows. So every line you add must earn its place, and every stale line you leave actively harms future work. Claude is not a linter, so never include syntax, line-length, or styling rules. 

A gotcha you discovered this session (a hidden invariant, a workaround for a specific bug, a non-obvious dependency rule) is *priceless* if it saves the next session from rediscovering it the hard way. This skill exists to capture that kind of learning - and to delete the cruft that has accumulated.

## Timing: defer if the session isn't actually ending

This skill edits docs based on what was learned across the whole session. If you run it before the implementation work is finished, you'll capture half a session learnings and may also disrupt the user flow. So:

- **If you were named inside a longer task** - e.g. the user said "implement X, then agents-md-sync, then commit" - do not run this skill yet. Complete the implementation work first.
- **If the user has merely said the word "commit" or "docs" mid-task** without indicating the session is ending, that not a trigger. Keep working.
- **The right moment** is: implementation is complete AND you are within one step of running `git commit` or ending the session.

When you do run, do it as a discrete step *before* staging the commit, so the edits can be included in that same commit if appropriate.

## The filter: should this be persisted?

Run every candidate learning through these gates. **All** must be true to add it.

1. **Universal** - applies to most future work in this domain, not just the task you just finished. A one-off fix or a decision specific to today feature does not belong.
2. **Non-obvious** - a competent reader couldn't infer it from reading the surrounding code, types, or test names. If the code already says it, the doc shouldn't.
3. **Not owned by another tool** - code style belongs to the linter, formatting to Prettier, test commands to `package.json`, file existence to git. Don't duplicate what those already enforce.
4. **Stable** - describes something that won't be obsolete next week. If it in flux, leave it out.

When in doubt, leave it out. A short context file is a strong context file.

## Where does it go? (Progressive Disclosure)

We use **Progressive Disclosure**: a root `AGENTS.md` acts as a router (WHAT, WHY, HOW), and specific technical domains live in `agent_docs/*.md`.

### Step 1 - Topical locality (check this first)
Before deciding where to put a new rule, read the existing files in `agent_docs/`. Find the file that covers the entity, function, or architectural concept your learning relates to. Add your line **there**, as a sibling to the existing mention.

Beware the "caller-side" trap: when you discovered the learning while working in module X, it tempting to think it belongs there. But if the rule is about how module Y behaves, record it next to Y existing context.

### Step 2 - Scope table

| If the learning is about… | Put it in… |
|---|---|
| The whole project (purpose, stack, top-level scripts) | Root `AGENTS.md` |
| An existing specific domain / workflow | The most relevant `agent_docs/*.md` file |
| A specific file or function | The closest `agent_docs/*.md` that covers it, using a `file:line` pointer |
| A completely new architectural domain | **Create a new file** in `agent_docs/` |

### Step 3 - Creating new files (When Required)
If you are introducing a completely new major workflow, integration, or architectural pattern that would bloat an existing file, **you may create a new `.md` file in `agent_docs/`**. 
*Rule*: If you create a new file in `agent_docs/`, you **MUST** update the root `AGENTS.md` file to include a link and description of the new file under the Progressive Disclosure section. Ensure the file has a self-descriptive name.

## Add or update? Don't append blindly

Before adding a line, scan the existing document for:
- **Duplicates** - same rule in different words. Merge into the clearer phrasing.
- **Contradictions** - old rule that the new one overrides. Replace, don't append both.
- **Supersets** - new rule is a special case of an existing one. Narrow the existing line.

Appending is the failure mode. Every duplicate line is one more instruction competing for attention.

## Pruning obsolete content (do this every time)

This is half the job. Active deletion is what keeps the files lean. Look for:
- References to files, directories, or commands that no longer exist.
- Rules about code that was refactored or removed this session.
- Hotfix-style instructions added to work around a bug that now fixed.
- Style guidance that duplicates what the linter or formatter already enforces.
- Stale TODOs, dead links, "see also" pointers to nowhere.

## How to apply

1. **Discover & Read**: Read the root `AGENTS.md` and *all* files within the `agent_docs/` directory. They contain the current architectural constraints.
2. **Harvest** candidate learnings from the session: bugs you hit, invariants discovered, or unwritten conventions.
3. **Filter** each candidate through the four gates above. Expect to reject most.
4. **Place** each survivor in the most relevant `agent_docs/*.md` file. Create a new one *only* if a massive new domain was introduced.
5. **Prune** for obsolete content in every file you touch.
6. **Apply the edits directly** using the Edit tool - don't stage them as a plan.
7. **Show a summary at the end**:
   - What was added (with rationale and file target).
   - What was removed (with rationale - deletions are valuable!).
   - What you considered and rejected (so the user can catch false negatives).
   - If you created a new `agent_docs/` file, confirm it was linked in `AGENTS.md`. 

The summary is the user audit trail. Keep it tight - bullet points, not prose.
