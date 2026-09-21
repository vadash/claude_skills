# Modular Refactor — src/ Structure

**Date:** 2026-03-14
**Status:** Approved

## Goal

Refactor `auto-execute.ps1` and `auto-execute-helpers.ps1` into a modular `src/` structure. Entry points (`auto-execute.ps1`, `auto-execute.cmd`) keep the same syntax and behavior. Tests mirror the new module layout.

## Current State

- `auto-execute-helpers.ps1` — 21 functions, ~450 lines, mixing 6 concerns
- `auto-execute.ps1` — ~300 lines, all phases inlined including a ~100-line monitoring loop
- `tests/auto-execute-helpers.Tests.ps1` — ~600 lines, single file covering all helpers

## Architecture

### Directory Layout

```
~/.claude/skills/auto-execute/
  auto-execute.ps1          # thin orchestrator (~150 lines, down from ~300)
  auto-execute.cmd           # unchanged
  install.ps1                # unchanged
  SKILL.md                   # unchanged
  README.md                  # updated file map
  CLAUDE.md                  # updated key files section
  src/
    plan.ps1                 # plan parsing and resolution
    args.ps1                 # CLI argument splitting
    preflight.ps1            # pre-flight checks and git verification
    stream.ps1               # stream JSON parsing and transcript reading
    monitor.ps1              # task monitoring loop (depends on stream + format)
    format.ps1               # formatting and display
  tests/
    plan.Tests.ps1           # mirrors src/plan.ps1
    args.Tests.ps1           # mirrors src/args.ps1
    preflight.Tests.ps1      # mirrors src/preflight.ps1
    stream.Tests.ps1         # mirrors src/stream.ps1
    monitor.Tests.ps1        # tests for Invoke-TaskMonitor
    format.Tests.ps1         # mirrors src/format.ps1
    install.Tests.ps1        # unchanged
    scaffolding.Tests.ps1    # unchanged
```

**Deleted:** `auto-execute-helpers.ps1` (replaced by `src/*.ps1`)

### Module Breakdown

#### `src/plan.ps1` — Plan Parsing (4 functions)

| Function | Purpose |
|----------|---------|
| `Get-PlanTasks` | Parse plan markdown into preamble + task blocks |
| `Get-TaskNumberGaps` | Detect missing task numbers in sequence |
| `Write-TaskTempFile` | Create per-task temp file with preamble + content + footer |
| `Resolve-PlanPath` | Resolve partial plan name to full path via fuzzy match |

#### `src/args.ps1` — Argument Parsing (1 function)

| Function | Purpose |
|----------|---------|
| `Split-AxeArguments` | Split positional args into claude binaries + plan input |

Small but distinct concern. CLI argument handling is separate from plan file content parsing.

#### `src/preflight.ps1` — Pre-flight and Verification (4 functions)

| Function | Purpose |
|----------|---------|
| `Test-PreFlightEarly` | Check CLI exists, plan exists, git repo, clean tree |
| `Test-PreFlightLate` | Check/create log directory |
| `Test-TaskSuccess` | Evaluate 3 post-task signals (exit code, new commit, clean tree) |
| `Save-DirtyState` | Git stash uncommitted changes from failed task |

#### `src/stream.ps1` — Stream JSON and Transcript (6 functions)

| Function | Purpose |
|----------|---------|
| `Read-StreamJsonChunk` | Parse newline-delimited JSON with buffering for partial lines |
| `Get-TokensFromEvent` | Extract token usage from assistant/result events |
| `Get-CostFromEvent` | Extract cost from result events |
| `Get-ContextSizeFromEvent` | Calculate context window size from event usage |
| `Get-TranscriptContextPeak` | Read Claude transcript JSONL for peak context (incremental) |
| `Get-ClaudeProjectHash` | Convert directory path to Claude project hash format |

#### `src/monitor.ps1` — Task Monitoring (1 function)

| Function | Purpose |
|----------|---------|
| `Invoke-TaskMonitor` | Inner monitoring loop: stream parsing, keyboard handling, context tracking, timeout |

This is the primary extraction from `auto-execute.ps1`. The ~100-line `while (-not $exited)` loop becomes a single callable function.

**Signature:**

```powershell
function Invoke-TaskMonitor {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$TaskLogPath,
        [int]$TaskTimeout,
        [int]$ContextLimit,
        [int]$MaxTurns,
        [string]$GitRoot,
        [int]$TaskNumber
    )
    # Returns:
    # @{
    #     ExitCode     = [int]
    #     Tokens       = @{ Input; Output; CacheRead; CacheWrite; Total; HitRate; CostUSD }
    #     PeakContext  = [int]
    #     SessionId    = [string]
    #     Cancelled    = [bool]
    #     StopReason   = [string]
    #     ErrorDetails = [string]  # e.g., "max turns exceeded (75/80)"
    # }
}
```

**Encapsulates:**
- Stream-json file reading with partial-line buffering
- Event parsing (tokens, cost, session ID, error details)
- Keyboard interrupt detection (Ctrl+C, Escape, Q)
- Transcript-based context peak tracking (polls every ~1s)
- Active context limit enforcement (kills process when exceeded)
- Stderr tailing
- Idle timeout enforcement

**Depends on:** `src/stream.ps1` (for event parsing), `src/format.ps1` (for `Format-ToolEvent`, `Format-ContextSize`)

#### `src/format.ps1` — Formatting and Display (6 functions)

| Function | Purpose |
|----------|---------|
| `Format-TaskLogEntry` | Format pass/fail line for a single task |
| `Format-FinalReport` | Format the end-of-run summary block |
| `Format-ContextSize` | Format token count with k/M suffix |
| `Format-ToolEvent` | Format tool_use blocks from stream-json for display |
| `Format-TokenMetrics` | Format token/cost metrics string |
| `Clear-LogDirectory` | Remove old log/err/md files from log directory |

### Loading Strategy

**Explicit dot-source in `auto-execute.ps1`:**

```powershell
. "$PSScriptRoot/src/args.ps1"
. "$PSScriptRoot/src/plan.ps1"
. "$PSScriptRoot/src/preflight.ps1"
. "$PSScriptRoot/src/stream.ps1"
. "$PSScriptRoot/src/format.ps1"
. "$PSScriptRoot/src/monitor.ps1"   # after stream + format (dependencies)
```

No loader scripts, no wildcards. Order matters only for `monitor.ps1` which depends on functions from `stream.ps1` and `format.ps1`.

**Tests source only what they need:**

```powershell
# tests/plan.Tests.ps1
BeforeAll { . "$PSScriptRoot/../src/plan.ps1" }

# tests/monitor.Tests.ps1
BeforeAll {
    . "$PSScriptRoot/../src/stream.ps1"
    . "$PSScriptRoot/../src/format.ps1"
    . "$PSScriptRoot/../src/monitor.ps1"
}
```

### What Stays in `auto-execute.ps1`

The main script becomes a thin orchestrator:

1. **Parameter block** — unchanged
2. **Dot-source** `src/` modules
3. **Phase 0** — `Split-AxeArguments` + `Resolve-PlanPath`
4. **Phase 1** — `Test-PreFlightEarly` + `Test-PreFlightLate` + gitignore enforcement
5. **Phase 2** — `Get-PlanTasks` + gap detection + start index determination
6. **Phase 3** — Main loop per task:
   - Record baseline hash, create temp file, build claude args, launch process
   - `$result = Invoke-TaskMonitor ...` — one call replaces ~100 lines
   - Check cancellation from result
   - `Test-TaskSuccess` + retry/backup decision logic
   - Accumulate overall metrics
7. **Finally** — cleanup (console state, kill child, remove temp file), `Format-FinalReport`

Retry/decision logic stays inlined — it manages loop state (`$consecutiveFailures`, `$useBackup`, `$running`, `$stashedThisTask`, `$summaryEntries`) that is core orchestration.

### Test Organization

Each test file mirrors its src/ module. The existing `auto-execute-helpers.Tests.ps1` Describe blocks map directly:

| Current Describe Block | Target Test File |
|----------------------|-----------------|
| `Get-PlanTasks` | `tests/plan.Tests.ps1` |
| `Get-TaskNumberGaps` | `tests/plan.Tests.ps1` |
| `Write-TaskTempFile` | `tests/plan.Tests.ps1` |
| `Resolve-PlanPath` | `tests/plan.Tests.ps1` |
| `Split-AxeArguments` | `tests/args.Tests.ps1` |
| `Test-PreFlightEarly` | `tests/preflight.Tests.ps1` |
| `Test-PreFlightLate` | `tests/preflight.Tests.ps1` |
| `Test-TaskSuccess` | `tests/preflight.Tests.ps1` |
| `Format-TaskLogEntry` | `tests/format.Tests.ps1` |
| `Format-FinalReport` | `tests/format.Tests.ps1` |
| `Format-ContextSize` | `tests/format.Tests.ps1` |
| `Format-ToolEvent` | `tests/format.Tests.ps1` |
| `Format-TokenMetrics` | `tests/format.Tests.ps1` |
| `Clear-LogDirectory` | `tests/format.Tests.ps1` |
| `Read-StreamJsonChunk` | `tests/stream.Tests.ps1` |
| `Get-TokensFromEvent` | `tests/stream.Tests.ps1` |
| `Get-CostFromEvent` | `tests/stream.Tests.ps1` |
| `Get-ContextSizeFromEvent` | `tests/stream.Tests.ps1` |
| `Get-TranscriptContextPeak` | `tests/stream.Tests.ps1` |
| `Get-ClaudeProjectHash` | `tests/stream.Tests.ps1` |

`tests/monitor.Tests.ps1` is new — tests for `Invoke-TaskMonitor`. Will need mocking of process behavior and stream-json file output.

`tests/install.Tests.ps1` and `tests/scaffolding.Tests.ps1` stay unchanged.

`tests/auto-execute-helpers.Tests.ps1` is deleted.

## Implementation Notes

- Pure function move — no logic changes to existing functions. Each function moves verbatim to its new file.
- `Invoke-TaskMonitor` is an extraction, not a rewrite. Same logic, wrapped in a function with clean input/output contract.
- `auto-execute.ps1` main loop simplifies by replacing the inner while loop with a single `Invoke-TaskMonitor` call and using the returned hashtable.
- All existing tests must pass after the move (same assertions, different source paths).
