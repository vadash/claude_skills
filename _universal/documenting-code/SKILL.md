---
name: documenting-code
description: Standardizes code comments and docstrings, focusing on intent, business rules, and constraints while removing redundant syntax noise. Use when writing docstrings, refactoring comments, adding inline explanations, or reviewing code documentation.
---

# Writing code comments

Run this before adding or editing any comment. The default is no comment. Good code with clear names carries most of its meaning on its own; a comment earns its place only when it tells a reader something the code cannot.

## The gate: one question

Before writing a comment, answer:

> **What does this tell a future reader that the code itself doesn't?**

If the answer is "it restates what the code does", delete it. Rename the variable or extract a function instead.

A comment worth keeping answers a _why_ the code can't:

- ✅ `# ATOMIC_REQUESTS is off, so wrap the two writes that must commit together`
- ✅ `// Stripe sends the amount in cents; the rest of our system uses dollars`
- ✅ `# Kept in sync with the enum in migrations/0042; update both`

## The comment carries the rule, not a pointer

Every token in a comment is paid again on every future read of the file. A pointer earns its place only when the reader will act on it: open the issue, follow the ADR. Otherwise the restated rule is the whole value and the pointer is pure cost.

So: restate the rule in the comment and drop the pointer. Do not keep a citation as a "bonus" beside the restatement; that doubles the cost for zero added meaning.

- ✅ `# in source order per the provider contract; do not sort`
- ❌ `# in source order per the provider contract (docs/fuel-monitor-spec.md §5); do not sort` — the restatement already carries everything; the citation is paid forever
- ✅ `# the provider owns the browser (issue #13)` — short, resolvable, and the reader may need the issue's policy discussion

What you may reference, only when it adds something the comment can't:

- A GitHub issue number (`#13`). Short, resolvable, often holds the debate behind a decision.
- An exact ADR id (`ADR-007`). Lives in-repo, immutable, numbered.

What you never reference:

- **Spec sections.** Do not cite specs in comments. Restate the behavior instead; the reader needs the rule, not its address. Two exceptions: (1) the comment exists to prove compliance with a clause that cannot be paraphrased without loss, and someone will audit the code against the spec: then use the short spoken name (`fuel spec §8`) and still restate the rule, never a file path; (2) an acceptance-test title pinning a numbered clause of the spec, where the clause id (`§12 case 24`) is the audit key, not noise. Never a file path anywhere.
- **File paths.** A path in a comment is 3-4 tokens of dead weight and rots on the first rename. If the document is worth naming, name it the way a person says it ("fuel spec").
- **Bare section numbers** (`§8`, `§12 case 24`). Nobody knows which document they point to. When you meet one in existing code, do not repair it by naming the document; that just relabels the noise. Delete it, or replace it with the rule it stood for.

## Delete these

### Narration that restates the code

- ❌ `# increment the counter` above `counter += 1`
- ❌ `// loop over users` above `for user of users`
- ❌ `# return the result` above `return result`

If a block needs narration to be followed, the fix is smaller functions and better names, not a comment.

### Change history and chat context

Never record how the code got here. That belongs in the commit message and PR description, where it's attached to the diff and searchable. In the source it's noise that goes stale immediately.

- ❌ `# previously used a set here, switched to a list for ordering`
- ❌ `// per PR #1234` / `# as discussed` / `# changed because the old way broke`
- ❌ `# AI: generated this helper` / `// agent: refactored`
- ❌ `# TODO(2024-01): remove after migration` left in long after the migration
- ❌ `handling candidate 3` - wtf is candidate?

### Perishable measurements and current-state stamps

Measured timings, counts, and rates rot silently: nothing forces them to update, and a rotted number misleads the next person sizing a timeout or shard count. The same goes for "currently" / "today" hedges, because the sentence states the same fact without them. State the durable relationship the number stood for.

- ❌ `# skip the ~20 min build` when the durable fact is that the build is expensive
- ❌ `# ci-backend runs ~28m, so 60m ≈ one red result` instead of "sized past a full run of the slowest workflow"
- ❌ `# no story currently opts into webkit snapshots` where dropping "currently" states the same fact
- ❌ `# ~20 minutes in June, past 25 by July` because trend narration is change history

Numbers that stay:

- A dated snapshot: `# as of August 2024, Homebrew ships 4.13.2` (the date makes staleness visible)
- A restated adjacent code literal: `# runs that took >5 min (300 seconds)` beside the `300` (it updates with the code)
- A platform constant: `# GitHub's comment size limit (~64KB)`
- A target or budget: `# Target: ~15 min per shard` (policy, not measurement)
- Cited evidence: `# 30% peak memory observed on 16-core runs (#46853)` (the link dates it)

### Commented-out code

Delete it; the version history has it if it's needed again. Commented-out code is ambiguous to the next reader, who can't tell whether it's a note, a rollback plan, or an accident.

### Redundant docstrings and type restatements

- ❌ A docstring that repeats the function name in prose: `"""Gets the user by id."""` on `get_user_by_id`
- ❌ `# type: string` on an already-typed field
- ❌ Python test doc comments (the repo convention is none; the test name says it)

## Keep these

- A **why** that isn't obvious from the code: a workaround, a performance trade-off, a spec quirk, an ordering constraint.
- A **warning** about a consequence that lives elsewhere: "changing this breaks the cache key", "callers rely on this being sorted".
- A **pointer** the reader will act on: an issue number or an exact ADR id. Nothing else; if the context matters, state it in the comment.

## Style

Write comments the way you'd write technical documentation: explicit and precise. State the reasoning so the reader does not have to infer it. Length is not a target in either direction: don't clip a comment to look terse, and don't pad it to look thorough. Say what needs saying and stop.

- **Be explicit and technical.** State the cause and effect. Name the actual conditions, values, and consequences. A reader should not have to reconstruct your reasoning from a hint.
- **Use mostly ASD-STE100 Simplified Technical English.** Use active voice, simple tenses, one idea per sentence, and consistent terms.
- **Let length follow the content.** One line is fine when one line covers it; use more when the reasoning needs more. Neither brevity nor length is the goal.
- **No em-dash.** The tell to avoid is the clipped two-part phrase joined by a dash, like `# do the thing — it's faster`. Use a real connective instead ("because", "so that", "which means", "to avoid").
- **Explain why, not what.** The what is in the code; the why usually is not.
- **Preserve existing comments when moving or refactoring code**, unless the change makes them wrong. Don't drop an existing why just because you're relocating the function.
- **Match the surrounding density.** Don't add a comment to every line of a file that had none; don't strip a well-commented module bare.

The fix for the em-dash is the connective, not more words. A short comment is fine once the dash is gone:

- ❌ `# batch here — avoids N+1`
- ✅ `# batch here to avoid an N+1 against posthog_organizationmembership`

## When you're tempted to comment

Try, in order: (1) a better name, (2) a smaller function, (3) a type. Reach for a comment only when none of those can carry the meaning.
