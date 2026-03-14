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
auto-execute claude_stable_ali mask-endpoint

# With backup claude binary (failover on task failure)
auto-execute claude_stable_ali claude_stable_any mask-endpoint

# Full plan path also works
auto-execute claude_stable_ali docs/plans/2026-03-14-mask-endpoint.md

# Resume from specific task (assumes 1..N-1 done)
auto-execute claude_stable_ali mask-endpoint 5

# Run tests
Invoke-Pester -Path tests/ -Output Detailed
```

## Safety Guards

- **Pre-flight (early)**: CLI exists, plan file exists, git tree clean
- **Hook auto-installer**: Installs/updates safety hooks in target project
- **Pre-flight (late)**: Plan has tasks, log directory ready
- **Gitignore enforcement**: Auto-adds `logs/` to `.gitignore` and commits if missing (prevents dirty-tree false positives from script's own log files)
- **Ctrl+C handling**: Two-layer interrupt mechanism. Primary: `[Console]::TreatControlCAsInput = $true` converts Ctrl+C into a regular keystroke, preventing Node.js (claude) from consuming the OS `CTRL_C_EVENT`. The main loop uses `[Console]::ReadKey()` to detect Ctrl+C, Escape, or Q and kills the child process tree. The child's stdin is redirected to NUL to prevent it from reading console input. Fallback: a compiled C# `ConsoleCancelEventHandler` (via `Add-Type`) handles Ctrl+Break on the OS signal thread. Both layers check for SIGINT exit codes (130/3221225786) as additional fallback. Console state is restored in the `finally` block.
- **Per-task timeout**: Kill process after N seconds (default 900)
- **Context tracking**: Reads Claude Code's transcript JSONL file (`~/.claude/projects/<hash>/<session_id>.jsonl`) for accurate per-turn context size (input_tokens + cache_read_input_tokens + cache_creation_input_tokens). The transcript has real per-turn usage data, unlike stream-json stdout which mostly reports zeros for cache_read. Session ID is captured from the stream-json init event; project hash is derived from git root path (`[^a-zA-Z0-9]` → `-`). Polls transcript every ~1s during execution; does a final read after task completion. Kills process in real-time when peak exceeds `-ContextLimit`; shows in task log and summary.
- **Post-task verification**: Exit code 0, new commit, clean tree
- **Hooks**: Loop detection blocks repeated identical tool calls
- **Failure limit**: Stop after N consecutive failures (default 2)

## Key Files

- `auto-execute.ps1` — main wrapper (parameters, process management, verification loop)
- `auto-execute-helpers.ps1` — pure functions (plan parsing, token metrics, formatting)
- `SKILL.md` — Claude Code skill definition (headless task execution rules)
- `.claude/hooks/` — PreToolUse hooks (context-check, loop-detect)
