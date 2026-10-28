---
name: retro
description: Retrospective on a coding session, aimed at improving the agent's environment rather than the code.
disable-model-invocation: true
---

The user has asked for a **retrospective**. You are suggesting improvements to the coding agent's **environment** to improve future runs.

Invocation: `/skill:retro [the session to review]`. With no argument, the session under review is the current one. Invoking it authorises reading the session's primary sources and presenting candidates; it does not authorise changing any file yet.

## [YOU] Phase 1: Load the writing standard

Read `skill://writing-for-agents` for the writing style guide. Every suggestion you make in Phase 4 has to read as the kind of document that skill describes, so its levers govern the wording of the candidates, not just the text you write afterwards.

**Done**: you know the standard well enough that a candidate you phrase would survive its pruning tests — a single source of truth, no no-ops, pointers rather than prose.

## [YOU] Phase 2: Read the primary sources

Read the primary sources for the session the user specifies. This may mean searching through session logs on this machine. If the user doesn't specify a session, default to the current one.

Read the actual record, not your memory of it: the session transcript, and within it the tool calls, the failures, and the places the work stalled. A candidate you cannot point at in the sources is a guess.

**Done**: you have read the session's record end to end, and can name the concrete moments your candidates will cite.

## [YOU] Phase 3: Collect candidates

Look for candidates for improvement in these categories. Each carries its own _Use when_ trigger — that trigger is how you decide a category is in play, so check every category against the session rather than only the ones that come to mind first.

- **Navigation**: how easy was it for the agent to find the right files? Are there hidden dependencies between files? Would a **navigation pointer** make it easier? _Use when_ the session took a long time to find a piece of information.
- **Automated checks**: are there automated checks that could catch errors the agent made? Linting, typing, tests, filesystem linters? Read the repo's own check command first (its `package.json`/build-tool `lint`/`check` scripts, its CI workflow), so a check that already exists but sits unwired or silently broken is the finding, not a reinvention. A repo with no **guardrail** (no pre-commit hook and no CI job running its lint/typecheck/test command) is itself a finding: an un-linted repo is a standing missed opportunity, not a neutral default. _Use when_ the agent made a mistake an automated check could have caught, or the repo has no guardrail at all.
- **Coding standards**: should the **reviewer agent** be given a new rule to enforce? Should an existing rule be removed or clarified? Classify the violation first: a **mechanical** one (a fixed syntactic pattern, a banned API, an import shape, a file-location rule) gets a deterministic check, full stop: a custom rule in the repo's own linter, a new pre-commit hook, or a new CI job, whichever the repo's language and existing guardrail make cheapest. Default to building the check over writing the rule. Reserve `CODING_STANDARDS.md` for genuine **judgement calls** (cross-file consistency, "matches the surrounding style," anything no guardrail could ever substitute for). _Use when_ the reviewer agent failed to catch a mistake.
- **Global AGENTS.md**: are there any steering instructions that should be moved to coding standards (or automated checks) instead? _Use when_ the AGENTS.md file is particularly large — in the repo OR the user's global scope.
- **Tool economy**: did the agent make expensive tool calls that could be streamlined? Is there any custom tooling (CLI's, MCP's) that is particularly token-inefficient? _Use when_ the agent made an expensive tool call.
- **No-ops**: look for instructions in steering files that don't modify the agent's behavior. _Use when_ the steering files are large and unwieldy.
- **Information access**: look for opportunities to increase the agent's access to information. Teeing dev server logs, readonly access to third-party services. _Use when_ a crucial piece of information was not available to the agent.

**Done**: every category above has been checked against the session, and each candidate you keep cites the moment in the sources that triggered it.

## [YOU] Phase 4: Present the candidates

Present these candidates to the user, in order of severity.

Each candidate names its category and the _Use when_ trigger it fired on, then states the change in the fewest words that carry it — in the environment's own terms, so a navigation pointer names its file and a mechanical violation names its check.

**Done**: the candidates are presented in severity order, each naming its category and its _Use when_ trigger.

## Reference

### Implementation vs Review

Remember that all work goes through two stages: implementation and review. The implementation agent has the most **context pressure**. They are responsible for exploration, writing code, and debugging failures.

The review agent has the least context pressure — it receives a diff, so no exploration needed. It often does not need to write code or debug.

This means that the review agent should be responsible for imposing coding standards, not the implementation agent.

### Files

You have access to several files in the repo:

- `CLAUDE.md`/`AGENTS.md`: these files are pushed to the context window of any agent working in this repo. They should be used incredibly sparingly, usually only for **navigation pointers** to other files.
- `CODING_STANDARDS.md`: this file is read during review, not implementation. Add **navigation pointers** to docs folders if the standards file gets more than 1,000 lines long.
- Docs: use docs as reference files, pointed to by other files. Look for existing docs before writing new ones.
- Skills: use skills for docs (since their description goes into the agent's context window), or for user-invoked commands. Follow the advice in `skill://writing-for-agents`.
