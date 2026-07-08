---
name: agents-md-init
description: Bootstrap AGENTS.MD. Manual-only
disable-model-invocation: true
---

# AGENTS.md Init

You are creating `AGENTS.md` from scratch for a repo that has none. This is the genesis counterpart to `agents-md-sync`: sync maintains and prunes over time; **init lays the foundation once**. After init runs, every future session loads these files — so the bar for what earns a line is just as high as in sync, just applied at moment zero instead of incrementally.

## Why this matters

Every line you write here will be read by future-you on every single task in this repo. A wrong asserted rule is worse than a missing one, because future-you will trust it. So the job is not "produce a thorough-looking document." The job is to capture what's verifiably true and stable, and to **surface as questions** the things you suspect but can't confirm from code alone.

The sync skill's four-gate filter — universal, non-obvious, not owned by another tool, stable — applies here too. Read it if you need a refresher. Init's added constraint: at genesis you have *no session learnings yet*. Everything you write is inferred from a cold read of the codebase, which means your false-positive rate on "is this actually a rule?" is higher than sync's. Compensate by being stricter about the verified/inferred line.

## Triggering and refusal

**First action on any invocation: glob `**/AGENTS.md`.** If even one exists anywhere in the repo, stop. Do not create a competing file, do not merge, do not overwrite. Tell the user: "An AGENTS.md already exists at `<path>`. Use `/agents-md-sync` to maintain it — init is only for repos that have none." Then exit. This keeps the boundary between the two skills clean.

## Inputs: docs first, code second

The user may provide initial project docs (a README, a design doc, a spec, an architecture write-up, pasted prose) — or nothing at all.

1. **If the user provided docs** — read them first. They are the authoritative narrative for *intent*: what the project is, what it's trying to do, how the pieces relate. Take them at face value for purpose and design.
2. **Then read the codebase** to verify what the docs claim and to capture what the docs omit (actual entry points, real script names, directory structure as it exists today, conventions enforceable from code).
3. **When docs and code conflict**, trust the code for facts (it's what's actually running) but surface the conflict in your draft as a question — don't silently pick a side, because a stale doc often signals intent the code hasn't caught up to.
4. **If no docs at all**, that's fine. Form your understanding entirely from the codebase, and flag anything you're inferring rather than directly observing.

## What to capture (and what to flag)

Separate everything you encounter into two buckets. This split is the most important discipline of this skill.

### Verified — safe to assert as fact

Things you can point to a file, command, or declaration for:

- **Stack and versions** — languages, frameworks, runtimes, key dependencies (from `package.json`, `Cargo.toml`, `pyproject.toml`, `go.mod`, etc.).
- **Entry points** — `main`, `index`, the server bootstrap, the CLI dispatch. Where does execution start?
- **Directory layout** — top-level modules and what each is responsible for, as observable from the tree.
- **Scripts and commands** — build, test, lint, dev server, deploy. From `package.json` scripts, Makefile, `justfile`, CI config.
- **Conventions the tooling enforces** — but only to *point at* them, not restate them. "Formatting is enforced by Prettier — see `.prettierrc`" beats restating the rules.
- **Navigation pointers** — where to look for X (config, tests, types, migrations). `file:line` and directory pointers beat copied content.
- **External interfaces** — public API surface, HTTP routes, event names, CLI flags — as they actually exist in the code.

### Inferred — surface as a question, never assert

Things that look like rules but you can't verify from a cold read:

- "We prefer X pattern over Y." — you may see both in the code; you don't know which is preferred without asking.
- "Always do X before Y." — without a session's worth of bug context, you can't know this.
- "Module X owns concern Y." — plausible from filenames, but ownership boundaries are often implicit and contested.
- Anything that smells like a hidden invariant — those are exactly what sync is designed to capture later, *after* a session has earned the learning.

**Rule of thumb:** if you'd be embarrassed to have future-you trust the line and it turns out wrong, it's inferred. Put it in the draft as a question ("I noticed X — is this a convention you want documented?") rather than asserting it.

## Placement: how many files to create

Sync uses topical locality — grep first, place next to existing mentions. At genesis there's nothing to grep, so you need a structural test instead.

### Default: root only

Most repos should get **a single root `AGENTS.md`**. Start here. The root file holds the project-level facts: purpose, stack, entry points, top-level layout, scripts, cross-cutting conventions, and pointers into the codebase.

### Create a subdirectory AGENTS.md only when both are true

1. **The directory is a real boundary** — a service with its own stack/runtime/deploy target, a self-contained module with its own README, a package in a monorepo workspace, a `docs/` or `scripts/` area with non-obvious local rules. Cosmetically distinct subdirectories do not qualify.
2. **An outsider would hit a wall without it** — there's something about how this directory works that isn't inferrable from the parent file and isn't visible in the code's own types/comments. If a competent reader could figure it out from the code, skip the file.

When in doubt, leave it out. Sync can always create a subdirectory file later when a real learning demands one — that's its job, not init's. A monorepo with 8 services does not need 8 init-time AGENTS.md files; it needs a root file with pointers, plus subdirectory files only where (2) clearly holds.

If you decide a subdirectory file is warranted, keep it as lean as the root — verified facts and pointers, inferences as questions. Don't pad.

## The flow

1. **Refuse if exists.** Glob `**/AGENTS.md`. Anything found → stop, redirect to sync.

2. **Take inputs.** Note any docs the user provided. Note whether the user hinted at scope ("just the root", "include the `services/` tree"). Default scope: root + structural-test subdirectories only.

3. **Explore the codebase with a subagent** if the repo is large (>~20 files at the top level, or >~200 total). Cold-reading a big repo in the main context wastes budget you'll need for writing. Hand the subagent a focused brief: stack identification, entry points, directory responsibilities, scripts/commands, and any conventions visible in tooling configs. Bring back findings, not the whole codebase. For small repos, explore inline.

4. **Bucket everything** into verified vs inferred, as above. Be ruthless — most "rules" you notice on a cold read are actually inferred.

5. **Decide structure** — root only by default, subdirectory files only where the structural test clearly passes. Mention what you considered and rejected.

6. **Draft the file(s) inline** in your response. Show the user the proposed content, not just a plan to write it. Structure each file roughly as:
   - One-line purpose statement for the file's scope.
   - Stack (versions where it matters).
   - Entry points with `file:line` pointers.
   - Directory layout (for root) or this directory's responsibility (for subdirectory files).
   - Scripts and commands — names + one-line purpose each, not full usage.
   - Navigation pointers for things a future session will look up (config, tests, types, migrations, env).
   - Conventions — only verified ones; phrased as pointers to the enforcing tool where possible.
   - An "**Open questions**" section at the end collecting every inferred item as a question for the user. This is the bridge to sync: items the user confirms can be added as rules; items they reject never make it in.

7. **Get explicit approval** before writing. The user may edit, trim, answer the open questions, or reject parts. Apply their changes. Only after approval, write the files with the Edit/Write tool.

8. **Summary.** After writing: list files created (paths), line counts, and any open questions the user didn't resolve — those are the seed of future sync runs. Keep it to bullets.

## Anti-patterns

- **Asserting inferred rules.** This is the cardinal sin. Every wrong rule persists into every future session until someone notices. When uncertain, ask.
- **Stuffing the root file.** A 300-line AGENTS.md at init time is a red flag — you've almost certainly crossed into inference or duplicated what tooling already enforces. Aim for the smallest file that still captures what's verified.
- **Creating subdirectory files preemptively.** "One per top-level directory" is wrong. The structural test is deliberately strict.
- **Restating what the code or tooling already says.** Pointers beat copies. If `.prettierrc` exists, your AGENTS.md says "formatting via Prettier — see `.prettierrc`", not a restatement of the rules.
- **Duplicating the README.** If the README covers purpose and setup well, your AGENTS.md points at it rather than copying. AGENTS.md is for what the agent needs that isn't already obvious from README + code.
- **Skipping the approval gate.** These files load into every future session. The user gets to see what you're about to put there.
- **Running when an AGENTS.md exists.** Always glob first. Hand off to sync.
