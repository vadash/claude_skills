# auto-execute

Automates the `/executing-plans` + `/clear` cycle by running each plan task in a fresh Claude process with safety circuit breakers.

## Architecture

Three components, all gated by `RALPH_ACTIVE` environment variable:

| Component | Entry Point | Role |
|-----------|-------------|------|
| **Wrapper** | `auto-execute.ps1` | Outer loop: pre-flight, launch Claude per task, verify 3 signals (exit code, new commit, clean tree) |
| **Skill** | `SKILL.md` | Per-task headless behavior: TDD cycle, commit, structured exit output |
| **Hooks** | `.claude/hooks/` | Real-time safety: context limit, loop detection |

## Running

```powershell
# Execute all remaining tasks in a plan
& "path/to/auto-execute.ps1" -Plan "docs/plans/my-plan.md"

# Run tests
Invoke-Pester -Path tests/ -Output Detailed
```

## Safety Guards

- **Pre-flight**: CLI exists, plan has unchecked tasks, git tree clean
- **Per-task timeout**: Kill process after N seconds (default 900)
- **Post-task verification**: Exit code 0, new commit, clean tree
- **Hooks**: Block tools on context overflow or repeated identical calls
- **Failure limit**: Stop after N consecutive failures (default 2)

## Key Files

- `auto-execute.ps1` — main wrapper (parameters, process management, verification loop)
- `auto-execute-helpers.ps1` — pure functions (plan parsing, token metrics, formatting)
- `SKILL.md` — Claude Code skill definition (headless task execution rules)
- `.claude/hooks/` — PreToolUse hooks (context-check, loop-detect)
