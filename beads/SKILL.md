---
name: beads
description: Use when a repository uses bd or Beads for durable task tracking, issue dependencies, blockers, current work state, or rare shared project memory. Trigger when finding or claiming work, creating or closing tasks, inspecting blockers, recovering task context, maintaining issue notes, or deciding whether information belongs in Beads, AGENTS.md, agent_docs, or a temporary handoff.
---

# Beads

Use Beads as the durable source for mutable project work. Do not turn it into a
copy of repository documentation or a chronological session archive.

## Startup

Use the `bd prime` context already injected by repository hooks. Run `bd prime`
manually only when that context is absent or stale; use `bd where` if workspace
discovery is uncertain.

## Ownership

| Information | Owner |
|---|---|
| Tasks, status, dependencies, blockers, acceptance | Beads issues |
| Current workstream state and next action | Active issue notes |
| Stable architecture, invariants, evidence, runbooks | `AGENTS.md` / `agent_docs/` |
| Emergency session checkpoint | Temporary handoff file |
| Rare stable fact useful in almost every future session | `bd remember` |

Use local planning tools only for the current turn's execution checklist. They
are not shared project state.

## Core workflow

1. Inspect before acting:

```bash
bd ready
bd list --status=in_progress
bd show <id>
```

2. Claim work before editing:

```bash
bd update <id> --claim
```

3. Create durable work when no issue represents the requested change:

```bash
bd create --title="Short title" --description="Why this exists and what must change" --type=task --priority=2
```

4. Keep issue notes concise and current. Replace stale state instead of appending
an unbounded diary.

5. Close only after acceptance is complete:

```bash
bd close <id> --reason="Completed and verified"
```

## Memory hygiene

Every `bd remember` value is injected by `bd prime`, so each memory consumes
context in every session.

The active agent using this skill owns memory creation, replacement, and
deletion. Hooks only load memories; `agents-md-init`, `agents-md-sync`, and
`handoff` do not maintain them. Perform an explicit memory audit when the user
requests one or when current work exposes a stale, duplicated, or relocated fact.

Before adding one:

1. Run `bd memories` and reject duplicates.
2. Confirm the fact is stable, non-obvious, short, and broadly useful.
3. Confirm it is not already owned by code, an issue, `AGENTS.md`, or
   `agent_docs/`.
4. Use a stable key and update it in place with `bd remember --key <key> ...`.
5. Remove obsolete memories with `bd forget <key>`.

Never store these as memories:

- handoff paths, chains, or resume prompts
- active task progress or next actions
- completed milestone chronology
- copies of architecture, validation evidence, or runbooks
- secrets, credentials, private identifiers, or ignored configuration

## Rules

- Do not create Markdown task ledgers when Beads is available.
- Do not use `bd edit`; use non-interactive `bd update` flags.
- Prefer `--json` when parsing output programmatically.
- Do not mutate or close issues merely because related code exists.
- Do not push Beads/Dolt state without explicit authority.
