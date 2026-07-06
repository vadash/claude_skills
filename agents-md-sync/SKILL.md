---
name: agents-md-sync
description: Sync session learnings into the repo's AGENTS.md files at the very end of a coding session — add new gotchas, remove obsolete lines, and keep the docs lean. Use this skill ONLY at the moment a commit is about to happen (after all implementation work for the session is finished), or when the user explicitly asks to wrap up the session. Timing matters: this skill runs in the same breath as `git commit`, never earlier. If the user mentions this skill by name inside a longer multi-step instruction (e.g., "implement X, agents-md-sync, then commit"), treat the mention as a scheduling instruction, NOT as a trigger — finish the implementation work first, then invoke this skill only when you are about to run the commit. Do NOT trigger just because the user said "commit", "agents-md-sync", "update docs", or named this skill mid-task; those words in isolation are not the signal. The signal is: implementation is done AND a commit/finish is imminent. Trigger examples: "ready to commit, do the agents-md sync first", "wrap up the session", "before we commit, anything to update?", "session done, sync docs".
---

# AGENTS.md Sync

You are at the end of a coding session, about to commit or wrap up. Your job is to decide what the agent (you, in future sessions) genuinely needs to know that isn't already in the code, the linter, or git — and to persist *only that* into the repo's `AGENTS.md` files.

## Why this matters

`AGENTS.md` goes into **every single future session**. It's the highest-leverage file in the repo: a bad line there doesn't break one feature, it subtly degrades every future task. Research on frontier LLMs shows instruction-following decays uniformly as instruction count grows — frontier thinking models reliably follow ~150-200 instructions total, and Claude Code's system prompt already consumes ~50 of those. So every line you add must earn its place, and every stale line you leave actively harms future work.

The reverse is also true: a gotcha you discovered this session (a hidden invariant, a workaround for a specific bug, a non-obvious dependency rule) is *priceless* if it saves the next session from rediscovering it the hard way. This skill exists to capture that kind of learning — and to delete the cruft that has accumulated.

## Timing: defer if the session isn't actually ending

This skill edits `AGENTS.md` based on what was learned across the whole session. If you run it before the implementation work is finished, you'll capture half a session's learnings and may also disrupt the user's flow. So:

- **If you were named inside a longer task** — e.g. the user said "implement X, then agents-md-sync, then commit" — do not run this skill yet. Complete the implementation work first. Come back and invoke this skill only when you are about to run `git commit` (or the user has explicitly said the session is ending).
- **If the user has merely said the word "commit" or "docs" mid-task** without indicating the session is ending, that's not a trigger. Keep working.
- **The right moment** is: implementation is complete AND you are within one step of running `git commit` or ending the session.

When you do run, do it as a discrete step *before* staging the commit, so the AGENTS.md edits can be included in that same commit if appropriate.

## The filter: should this be persisted?

Run every candidate learning through these gates. **All** must be true to add it.

1. **Universal** — applies to most future work in this file/dir, not just the task you just finished. A one-off fix or a decision specific to today's feature does not belong.
2. **Non-obvious** — a competent reader couldn't infer it from reading the surrounding code, types, or test names. If the code already says it, the doc shouldn't.
3. **Not owned by another tool** — code style belongs to the linter, formatting to Prettier, test commands to `package.json`, file existence to git. Don't duplicate what those already enforce.
4. **Stable** — describes something that won't be obsolete next week. If it's in flux, leave it out.

### Examples

- ✅ "`src/foundation/context.js` is the only module allowed to touch the `SillyTavern` global." — universal, non-obvious, enforced by neither linters nor types.
- ✅ "SSE stream readers MUST reach `data: [DONE]` before any text is accepted." — a hidden invariant you'd only learn from a bug.
- ❌ "We added a `profitMargin` column to the Q4 sales view." — task-specific, not universal.
- ❌ "Use camelCase for variables." — the linter already enforces this.
- ❌ "TODO: refactor the auth module." — belongs in a ticket or code comment, not AGENTS.md.

When in doubt, leave it out. A short AGENTS.md is a strong AGENTS.md.

## Where does it go?

Most repos use progressive disclosure: a root `AGENTS.md` plus one per subdirectory/module. The goal is **discoverability**: a future reader (you, in a later session) looking for context on a topic should find all the relevant rules in one place, not scattered.

### Step 1 — Topical locality (check this first)

Before consulting the scope table below, grep every existing `AGENTS.md` for the entity, file, function, or concept your learning relates to (the module a function lives in, the queue it's about, the API it concerns, etc.). If a topic already has a home — even if that home is in a different directory from where you were working — add your line **there**, as a sibling to the existing mention.

Why this beats "pick by directory": a future reader who hits `SummarizerQueue` in the code will pull up `src/core/AGENTS.md` (where the queue is already documented). If your new rule about that queue lives in `src/features/AGENTS.md` because that's where the *caller* was, it's invisible to them exactly when they need it most. Topical locality keeps related rules together; directory is a tiebreaker, not the primary signal.

Beware the "caller-side" trap: when you discovered the learning while working in module X, it's tempting to record it in module X's file ("this is what I was doing"). But the rule is usually about module Y (the thing that bit you). Record it next to Y's existing context.

### Step 2 — Scope table (only if Step 1 finds no existing mention)

| If the learning is about… | Put it in… |
|---|---|
| The whole project (purpose, stack, top-level navigation, scripts) | Root `AGENTS.md` |
| One layer / module / directory and its rules | That subdirectory's `AGENTS.md` |
| A specific file or function | The closest AGENTS.md that covers it, ideally with a `file:line` pointer |

Prefer the **most specific** file that still applies. If a rule spans two files, put it in the more specific one and let navigation handle discovery — don't duplicate.

If no existing AGENTS.md fits cleanly, that's a signal: either the learning is too narrow (skip it) or there's a missing subdirectory file (mention this to the user, don't silently create one).

## Add or update? Don't append blindly

Before adding a line, scan the existing AGENTS.md you're targeting for:

- **Duplicates** — same rule in different words. Merge into the clearer phrasing.
- **Contradictions** — old rule that the new one overrides. Replace, don't append both.
- **Supersets** — new rule is a special case of an existing one. Narrow the existing line.

Appending is the failure mode. Every duplicate line is one more instruction competing for attention.

## Pruning obsolete content (do this every time)

This is half the job. Active deletion is what keeps the files lean.

Look for:

- References to files, directories, or commands that no longer exist (verify with Glob/Grep before deleting — don't assume).
- Rules about code that was refactored or removed this session.
- Hotfix-style instructions ("always do X before Y") added to work around a bug that's now fixed.
- Style guidance that duplicates what the linter or formatter already enforces.
- Stale TODOs, dead links, "see also" pointers to nowhere.
- Anything that reads like a note to self rather than a stable rule.

When you delete, the goal is to leave the file shorter and more focused than you found it.

## How to apply

1. **Discover** the AGENTS.md files in the repo with Glob (`**/AGENTS.md`). They're normally already in your context from this session's work — don't re-read ones you've already seen. Read only files you're about to edit and haven't seen yet.

2. **Harvest** candidate learnings from the session: bugs you hit and how you reasoned about them, invariants you discovered, conventions the codebase follows that aren't documented anywhere, surprises in the dependency graph, things you tried that didn't work and why.

3. **Filter** each candidate through the four gates above. Expect to reject most.

4. **Place** each survivor — first grep every existing `AGENTS.md` for the topic/entity (topical locality, see above); only fall back to the scope table if no existing mention turns up.

5. **Prune** for obsolete content in every file you touch.

6. **Apply the edits directly** using the Edit tool — don't stage them as a plan. The user wants the result, then a summary.

7. **Show a summary at the end**:
   - What was added, with a one-line rationale and which file.
   - What was removed, with a one-line rationale (deletions are valuable — surface them).
   - What you considered and rejected, briefly, so the user can catch false negatives.
   - If you almost created a new AGENTS.md but didn't, say so.

The summary is the user's audit trail. Keep it tight — bullet points, not prose.

## Anti-patterns

- **Stuffing the file to be "thorough".** The goal is the smallest file that still captures what matters.
- **Recording the session's task list.** That belongs in a commit message or PR description, not in docs that load into every future session.
- **Adding "helpful" context that the agent could read from code.** Pointers (`file:line`) beat copies.
- **Creating a new AGENTS.md "just in case".** Only when there's a real gap the user should know about.
- **Reformatting or rewriting lines you didn't need to touch.** Stay surgical; unrelated cleanup is noise in the diff.
