---
name: setup-matt-pocock-skills
description: Configure this repo for the engineering skills: where issues live, the triage label vocabulary, and the domain doc layout.
disable-model-invocation: true
---

Scaffold the per-repo configuration that the engineering skills assume:

- **Issue tracker**: where issues live (GitHub by default; local markdown is also supported out of the box)
- **Triage labels**: the strings used for the five canonical triage roles
- **Domain docs**: where `GLOSSARY.md` and ADRs live, and the consumer rules for reading them

Invocation: `/skill:setup-matt-pocock-skills`. Run it once before the first use of the other engineering skills. Invoking it authorises writing `docs/agents/*.md` and the `## Agent skills` block, once the user has confirmed the draft.

This is a prompt-driven skill, not a deterministic script. Explore, present what you found, confirm with the user, then write.

## [YOU] Phase 1: Explore

Look at the current repo to understand its starting state. Read whatever exists; don't assume:

- `git remote -v` and `.git/config`: is this a GitHub repo? Which one?
- `AGENTS.md` and `CLAUDE.md` at the repo root: does either exist? Is there already an `## Agent skills` section in either?
- `GLOSSARY.md` and `GLOSSARY-MAP.md` at the repo root, and the legacy `CONTEXT.md` / `CONTEXT-MAP.md`. If a legacy file exists, offer to `git mv` it to its `GLOSSARY` name and rewrite those names in `docs/agents/domain.md`.
- `docs/adr/` and any `src/*/docs/adr/` directories
- `docs/agents/`: does this skill's prior output already exist?
- `.scratch/`: a sign that a local-markdown issue tracker convention is already in use
- Is the `triage` skill installed? A flat install makes that a `triage` folder sitting alongside this one in the skills directory, or simply a `triage` name in your available skills. This decides whether Section B runs at all.
- Monorepo signals: a `pnpm-workspace.yaml`, a `workspaces` field in `package.json`, or a populated `packages/*` with its own `src/`. These are present only in a genuinely large multi-package repo; their absence means single-context, which is almost every repo.

**Done**: every bullet above is resolved to present or absent, each from a file you actually read rather than a guess.

## [YOU] Phase 2: Present findings

Summarise what is present and what is missing, in the user's terms: the tracker the remote implies, which of `AGENTS.md` / `CLAUDE.md` will be edited, whether a glossary already exists or a legacy one wants migrating, whether `docs/agents/` holds prior output, whether `.scratch/` shows a local-tracker convention already in use, whether `triage` is installed, and whether this is a monorepo. State plainly which sections will run and which exploration already settled.

**Done**: the user can see the starting state without opening any of the files themselves.

## [YOU] Phase 3: Settle the sections, one at a time

Take the sections in order. One section, one answer, then the next.

Lead each section with the recommended answer so the user can accept it in a word. Give a one-line explainer only when the choice genuinely branches; skip the section entirely when exploration already settled it (Section B when `triage` isn't installed, Section C when there's no monorepo).

### Section A: Issue tracker

> Explainer: The "issue tracker" is where issues live for this repo. Skills like `to-tickets`, `triage`, and `to-spec` read from and write to it. They need to know whether to call `gh issue create`, write a markdown file under `.scratch/`, or follow some other workflow you describe. Pick the place you actually track work for this repo.

Default posture: these skills were designed for GitHub. If a `git remote` points at GitHub, propose that. If a `git remote` points at GitLab (`gitlab.com` or a self-hosted host), propose GitLab. Otherwise (or if the user prefers), offer:

- **GitHub**: issues live in the repo's GitHub Issues (uses the `gh` CLI)
- **GitLab**: issues live in the repo's GitLab Issues (uses the [`glab`](https://gitlab.com/gitlab-org/cli) CLI)
- **Local markdown**: issues live as files under `.scratch/<feature>/` in this repo (good for solo projects or repos without a remote)
- **Other** (Jira, Linear, etc.): ask the user to describe the workflow in one paragraph; the skill will record it as freeform prose

Record the choice in `docs/agents/issue-tracker.md`. The GitHub and GitLab templates carry a "PRs as a request surface" flag, defaulted **off**. Leave it off and don't raise it: a user who wants external PRs in the triage queue can flip the flag in the file later.

A GitHub or GitLab tracker needs a reachable repo. When the user picks one and no `git remote` points at that host, get the repo URL from them and wire it up (`git init` if needed, `git remote add origin <url>`) before going further. The check: `gh repo view` / `glab repo view` prints the project from inside this directory; if it can't, stop and tell the user what's missing.

### Section B: Triage label vocabulary

Skip this section entirely if the `triage` skill isn't installed (exploration told you), since an uninstalled skill needs no labels.

If it is installed, ask exactly one question:

> Do you want to keep the default triage labels? (recommended: **yes**)

The defaults are the five canonical roles, each label string equal to its name: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. On **yes**, write them as-is. Only if the user says no, usually because their tracker already uses other names (e.g. `bug:triage` for `needs-triage`), collect the overrides so `triage` applies existing labels instead of creating duplicates.

### Section C: Domain docs

Default to **single-context** (one `GLOSSARY.md` + `docs/adr/` at the repo root). This fits almost every repo; write it without asking.

Offer **multi-context** (a root `GLOSSARY-MAP.md` pointing to per-context `GLOSSARY.md` files) only when exploration found monorepo signals. Then confirm which layout they want.

**Done**: each section that runs has one recorded answer, and the tracker choice is either reachable from this directory or has a named missing piece reported to the user.

## [YOU] Phase 4: Confirm and edit

Show the user a draft of:

- The `## Agent skills` block to add to whichever of `CLAUDE.md` / `AGENTS.md` is being edited (see Phase 5 for the selection rules)
- The contents of `docs/agents/issue-tracker.md`, `docs/agents/domain.md`, and `docs/agents/triage-labels.md` (the last only when `triage` is installed)

Let them edit before writing.

**Done**: the user has seen every file about to be written, and has either approved it or given the changes.

## [YOU] Phase 5: Write

**Pick the file to edit:**

- If `CLAUDE.md` exists, edit it.
- Else if `AGENTS.md` exists, edit it.
- If neither exists, ask the user which one to create; don't pick for them.

Never create `AGENTS.md` when `CLAUDE.md` already exists (or vice versa); always edit the one that's already there.

If an `## Agent skills` block already exists in the chosen file, update its contents in-place rather than appending a duplicate. Don't overwrite user edits to the surrounding sections.

The block:

```markdown
## Agent skills

### Issue tracker

[one-line summary of where issues are tracked]. See `docs/agents/issue-tracker.md`.

### Triage labels

[one-line summary of the label vocabulary]. See `docs/agents/triage-labels.md`.

### Domain docs

[one-line summary of layout: "single-context" or "multi-context"]. See `docs/agents/domain.md`.
```

Include the `### Triage labels` sub-block, and write `docs/agents/triage-labels.md`, only when `triage` is installed and Section B ran. When it isn't, both are omitted.

When Section B ran on GitHub or GitLab, create each configured label the tracker lacks (`gh label create` / `glab label create`).

Then write the docs files, using the seed templates in this skill folder as a starting point:

- `read skill://setup-matt-pocock-skills/issue-tracker-github.md`: GitHub issue tracker
- `read skill://setup-matt-pocock-skills/issue-tracker-gitlab.md`: GitLab issue tracker
- `read skill://setup-matt-pocock-skills/issue-tracker-local.md`: local-markdown issue tracker
- `read skill://setup-matt-pocock-skills/triage-labels.md`: label mapping (only if `triage` is installed)
- `read skill://setup-matt-pocock-skills/domain.md`: domain doc consumer rules + layout

For "other" issue trackers, write `docs/agents/issue-tracker.md` from scratch using the user's description.

**Done**: `docs/agents/issue-tracker.md` and `docs/agents/domain.md` exist with the confirmed content, `docs/agents/triage-labels.md` exists exactly when `triage` is installed, and the chosen `CLAUDE.md` / `AGENTS.md` carries one `## Agent skills` block whose three summaries match those files.

## [YOU] Phase 6: Hand over

Tell the user the setup is complete and which engineering skills will now read from these files: `to-tickets`, `to-spec`, `wayfinder`, and `triage` when it is installed. Mention they can edit `docs/agents/*.md` directly later; re-running this skill is only necessary if they want to switch issue trackers or restart from scratch.

**Done**: the user knows the setup is complete, which files are now the source of truth, and that editing them by hand is the normal path from here.
