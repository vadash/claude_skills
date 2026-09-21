# Smart Dirty Tree Guard

## Problem

Task execution leaves behind temporary files (backups, logs, temp artifacts) that cause "dirty tree" failures even when the task successfully committed its work. Current logic treats all dirty trees as failures, triggering unnecessary resets and retries.

## Example Failure Pattern

```
Task 2: SUCCESS (commit f2e0acc - vitest config updated)
         BUT vitest.config.js.backup exists (untracked)
Result: dirty tree → stash → retry → STOPPED
```

Both attempts failed because the backup file wasn't cleaned up, even though the actual work was committed.

## Solution: State-Aware Guard Logic

Distinguish between:
1. **Success with debris** (NewCommit=true, CleanTree=false) → Clean debris, continue
2. **Failure with debris** (NewCommit=false, CleanTree=false) → Reset, retry if possible
3. **Clean success** (NewCommit=true, CleanTree=true) → Continue
4. **Clean no-op** (NewCommit=false, CleanTree=true) → Continue (verification tasks)

## Design

### 1. Enhanced Test-TaskSuccess Output

`Test-TaskSuccess` already returns granular signals. No changes needed to this function.

Current output:
```powershell
$signals = @{
    ExitOk    = ($ExitCode -eq 0)
    NewCommit = ($AfterHash -ne $BeforeHash)
    CleanTree = ([string]::IsNullOrWhiteSpace($GitStatus))
    AllPassed = $signals.ExitOk -and $signals.NewCommit -and $signals.CleanTree
}
```

### 2. New Function: Invoke-TreeCleanup

Encapsulates safe cleanup operations based on task outcome.

```powershell
function Invoke-TreeCleanup {
    param(
        [bool]$NewCommit,
        [bool]$CleanTree,
        [string]$GitStatus,
        [int]$TaskNumber
    )

    # Nothing to clean
    if ($CleanTree) {
        return @{ Action = "NONE"; Message = "Tree clean" }
    }

    # Success with debris: Task committed but left temp files
    # Safe to clean - the real work is in git history
    if ($NewCommit) {
        # git clean -fd only removes untracked files (safe)
        # -f = force, -d = include directories
        $output = git clean -fd 2>&1
        if ($LASTEXITCODE -eq 0) {
            return @{
                Action = "CLEANED"
                Message = "Removed untracked debris after successful commit"
                Details = $output
            }
        }
        return @{
            Action = "CLEAN_FAILED"
            Message = "git clean failed: $output"
        }
    }

    # Failure with debris: Task failed, messy working tree
    # Need hard reset to get back to known good state
    if (-not $NewCommit) {
        # Reset to HEAD (discards tracked changes)
        $resetOutput = git reset --hard HEAD 2>&1
        $resetOk = $LASTEXITCODE -eq 0

        # Also clean untracked (in case reset left any)
        $cleanOutput = git clean -fd 2>&1
        $cleanOk = $LASTEXITCODE -eq 0

        if ($resetOk -and $cleanOk) {
            return @{
                Action = "RESET"
                Message = "Hard reset to HEAD after failed task"
                Details = "$resetOutput; $cleanOutput"
            }
        }
        return @{
            Action = "RESET_FAILED"
            Message = "Reset failed. Reset: $resetOutput; Clean: $cleanOutput"
        }
    }
}
```

**Safety guarantee**: Uses only `git clean -fd` and `git reset --hard HEAD` - both are git-contained operations that only affect the working tree, never the filesystem outside the repo.

### 3. Modified Main Loop Logic

Replace the current dirty tree handling (lines 268-290 in auto-execute.ps1):

```powershell
# Current logic:
if ($signals.AllPassed -or ($isCleanNoop -and $isLastTask)) {
    # Success path...
} else {
    # Failure path with dirty tree handling...
}

# New logic:
if ($signals.AllPassed -or ($isCleanNoop -and $isLastTask)) {
    # Task passed all signals - continue normally
    $consecutiveFailures = 0
    $completedCount++
    # ... logging ...
    $taskIndex++
}
else {
    # Task failed one or more signals - analyze and recover
    $consecutiveFailures++

    # --- NEW: Smart guard logic ---
    $cleanup = Invoke-TreeCleanup `
        -NewCommit $signals.NewCommit `
        -CleanTree $signals.CleanTree `
        -GitStatus $gitStatus `
        -TaskNumber $currentTask

    Write-Host "Task $currentTask cleanup: $($cleanup.Message)" -ForegroundColor Yellow

    # Success with debris: Cleaned up, treat as success
    if ($cleanup.Action -eq "CLEANED") {
        $consecutiveFailures = 0
        $completedCount++
        $useBackup = $false
        $entry = Format-TaskLogEntry -TaskNumber $currentTask -Passed $true `
            -CommitHash $afterHash -Duration $taskDuration -TokenString $tokenStr `
            -PeakContext $taskPeakContext -ContextLimit $ContextLimit `
            -ClaudeBin $activeClaude -PassSuffix "(auto-cleaned)"
        Write-Host $entry -ForegroundColor Green
        $summaryEntries += $entry
        $taskIndex++
        continue  # Skip normal failure handling
    }

    # Success with debris but cleanup failed: Log warning, continue as success
    if ($cleanup.Action -eq "CLEAN_FAILED") {
        $consecutiveFailures = 0
        $completedCount++
        $useBackup = $false
        $entry = Format-TaskLogEntry -TaskNumber $currentTask -Passed $true `
            -CommitHash $afterHash -Duration $taskDuration -TokenString $tokenStr `
            -PeakContext $taskPeakContext -ContextLimit $ContextLimit `
            -ClaudeBin $activeClaude -PassSuffix "(cleanup failed)"
        Write-Host $entry -ForegroundColor Yellow
        Write-Host "Warning: Cleanup failed for task $currentTask. Manual intervention may be needed." -ForegroundColor Yellow
        $summaryEntries += $entry
        $taskIndex++
        continue
    }

    # Failure with debris: Already reset, decide on retry
    if ($cleanup.Action -eq "RESET") {
        # Fall through to retry logic below
    }

    # Failure with debris and reset failed: Stop execution
    if ($cleanup.Action -eq "RESET_FAILED") {
        $running = $false
        $stopReason = "Reset failed after dirty tree: $($cleanup.Message)"
        break
    }
    # --- END NEW ---

    # Determine failure reasons (existing logic)
    $failReasons = @()
    if ($taskErrorDetails) {
        $failReasons += $taskErrorDetails
    } elseif (-not $signals.ExitOk) {
        $failReasons += "exit code $taskExitCode"
    }
    if (-not $signals.NewCommit) { $failReasons += "no new commit" }
    if (-not $signals.CleanTree) { $failReasons += "dirty tree" }

    # Retry logic (existing)
    $canRetry = $BackupClaudeBin -and (-not $useBackup) -and
                ($monitorResult.StopReason -notmatch "^Context limit")

    if ($canRetry) {
        $useBackup = $true
        # Accumulate tokens...
        continue
    }

    # Max failures check (existing)
    if ($consecutiveFailures -ge $MaxFailures) {
        $running = $false
        $stopReason = "Max failures reached ($MaxFailures consecutive)"
    }
}
```

## Decision Matrix

| ExitOk | NewCommit | CleanTree | Action | Logic |
|--------|-----------|-----------|--------|-------|
| ✓ | ✓ | ✓ | Success | All signals pass |
| ✓ | ✓ | ✗ | **Auto-clean** | Success but temp files left → `git clean -fd` → continue |
| ✗ | ✓ | ✓ | Success | Exit failed but commit made (edge case) |
| ✗ | ✓ | ✗ | **Auto-clean** | Exit failed but commit made → clean, continue |
| ✓ | ✗ | ✓ | Success | Clean no-op (verification task) |
| ✓ | ✗ | ✗ | Reset+Retry | Dirty tree, no commit → reset, retry with backup |
| ✗ | ✗ | ✓ | Retry | Failed but clean → retry with backup |
| ✗ | ✗ | ✗ | Reset+Retry | Failed with debris → reset, retry with backup |

## Safety Guarantees

1. **`git clean -fd`** only removes untracked files/directories
   - Never touches tracked files
   - Never modifies git history
   - Confined to repository directory

2. **`git reset --hard HEAD`** only affects working tree
   - Resets to committed state at HEAD
   - Does not modify history (no --force needed)
   - Confined to repository directory

3. **No `rm -rf`** or filesystem-level operations
   - All cleanup through git commands
   - Git's safety mechanisms apply

## Testing Strategy

Add tests to `tests/preflight.Tests.ps1`:

```powershell
Describe "Invoke-TreeCleanup" {
    It "Returns NONE when tree is clean" {
        # Mock git status returns empty
        $result = Invoke-TreeCleanup -NewCommit $true -CleanTree $true -GitStatus "" -TaskNumber 1
        $result.Action | Should -Be "NONE"
    }

    It "Cleans debris after successful commit" {
        # Mock git clean -fd success
        $result = Invoke-TreeCleanup -NewCommit $true -CleanTree $false -GitStatus "?? backup.txt" -TaskNumber 1
        $result.Action | Should -Be "CLEANED"
        # Verify git clean -fd was called
    }

    It "Resets after failed task with debris" {
        # Mock git reset --hard and git clean -fd success
        $result = Invoke-TreeCleanup -NewCommit $false -CleanTree $false -GitStatus "M file.txt" -TaskNumber 1
        $result.Action | Should -Be "RESET"
        # Verify both commands were called
    }

    It "Reports failure when git commands fail" {
        # Mock git clean failure
        $result = Invoke-TreeCleanup -NewCommit $true -CleanTree $false -GitStatus "?? backup.txt" -TaskNumber 1
        $result.Action | Should -Be "CLEAN_FAILED"
    }
}
```

## Files Modified

| File | Change |
|------|--------|
| `src/preflight.ps1` | Add `Invoke-TreeCleanup` function |
| `auto-execute.ps1` | Replace dirty tree handling with guard logic |
| `tests/preflight.Tests.ps1` | Add tests for `Invoke-TreeCleanup` |

## Success Criteria

- Task 2 scenario succeeds: commit exists + backup file → cleaned automatically, continues
- No false "dirty tree" failures when work was actually committed
- Zero filesystem-level operations (`rm`, `Remove-Item`)
- All cleanup via `git clean -fd` and `git reset --hard HEAD` only
