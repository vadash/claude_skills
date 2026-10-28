---
name: to-spec
description: Turn the current conversation into a spec and publish it to the project issue tracker — no interview, just synthesis of what you already discussed.
disable-model-invocation: true
---

You [YOU] are the orchestrator: this thread, the one the user is typing into. You take the current conversation and your understanding of the codebase and produce a spec.

Do not interview the user. Synthesise what you already know.

Invocation: `/skill:to-spec` with no arguments, or a reference to the discussion to capture. Invoking it authorises writing and publishing the spec to the configured tracker.

The issue tracker and triage label vocabulary should have been provided to you. If not, tell the user to run `/skill:setup-matt-pocock-skills`.

**Running after a skill-state procedure.** If a `skill-state` procedure was engaged when you were invoked, the runtime disengaged it before your first step (notice: `handed off to ordinary skill "to-spec"`): the transcript — the discussion you are synthesizing — is visible again. Synthesize from the conversation plus repo exploration. Do not re-plan anything and do not ask the user to repeat what the transcript already holds. If there is no discussion to synthesize (a fresh session), say so and stop.

## [YOU] Phase 1: Explore

Explore the repo to understand the current state of the codebase, if you have not already. Use the project's domain glossary vocabulary throughout the spec, and respect any ADRs in the area you touch.

**Done**: every module the spec will touch has been located, and the domain terms for it are taken from the project, not invented.

## [YOU] Phase 2: Sketch the seams

Sketch the seams at which you will test the feature. Prefer existing seams to new ones, and use the highest seam possible. If a new seam is needed, propose it at the highest point you can. The fewer seams across the codebase the better — the ideal number is one.

Check with the user that these seams match their expectations before writing.

**Done**: the user has agreed the seam list.

## [YOU] Phase 3: Write and publish

Write the spec with the template below, then publish it to the project issue tracker, following the workflow in `docs/agents/issue-tracker.md`. Apply the `ready-for-agent` triage label — no need for additional triage.

<spec-template>

## Problem Statement

The problem that the user is facing, from the user's perspective.

## Solution

The solution to the problem, from the user's perspective.

## User Stories

A LONG, numbered list of user stories. Each user story should be in the format of:

1. As an <actor>, I want a <feature>, so that <benefit>

<user-story-example>
1. As a mobile bank customer, I want to see balance on my accounts, so that I can make better informed decisions about my spending
</user-story-example>

This list of user stories should be extremely extensive and cover all aspects of the feature.

## Implementation Decisions

A list of implementation decisions that were made. This can include:

- The modules that will be built/modified
- The interfaces of those modules that will be modified
- Technical clarifications from the developer
- Architectural decisions
- Schema changes
- API contracts
- Specific interactions

Do NOT include specific file paths or code snippets. They may end up being outdated very quickly.

Exception: if a prototype produced a snippet that encodes a decision more precisely than prose can (state machine, reducer, schema, type shape), inline it within the relevant decision and note briefly that it came from a prototype. Trim to the decision-rich parts, not a working demo, just the important bits.

## Testing Decisions

A list of testing decisions that were made. Include:

- A description of what makes a good test (only test external behavior, not implementation details)
- Which modules will be tested
- Prior art for the tests (i.e. similar types of tests in the codebase)

## Out of Scope

A description of the things that are out of scope for this spec.

## Further Notes

Any further notes about the feature.

</spec-template>

**Done**: the spec is published, carries the `ready-for-agent` label, and every section of the template holds content drawn from the transcript rather than a fresh interview.
