---
name: agents-md-init
description: Bootstrap AGENTS.md and agent_docs/ from scratch using chaotic docs and codebase exploration. Manual-only.
disable-model-invocation: true
---

# AGENTS.md Init

You are creating the `AGENTS.md` memory system from scratch for a repo that has none. This is the genesis counterpart to `agents-md-sync`: sync maintains and prunes over time; **init lays the foundation once**. 

The user will often feed you chaotic, unstructured, or outdated documentation. Your job is to synthesize that chaos, verify it against the actual codebase, and output a lean, machine-readable Progressive Disclosure structure.

## Why this matters

Every line you write here will be read by future-you on every single task in this repo. A wrong asserted rule is worse than a missing one, because future-you will trust it. The job is not "produce a thorough-looking document." The job is to capture what verifiably true and stable, and to **surface as questions** the things you suspect but can't confirm from code alone.

## Triggering and Refusal

**First action on any invocation: check for a root `AGENTS.md`.** 
If it exists, stop immediately. Do not create a competing file, do not merge, do not overwrite. Tell the user: "An `AGENTS.md` already exists. Use the `agents-md-sync` skill to maintain it - init is only for repos that have none." Exit.

## Inputs: Chaotic Docs first, Code second

The user will likely provide initial project docs (a sprawling README, outdated design docs, pasted chat logs) - or nothing at all.

1. **Read the provided docs first.** They are the authoritative narrative for *intent*: what the project is, what it trying to do, and the vocabulary of the domain.
2. **Explore the codebase second** to verify what the docs claim and to capture what the docs omit (actual entry points, real script names, how tooling is *actually* configured today).
3. **When docs and code conflict**, trust the code for facts (it what actually running) but surface the conflict in your draft as a question - don't silently pick a side.
4. **If no docs at all**, form your understanding entirely from the codebase.

## What to capture (and what to flag)

Separate everything you encounter into two buckets:

### 1. Verified - safe to assert as fact
Things you can point to a file, command, or declaration for:
- **Stack and versions** - languages, frameworks, dependencies (e.g., from `package.json`).
- **Entry points** - where execution actually starts.
- **Scripts and commands** - build, test, lint, dev (from configurations, not just README promises).
- **Tooling conventions** - "Formatting via Prettier (see `.prettierrc`)" rather than copying the rules.
- **Navigation pointers** - where to look for X (e.g., `file:src/db/schema.ts`).

### 2. Inferred - surface as a question, never assert
Things that look like rules but you can't verify from a cold read:
- "We prefer X pattern over Y."
- "Module X owns concern Y." (plausible, but boundaries are often implicit).
- Anything that smells like a hidden invariant.
*Rule of thumb:* If you'd be embarrassed to have future-you trust the line and it turns out wrong, it inferred. Put it in the draft as an "**Open Question**".

## Placement: The Progressive Disclosure Architecture

Do NOT create nested `AGENTS.md` files. We use a centralized architecture.

1. **Root `AGENTS.md` (Always Created):**
   This is the router. It must contain WHAT the project is, WHY it exists, HOW to work on it (stack, scripts), and a **Progressive Disclosure** section that explicitly links to the files in `agent_docs/`. Keep it under 60 lines if possible.

2. **The `agent_docs/` Directory (Created based on complexity):**
   Group the chaotic documentation into distinct, bounded contextual files. 
   - *Example splits:* `agent_docs/architecture_and_state.md`, `agent_docs/testing_rules.md`, `agent_docs/deployment_and_ci.md`.
   - *Rule:* Only create a separate file if an outsider would hit a wall without it, and if it too detailed for the root file. Don't over-fragment. 2-4 files is usually plenty for a new repo.

## The Flow

1. **Refuse if exists.** Look for `AGENTS.md` in the root. If found → stop.
2. **Absorb Inputs.** Read any chaotic docs provided by the user.
3. **Explore the Codebase.** (If repo > 200 files, use a subagent with a focused brief to find entry points, configs, and layout).
4. **Bucket & Filter.** Ruthlessly separate Verified facts from Inferred guesses.
5. **Draft Inline (Do not write files yet).** Present your proposed structure to the user in your response:
   - Provide the exact markdown for the root `AGENTS.md`.
   - Provide the exact markdown for each planned `agent_docs/*.md` file.
   - Include an "**Open Questions**" section at the end collecting every inferred item/conflict.
6. **Wait for Approval.** The user gets to see what you are about to inject into every future session. They may edit, trim, or answer your open questions.
7. **Write.** ONLY after the user approves, create the `agent_docs/` folder and write the files to disk.

## Anti-patterns

- **Asserting inferred rules.** This is the cardinal sin. When uncertain, ask.
- **Stuffing the root file.** If the root file is getting huge, you are failing to use `agent_docs/` or you are copying rules that linters already enforce.
- **Over-fragmenting `agent_docs/`.** Don't create 10 different files with 3 lines each. Group related concepts.
- **Duplicating the README.** If the README covers setup perfectly, point at it. Don't transcribe it.
- **Skipping the approval gate.** Never write the files without showing the draft and asking for the green light first.
