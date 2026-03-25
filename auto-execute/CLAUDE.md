# auto-execute

Automates the `/executing-plans` + `/clear` cycle by running each plan task in a fresh Claude process with safety circuit breakers.

## Architecture

Two components:

| Component | Entry Point | Role |
|-----------|-------------|------|
| **Wrapper** | `auto-execute.ps1` | Outer loop: pre-flight (early/late), task splitting, launch Claude per task, verify 3 signals (exit code, new commit, clean tree) |
| **Skill** | `SKILL.md` | Per-task headless behavior: TDD cycle, commit, structured exit output |

## Running

```powershell
# One-time install (adds to PATH, creates .cmd shim)
.\install.ps1

# Execute from any project directory (partial name match)
# 1 binary = 1 attempt per task
auto-execute claude_stable_kimi mask-endpoint

# 2 binaries = 2 attempts per task (1 each, tries second on first failure)
auto-execute claude_stable_kimi claude_stable_any mask-endpoint

# 5 binaries = 5 attempts per task (max supported)
auto-execute claude_a claude_b claude_c claude_d claude_e mask-endpoint

# Full plan path also works
auto-execute claude_stable_kimi docs/plans/2026-03-14-mask-endpoint.md

# Run the most recently committed plan
auto-execute claude_stable_kimi claude_stable_glm latest

# Resume from specific task (assumes 1..N-1 done)
auto-execute claude_stable_kimi mask-endpoint 5
auto-execute claude_stable_kimi mask-endpoint --Start-task 5

# Run tests (bash shell is Unix-style on Windows, so wrap PowerShell commands)
powershell -NoProfile -Command "Invoke-Pester -Path 'tests' -Output Detailed"
```

## Safety Guards

- **Pre-flight (early)**: CLI exists, plan file exists, git tree clean
- **Task splitting**: Pre-flight parsing extracts preamble and individual tasks from plan; gap detection warns if task numbers skip; each task gets a temp file with its portion of the plan
- **Pre-flight (late)**: Plan has tasks, log directory ready
- **Gitignore enforcement**: Auto-adds `logs/` to `.gitignore` and commits if missing (prevents dirty-tree false positives from script's own log files)
- **Ctrl+C handling**: Two-layer interrupt mechanism. Primary: `[Console]::TreatControlCAsInput = true` converts Ctrl+C into a regular keystroke, preventing Node.js (claude) from consuming the OS `CTRL_C_EVENT`. The main loop uses `[Console]::ReadKey()` to detect Ctrl+C, Escape, or Q and kills the child process tree. The child's stdin is redirected to NUL to prevent it from reading console input. Fallback: a compiled C# `ConsoleCancelEventHandler` (via `Add-Type`) handles Ctrl+Break on the OS signal thread. Both layers check for SIGINT exit codes (130/3221225786) as additional fallback. Console state is restored in the `finally` block.
- **Per-task timeout**: Kill process after N seconds of idle time — no stream-json events received (default 600)
- **Max turns**: Hard limit on assistant turns per task (default 80). Captured from stream-json `error_max_turns` events; failure output shows exact turns used (e.g., "max turns exceeded (75/80)")
- **Context tracking**: Reads Claude Code's transcript JSONL file (`~/.claude/projects/<hash>/<session_id>.jsonl`) for accurate per-turn context size (input_tokens + cache_read_input_tokens + cache_creation_input_tokens). The transcript has real per-turn usage data, unlike stream-json stdout which mostly reports zeros for cache_read. Session ID is captured from the stream-json init event; project hash is derived from git root path (`[^a-zA-Z0-9]` → `-`). Polls transcript every ~1s during execution; does a final read after task completion. Kills process in real-time when peak exceeds `-ContextLimit`; shows in task log and summary.
- **Post-task verification**: Exit code 0, new commit, clean tree. Smart dirty tree guard (`Invoke-TreeCleanup`) handles 4 state combinations: (success, dirty) → `git clean -fd` + `git checkout HEAD .` (restore tracked files to committed state); (success, clean) → no-op; (failure, dirty) → hard reset and retry; (failure, clean) → no-op. The checkout handles verification commands (e.g., `typecheck` running generators) that dirty the tree with timestamp-only changes. Captures specific error details (e.g., max turns exceeded) from stream-json result events for clearer failure messages.
- **Multi-binary execution**: Provide 1-5 Claude binaries as positional arguments. Each binary gets exactly one attempt per task. On failure, the next binary is tried. Execution stops only when all binaries have been exhausted for a task.
- **Full plan on retry**: On attempt 2+ (second binary or later), the full plan file is fed instead of just the single task. This provides broader context when initial attempts fail, helping Claude understand cross-task dependencies and architectural patterns.

## Key Files

- `auto-execute.ps1` — main wrapper (parameters, dot-sources modules, process management, verification loop)
- `src/args.ps1` — CLI argument splitting (`Split-AxeArguments`): classifies `claude`-prefixed args as binaries (1-5 supported), bare numbers or `--Start-task N` as StartTask, remainder as plan input
- `src/plan.ps1` — plan parsing (`Get-PlanTasks`, `Get-TaskNumberGaps`, `Write-TaskTempFile`, `Resolve-PlanPath`)
- `src/preflight.ps1` — pre-flight checks (`Test-PreFlightEarly`, `Test-PreFlightLate`, `Test-TaskSuccess`, `Invoke-TreeCleanup`)
- `src/stream.ps1` — stream JSON parsing and transcript reading (6 functions)
- `src/format.ps1` — formatting and display (6 functions)
- `src/monitor.ps1` — task monitoring loop (`Invoke-TaskMonitor`; depends on stream + format)
- `SKILL.md` — Claude Code skill definition (headless task execution rules)
## Development Notes

- **Git show patch**: Use `git show <commit> -p` not `git show <commit> --no-stat` (fails with "unrecognized argument" on Windows)
