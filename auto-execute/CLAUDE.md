# auto-execute

Automates the `/executing-plans` + `/clear` cycle by running each plan task in a fresh Claude process with safety circuit breakers.

## Architecture

Three components, all gated by `AXE_ACTIVE` environment variable:

| Component | Entry Point | Role |
|-----------|-------------|------|
| **Wrapper** | `auto-execute.ps1` | Outer loop: pre-flight (early/late), hook auto-installer, launch Claude per task, verify 3 signals (exit code, new commit, clean tree) |
| **Skill** | `SKILL.md` | Per-task headless behavior: TDD cycle, commit, structured exit output |
| **Hooks** | `.claude/hooks/` | Real-time safety: context limit, loop detection |

## Running

```powershell
# One-time install (adds to PATH, creates .cmd shim)
.\install.ps1

# Execute from any project directory (partial name match)
auto-execute 2026-03-13-markdown-link-checker claude_stable_ali

# With default claude binary
auto-execute markdown-link

# Old explicit form still works
& "path/to/auto-execute.ps1" -Plan "docs/plans/my-plan.md"

# Run tests
Invoke-Pester -Path tests/ -Output Detailed
```

## Safety Guards

- **Pre-flight (early)**: CLI exists, plan file exists, git tree clean
- **Hook auto-installer**: Installs/updates safety hooks in target project
- **Pre-flight (late)**: Plan has unchecked tasks, log directory ready
- **Gitignore enforcement**: Auto-adds `logs/` to `.gitignore` and commits if missing (prevents dirty-tree false positives from script's own log files)
- **Ctrl+C handling**: Uses a compiled C# `ConsoleCancelEventHandler` (via `Add-Type`) to intercept Ctrl+C instantly on the OS signal thread — PowerShell scriptblock delegates are queued on the main runspace thread which never processes them during our blocking loop. The C# handler sets a flag and kills the child process tree via `taskkill /F /T`. The main loop also checks for SIGINT exit codes (130/3221225786) as a fallback.
- **Per-task timeout**: Kill process after N seconds (default 900)
- **Context tracking**: Tracks peak context (input_tokens + cache_read) per task from `assistant` events only (result events contain cumulative session totals); shows in task log and summary
- **Post-task verification**: Exit code 0, new commit, clean tree
- **Hooks**: Block tools on context overflow or repeated identical calls
- **Failure limit**: Stop after N consecutive failures (default 2)

## Key Files

- `auto-execute.ps1` — main wrapper (parameters, process management, verification loop)
- `auto-execute-helpers.ps1` — pure functions (plan parsing, token metrics, formatting)
- `SKILL.md` — Claude Code skill definition (headless task execution rules)
- `.claude/hooks/` — PreToolUse hooks (context-check, loop-detect)
