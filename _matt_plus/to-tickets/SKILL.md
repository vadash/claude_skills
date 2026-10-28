---
name: to-tickets
description: Break a plan, spec, or the current conversation into tracer-bullet tickets, each declaring its blocking edges, and publish them to the configured tracker.
disable-model-invocation: true
---

You [YOU] are the orchestrator: this thread, the one the user is typing into. You break a plan, spec, or conversation into **tickets**: tracer-bullet vertical slices, each declaring the tickets that **block** it.

Invocation: `/skill:to-tickets` with no argument, or one reference — a spec path, an issue number, an issue URL. The reference names the source to break down. Invoking it authorises publishing the approved tickets to the configured tracker.

The issue tracker and triage label vocabulary should have been provided to you. If not, tell the user to run `/setup-matt-pocock-skills`.

## [YOU] Phase 1: Gather context

Work from whatever is already in the conversation. If the user passed a reference, fetch it and read its full body and comments.

**Done**: the source — spec, plan, issue, or transcript — has been read whole, including comments.

## [YOU] Phase 2: Explore and prefactor

If you have not already explored the codebase, do so to understand the current state of the code. Ticket titles and descriptions use the project's domain glossary vocabulary, and respect ADRs in the area you touch.

Look for opportunities to prefactor the code to make the implementation easier: make the change easy, then make the easy change. Any prefactoring is done first, as its own ticket.

**Done**: the prefactor opportunities are listed as tickets ahead of the feature work, or recorded as checked-and-none.

## [YOU] Phase 3: Draft vertical slices

Break the work into **tracer bullet** tickets:

- Each slice cuts a narrow but COMPLETE path through every layer (schema, API, UI, tests): vertical, NOT a horizontal slice of one layer.
- A completed slice is demoable or verifiable on its own.
- Each slice is sized to fit in a single fresh context window.
- Any prefactoring comes first.

Give each ticket its **blocking edges**: the other tickets that must complete before it can start. A ticket with no blockers can start immediately.

**Wide refactors are the exception to vertical slicing.** A **wide refactor** is one mechanical change (rename a column, retype a shared symbol) whose **blast radius** fans across the whole codebase, so a single edit breaks thousands of call sites at once and no vertical slice can land green. Do not force it into a tracer bullet; sequence it as **expand–contract**. First expand: add the new form beside the old so nothing breaks. Then migrate the call sites over in batches sized by blast radius (per package, per directory), each batch its own ticket blocked by the expand, keeping CI green batch to batch because the old form still exists. Finally contract: delete the old form once no caller remains, in a ticket blocked by every migrate batch. When even the batches cannot stay green alone, keep the sequence but let them share an integration branch that all block a final integrate-and-verify ticket; green is promised only there.

**Done**: every ticket names the end-to-end behaviour it delivers and the tickets that gate it.

## [YOU] Phase 4: Quiz the user

Present the breakdown as a numbered list. For each ticket show **Title**, **Blocked by**, and **What it delivers**.

Ask:

- Does the granularity feel right (too coarse / too fine)?
- Are the blocking edges correct — does each ticket only depend on tickets that genuinely gate it?
- Should any tickets be merged or split further?

Iterate until the user approves.

**Done**: the user has approved the breakdown.

## [YOU] Phase 5: Publish

Publish the approved tickets. The tickets are the same either way; only the shape of the blocking edges changes with the tracker `/setup-matt-pocock-skills` configured:

- **Local files** → one file per ticket under `.scratch/<feature-slug>/issues/<NN>-<slug>.md`, numbered from `01` in dependency order (blockers first). Each file's "Blocked by" lists the numbers/titles it depends on, as text. One ticket per file, never a single combined file.
- **A real issue tracker (GitHub, Linear, …)** → one issue per ticket, in dependency order (blockers first) so each blocking edge can reference a real identifier. Use the platform's native blocking / sub-issue link where it has one; otherwise set "Blocked by" to the blocking issues. Apply the `ready-for-agent` triage label unless instructed otherwise: the tickets are agent-grabbable by construction.

The tracker workflow lives in `docs/agents/issue-tracker.md`. Work the **frontier**: any ticket whose blockers are all done. For a purely linear chain that means top to bottom. Do not close or modify any parent issue.

In either form, avoid specific file paths or code snippets: they go stale fast. Exception: if a prototype produced a snippet that encodes a decision more precisely than prose can (state machine, reducer, schema, type shape), inline it and note briefly that it came from a prototype. Trim to the decision-rich parts, not a working demo, just the important bits.

<local-ticket-template>
# <NN>: <Ticket title>

**What to build:** the end-to-end behaviour this ticket makes work, from the user's perspective, not a layer-by-layer implementation list.

**Blocked by:** the numbers/titles of the tickets that gate this one, or "None (can start immediately)".

**Status:** ready-for-agent

- [ ] Acceptance criterion 1
- [ ] Acceptance criterion 2
</local-ticket-template>

<issue-template>
## Parent

A reference to the parent issue on the tracker (if the source was an existing issue, otherwise omit this section).

## What to build

The end-to-end behaviour this ticket makes work, from the user's perspective, not layer-by-layer implementation.

## Acceptance criteria

- [ ] Criterion 1
- [ ] Criterion 2

## Blocked by

- A reference to each blocking ticket, or "None (can start immediately)".
</issue-template>

**Done**: every ticket exists on the tracker with its blocking edges resolvable, and the first frontier ticket is grabbable.
