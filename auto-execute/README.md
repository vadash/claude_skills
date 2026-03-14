# auto-execute

Automates the repetitive `/executing-plans` + `/clear` cycle by running each plan task in a fresh Claude process with safety circuit breakers.

## Architecture

Two components:

| Component | File | Role |
|-----------|------|------|
| **Skill** | `SKILL.md` | Per-task headless behavior for Claude Code |
| **Wrapper** | `auto-execute.ps1` | Outer loop — launches Claude per task, verifies results |

## Prerequisites

- PowerShell 7.x (recommended) or PowerShell 5.1+
- Claude Code CLI (`claude`) in PATH
- Pester 5.x (for running tests)
- Git

## Installation

The skill is installed globally at `~/.claude/skills/auto-execute/`. No per-repo install needed for the core script.

## Usage

### Basic — run all tasks from start

```powershell
& "C:\Users\vadash\.claude\skills\auto-execute\auto-execute.ps1" -Plan "docs/plans/my-plan.md"
```

Starts from task 1. Assumes nothing done yet.

### Resume from a specific task

```powershell
& "C:\Users\vadash\.claude\skills\auto-execute\auto-execute.ps1" -Plan "docs/plans/my-plan.md" -StartTask 3
```

Assumes tasks 1-2 are already complete.

### All parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Plan` | *(required)* | Path to the plan file (relative to repo root) |
| `-ClaudeBin` | `claude` | Claude CLI binary name or path |
| `-MaxTurns` | `80` | Max Claude turns per task |
| `-TaskTimeout` | `600` | Seconds of idle time before killing a stuck task |
| `-ContextLimit` | `100000` | Token threshold — wrapper kills task when peak context exceeds this |
| `-MaxFailures` | `2` | Consecutive failures before stopping the loop |
| `-StartTask` | `0` | Start at specific task (0 = start from 1, N = assumes 1..N-1 done) |
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

For each task from start to finish:

1. **Pre-flight** — parses plan into preamble + individual tasks; detects gaps in task numbering; verifies clean git tree, plan file exists, CLI available; ensures `logs/` is in `.gitignore`
2. **Launch** — creates per-task temp file (preamble + task content), runs `claude -p "/auto-execute task-N.md" --dangerously-skip-permissions`
3. **Monitor** — tails output in real-time, tracks peak context usage per task, enforces idle timeout
4. **Verify** — checks 3 signals: exit code 0, new commit, clean tree
5. **Decide** — on success advances to next task; on failure stashes dirty state or retries

Each task logs peak context extracted from Claude Code's transcript JSONL file (`~/.claude/projects/<hash>/<session_id>.jsonl`), which contains accurate per-turn usage data including cached tokens. Context size per turn = `input_tokens + cache_read_input_tokens + cache_creation_input_tokens`.

Stops when:
- All tasks complete
- Cancelled by user (Ctrl+C, Escape, or Q) — kills child process cleanly via `taskkill /F /T`; also detects SIGINT exit codes (130/3221225786) when child swallows the interrupt
- Consecutive failures hit `-MaxFailures`
- Context limit exceeded (wrapper kills process when peak context > `-ContextLimit`)
- Dirty tree detected (changes are git-stashed)
- Timeout exceeded

## Plan format

Plans use task headers:

```markdown
### Task 1: Setup

Step 1: Do something
Step 2: Do another thing

### Task 2: Implementation

Step 1: Write tests
Step 2: Write code
```

The wrapper runs tasks sequentially starting from task 1 (or `-StartTask N` if resuming).

## Logs

Each run creates:
- `logs/auto-execute/run-YYYYMMDD-HHmmss.log` — summary of all tasks
- `logs/auto-execute/task-N-YYYYMMDD-HHmmss.log` — full Claude output per task
- `logs/auto-execute/task-N-*.log.err` — stderr per task

## Running tests

```powershell
# All tests
Invoke-Pester -Path "C:\Users\vadash\.claude\skills\auto-execute\tests" -Output Detailed

# Individual module tests
Invoke-Pester -Path "C:\Users\vadash\.claude\skills\auto-execute\tests\plan.Tests.ps1" -Output Detailed
Invoke-Pester -Path "C:\Users\vadash\.claude\skills\auto-execute\tests\monitor.Tests.ps1" -Output Detailed
```

## File map

```
~/.claude/skills/auto-execute/
  README.md                              # this file
  SKILL.md                               # Claude Code skill definition
  auto-execute.ps1                       # thin orchestrator — dot-sources src/ modules
  auto-execute.cmd                       # .cmd shim for PATH usage
  install.ps1                            # one-time installer (adds to PATH)
  src/
    args.ps1                             # CLI argument splitting
    plan.ps1                             # plan parsing and resolution
    preflight.ps1                        # pre-flight checks and verification
    stream.ps1                           # stream JSON parsing and transcript reading
    format.ps1                           # formatting and display
    monitor.ps1                          # task monitoring loop (depends on stream + format)
  tests/
    args.Tests.ps1                       # mirrors src/args.ps1
    plan.Tests.ps1                       # mirrors src/plan.ps1
    preflight.Tests.ps1                  # mirrors src/preflight.ps1
    stream.Tests.ps1                     # mirrors src/stream.ps1
    format.Tests.ps1                     # mirrors src/format.ps1
    monitor.Tests.ps1                    # tests for Invoke-TaskMonitor
    scaffolding.Tests.ps1                # test infrastructure verification
    install.Tests.ps1                    # installer tests
  docs/
    designs/                             # design documents
    plans/                               # implementation plans
```
