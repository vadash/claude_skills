# auto-execute

Automates the repetitive `/executing-plans` + `/clear` cycle by running each plan task in a fresh Claude process with safety circuit breakers.

## Architecture

Three components:

| Component | File | Role |
|-----------|------|------|
| **Skill** | `SKILL.md` | Per-task headless behavior for Claude Code |
| **Wrapper** | `auto-execute.ps1` | Outer loop — launches Claude per task, verifies results |
| **Hooks** | `.claude/hooks/` | Real-time safety guards (context limits, loop detection) |

Hooks are gated by the `AXE_ACTIVE` environment variable — they stay silent during normal manual usage.

## Prerequisites

- PowerShell 7.x (recommended) or PowerShell 5.1+
- Claude Code CLI (`claude`) in PATH
- Pester 5.x (for running tests)
- Git

## Installation

The skill is installed globally at `~/.claude/skills/auto-execute/`. No per-repo install needed for the core script.

### Hooks (per-repo, required for safety guards)

Copy the `.claude` folder into any repo where you want the safety hooks active:

```powershell
# From the target repo root
Copy-Item -Recurse "C:\Users\vadash\.claude\skills\auto-execute\.claude" ".claude"
```

This gives the repo:
```
.claude/
  settings.json          # hook registration
  hooks/
    axe-context-check.ps1    # blocks tools when context window is nearly full
    axe-loop-detect.ps1      # blocks tools when Claude is stuck repeating itself
```

Without this, the wrapper still works — you just lose the safety hooks.

### Gitignore

The script automatically ensures `logs/` is in `.gitignore` before running tasks. If missing, it appends the entry and commits with `chore: add logs to .gitignore`. No manual setup needed.

## Usage

### Basic — run all remaining tasks

```powershell
& "C:\Users\vadash\.claude\skills\auto-execute\auto-execute.ps1" -Plan "docs/plans/my-plan.md"
```

The script auto-detects the first unchecked task (`- [ ]`) and runs from there.

### Start from a specific task

```powershell
& "C:\Users\vadash\.claude\skills\auto-execute\auto-execute.ps1" -Plan "docs/plans/my-plan.md" -StartTask 3
```

### All parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Plan` | *(required)* | Path to the plan file (relative to repo root) |
| `-ClaudeBin` | `claude` | Claude CLI binary name or path |
| `-MaxTurns` | `40` | Max Claude turns per task |
| `-TaskTimeout` | `900` | Seconds before killing a stuck task (15 min) |
| `-ContextLimit` | `70000` | Token threshold — wrapper kills task when peak context exceeds this |
| `-MaxFailures` | `2` | Consecutive failures before stopping the loop |
| `-StartTask` | `0` | Force start at a specific task (0 = auto-detect) |
| `-LogDir` | `logs/auto-execute` | Where run/task logs are written |

### Examples

```powershell
# Quick run with shorter timeout
& "C:\Users\vadash\.claude\skills\auto-execute\auto-execute.ps1" -Plan "docs/plans/auth.md" -TaskTimeout 600

# Allow more retries and turns
& "C:\Users\vadash\.claude\skills\auto-execute\auto-execute.ps1" -Plan "docs/plans/big-refactor.md" -MaxTurns 60 -MaxFailures 3

# Use a specific claude binary
& "C:\Users\vadash\.claude\skills\auto-execute\auto-execute.ps1" -Plan "docs/plans/auth.md" -ClaudeBin "C:\bin\claude.exe"
```

## What it does

For each unchecked task in the plan:

1. **Pre-flight** — verifies clean git tree, plan file exists, CLI available, installs/updates safety hooks if needed, ensures `logs/` is in `.gitignore`
2. **Launch** — runs `claude -p "/auto-execute @plan.md do task N" --dangerously-skip-permissions`
3. **Monitor** — tails output in real-time, tracks peak context usage per task, enforces timeout
4. **Verify** — checks 3 signals: exit code 0, new commit, clean tree
5. **Decide** — on success advances to next task; on failure stashes dirty state or retries

Each task logs peak context extracted from Claude Code's transcript JSONL file (`~/.claude/projects/<hash>/<session_id>.jsonl`), which contains accurate per-turn usage data including cached tokens. Context size per turn = `input_tokens + cache_read_input_tokens + cache_creation_input_tokens`.

Stops when:
- All tasks complete
- Cancelled by user (Ctrl+C) — kills child process cleanly; also detects SIGINT exit codes (130/3221225786) when child swallows the interrupt
- Consecutive failures hit `-MaxFailures`
- Context limit exceeded (wrapper kills process when peak context > `-ContextLimit`)
- Dirty tree detected (changes are git-stashed)
- Timeout exceeded

## Plan format

Plans must use this task/step structure:

```markdown
### Task 1: Setup

- [ ] Step 1: Do something
- [ ] Step 2: Do another thing

### Task 2: Implementation

- [ ] Step 1: Write tests
- [ ] Step 2: Write code
```

Checked steps (`- [x]`) are considered done. The wrapper finds the first task with any unchecked step.

## Safety hooks

Both hooks only activate when `AXE_ACTIVE=true` (set automatically by the wrapper).

### axe-context-check.ps1

No-op. Context limit enforcement is handled in real-time by the wrapper using exact token counts from stream-json events. The hook file is kept so existing `settings.json` registrations don't break.

### axe-loop-detect.ps1

Tracks tool calls per session in temp files. Blocks when:
- Total calls exceed 100 (configurable)
- Same exact call repeats 3+ times in the last 10 calls

## Logs

Each run creates:
- `logs/auto-execute/run-YYYYMMDD-HHmmss.log` — summary of all tasks
- `logs/auto-execute/task-N-YYYYMMDD-HHmmss.log` — full Claude output per task
- `logs/auto-execute/task-N-*.log.err` — stderr per task

## Running tests

```powershell
# All tests
Invoke-Pester -Path "C:\Users\vadash\.claude\skills\auto-execute\tests" -Output Detailed

# Individual test files
Invoke-Pester -Path "C:\Users\vadash\.claude\skills\auto-execute\tests\context-check.Tests.ps1" -Output Detailed
Invoke-Pester -Path "C:\Users\vadash\.claude\skills\auto-execute\tests\loop-detect.Tests.ps1" -Output Detailed
Invoke-Pester -Path "C:\Users\vadash\.claude\skills\auto-execute\tests\auto-execute-helpers.Tests.ps1" -Output Detailed
```

## File map

```
~/.claude/skills/auto-execute/
  README.md                              # this file
  SKILL.md                               # Claude Code skill definition
  auto-execute.ps1                       # main wrapper script
  auto-execute.cmd                       # .cmd shim for PATH usage
  auto-execute-helpers.ps1               # pure helper functions
  install.ps1                            # one-time installer (adds to PATH)
  .claude/
    settings.json                        # hook registration (copy to target repo)
    hooks/
      axe-context-check.ps1                  # context limit hook
      axe-loop-detect.ps1                    # loop detection hook
  tests/
    scaffolding.Tests.ps1                # test infrastructure verification
    context-check.Tests.ps1              # context hook tests
    loop-detect.Tests.ps1                # loop detection tests
    auto-execute-helpers.Tests.ps1       # helper function tests
    install.Tests.ps1                    # installer tests
  docs/
    designs/2026-03-13-auto-execute.md   # design document
    plans/2026-03-13-auto-execute.md     # implementation plan
```
