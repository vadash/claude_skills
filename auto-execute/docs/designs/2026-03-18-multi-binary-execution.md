# Multi-Binary Execution (Up to 5 Binaries)

**Status:** Design Approved
**Date:** 2026-03-18

## Summary

Remove the `MaxFailures` limit and support up to 5 Claude binaries. Each binary gets exactly one attempt per task. Execution proceeds to the next binary on failure, and stops only when all binaries have been exhausted.

## Current Behavior

- Maximum 2 binaries: main + backup
- `MaxFailures` parameter (default 2) controls consecutive failures before stopping
- Backup binary only used after `MaxFailures` is reached with main binary

## New Behavior

- Support 1-5 binaries (any arguments starting with `claude`)
- Each binary gets exactly 1 attempt per task
- No `MaxFailures` — stop when all binaries exhausted
- Binary index resets to 0 for each new task

## Usage Examples

```powershell
# 1 binary = 1 try per task
auto-execute claude_stable_kimi latest

# 3 binaries = 3 tries per task (1 each)
auto-execute claude_stable_kimi claude_stable_any claude-opus-4-6 latest

# 5 binaries = 5 tries per task (1 each)
auto-execute claude_stable_kimi claude_stable_any claude-opus-4-6 claude-sonnet-4-6 claude-haiku-4-5 latest
```

## Architecture Changes

### 1. Argument Parsing (`src/args.ps1`)

**Before:**
```powershell
return @{
    MainClaude   = $claudeBinaries[0]
    BackupClaude = if ($claudeBinaries.Count -gt 1) { $claudeBinaries[1] } else { $null }
    PlanInput    = $otherArgs[0]
    StartTask    = $startTask
}
```

**After:**
```powershell
return @{
    ClaudeBinaries = $claudeBinaries  # Array of 1-5 binaries
    PlanInput      = $otherArgs[0]
    StartTask      = $startTask
}
```

- Change validation from `max 2` to `max 5`
- Keep `MaxFailures` parameter in main script for backward compatibility but mark deprecated

### 2. Execution Loop (`auto-execute.ps1`)

**State Changes:**
- Remove: `$consecutiveFailures` counter
- Remove: `$useBackup` boolean
- Add: `$binaryIndex` integer (0-based index into binaries array)

**Loop Logic:**

```powershell
while ($running -and $taskIndex -lt $planData.Tasks.Count) {
    $currentTask = $planData.Tasks[$taskIndex].Number
    $binaryIndex = 0
    $taskSucceeded = $false

    while ($binaryIndex -lt $ClaudeBinaries.Count -and -not $taskSucceeded) {
        $activeClaude = $ClaudeBinaries[$binaryIndex]

        # Run task with current binary...
        # Check result

        if ($signals.AllPassed -or ($isCleanNoop -and $isLastTask)) {
            $taskSucceeded = $true
            $taskIndex++
        } else {
            $binaryIndex++  # Try next binary
        }
    }

    if (-not $taskSucceeded) {
        # All binaries exhausted for this task
        $running = $false
        $stopReason = "Task $currentTask failed after trying all binaries"
    }
}
```

### 3. Display Updates

**During Execution:**
- Show attempt number: `Task 3/10 (attempt 2/5 with claude_stable_any)`

**Final Report:**
- List all binaries that were available
- Show which binary succeeded for each task (or "all failed")

## Error Handling

| Scenario | Action |
|----------|--------|
| Task succeeds | Advance to next task, reset binaryIndex to 0 |
| Task fails, more binaries available | Log failure, increment binaryIndex, retry same task |
| Task fails, no more binaries | Stop execution, report failure |
| User Ctrl+C | Cancel current task, stop entire run |

## Backward Compatibility

- Existing commands with 1-2 binaries continue to work
- `MaxFailures` parameter kept but deprecated (emit warning if used)
- Default behavior changes: previously 2 tries with 1 binary, now 1 try with 1 binary

## Testing Strategy

1. **Unit tests** (`tests/args.Tests.ps1`):
   - Parse 1, 2, 3, 4, 5 binaries
   - Reject 6+ binaries
   - Reject 0 binaries

2. **Integration tests**:
   - Mock failing task, verify all binaries tried
   - Mock success on 2nd binary, verify task advances
   - Verify binary index resets for each new task

## Files to Modify

- `auto-execute.ps1` — main execution loop
- `src/args.ps1` — argument parsing
- `src/format.ps1` — display formatting (if needed for attempt counter)
- `tests/args.Tests.ps1` — update tests
