# Smart Dirty Tree Guard Implementation Plan

**Goal:** Replace naive dirty-tree failures with state-aware cleanup that distinguishes success-with-debris from actual failures.
**Architecture:** Add `Invoke-TreeCleanup` function to `src/preflight.ps1` that returns action objects based on commit/dirty state, then integrate into the main loop in `auto-execute.ps1`.
**Tech Stack:** PowerShell 7, Pester 5, Git CLI

---

## File Structure

| File | Action | Purpose |
|------|--------|---------|
| `src/preflight.ps1` | Modify | Add `Invoke-TreeCleanup` function |
| `tests/preflight.Tests.ps1` | Modify | Add tests for `Invoke-TreeCleanup` |
| `auto-execute.ps1` | Modify | Replace dirty-tree handling with smart guard logic |

---

### Task 1: Add Invoke-TreeCleanup Function

**Files:**
- Modify: `src/preflight.ps1`
- Test: `tests/preflight.Tests.ps1`

- [ ] Step 1: Write failing test for clean tree (no-op case)

Add to `tests/preflight.Tests.ps1` after the `Test-TaskSuccess` describe block:

```powershell
Describe "Invoke-TreeCleanup" {
    It "Returns NONE when tree is clean" {
        $result = Invoke-TreeCleanup -NewCommit $true -CleanTree $true -GitStatus "" -TaskNumber 1
        $result.Action | Should -Be "NONE"
        $result.Message | Should -Be "Tree clean"
    }
}
```

- [ ] Step 2: Run test to verify it fails

Run: `pwsh -Command "Invoke-Pester tests/preflight.Tests.ps1 -Output Detailed"`
Expected: FAIL with "Invoke-TreeCleanup: The term 'Invoke-TreeCleanup' is not recognized"

- [ ] Step 3: Write minimal implementation for clean tree case

Add to end of `src/preflight.ps1`:

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
}
```

- [ ] Step 4: Run test to verify it passes

Run: `pwsh -Command "Invoke-Pester tests/preflight.Tests.ps1 -Output Detailed"`
Expected: PASS

- [ ] Step 5: Commit

```bash
git add -A && git commit -m "feat(preflight): add Invoke-TreeCleanup function with NONE case"
```

---

### Task 2: Add Cleaned Case (Success with Debris)

**Files:**
- Modify: `src/preflight.ps1`
- Test: `tests/preflight.Tests.ps1`

- [ ] Step 1: Write failing test for success-with-debris case

Add to `tests/preflight.Tests.ps1` inside the `Invoke-TreeCleanup` describe block:

```powershell
    It "Cleans debris after successful commit (NewCommit=true, CleanTree=false)" {
        Mock git {
            if ($args[0] -eq 'clean') {
                return "Removing backup.txt"
            }
        }

        $result = Invoke-TreeCleanup -NewCommit $true -CleanTree $false -GitStatus "?? backup.txt" -TaskNumber 1

        $result.Action | Should -Be "CLEANED"
        $result.Message | Should -Be "Removed untracked debris after successful commit"
        $result.Details | Should -Be "Removing backup.txt"
    }
```

- [ ] Step 2: Run test to verify it fails

Run: `pwsh -Command "Invoke-Pester tests/preflight.Tests.ps1 -Output Detailed"`
Expected: FAIL with "Action: Should -Be 'CLEANED'"

- [ ] Step 3: Write implementation for success-with-debris case

Update `src/preflight.ps1` function:

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
}
```

- [ ] Step 4: Run test to verify it passes

Run: `pwsh -Command "Invoke-Pester tests/preflight.Tests.ps1 -Output Detailed"`
Expected: PASS

- [ ] Step 5: Commit

```bash
git add -A && git commit -m "feat(preflight): add CLEANED case for success-with-debris"
```

---

### Task 3: Add Reset Case (Failure with Debris)

**Files:**
- Modify: `src/preflight.ps1`
- Test: `tests/preflight.Tests.ps1`

- [ ] Step 1: Write failing test for failure-with-debris case

Add to `tests/preflight.Tests.ps1` inside the `Invoke-TreeCleanup` describe block:

```powershell
    It "Resets after failed task with debris (NewCommit=false, CleanTree=false)" {
        Mock git {
            if ($args[0] -eq 'reset') {
                return "HEAD is now at abc1234"
            }
            if ($args[0] -eq 'clean') {
                return ""
            }
        }

        $result = Invoke-TreeCleanup -NewCommit $false -CleanTree $false -GitStatus "M file.txt" -TaskNumber 1

        $result.Action | Should -Be "RESET"
        $result.Message | Should -Be "Hard reset to HEAD after failed task"
    }
```

- [ ] Step 2: Run test to verify it fails

Run: `pwsh -Command "Invoke-Pester tests/preflight.Tests.ps1 -Output Detailed"`
Expected: FAIL with "Action: Should -Be 'RESET'"

- [ ] Step 3: Write implementation for failure-with-debris case

Update `src/preflight.ps1` function:

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
```

- [ ] Step 4: Run test to verify it passes

Run: `pwsh -Command "Invoke-Pester tests/preflight.Tests.ps1 -Output Detailed"`
Expected: PASS

- [ ] Step 5: Commit

```bash
git add -A && git commit -m "feat(preflight): add RESET case for failure-with-debris"
```

---

### Task 4: Add Edge Case Tests

**Files:**
- Modify: `tests/preflight.Tests.ps1`

- [ ] Step 1: Write failing test for CLEAN_FAILED case

Add to `tests/preflight.Tests.ps1` inside the `Invoke-TreeCleanup` describe block:

```powershell
    It "Reports CLEAN_FAILED when git clean fails" {
        Mock git {
            if ($args[0] -eq 'clean') {
                $global:LASTEXITCODE = 1
                return "fatal: not a git repository"
            }
        }

        $result = Invoke-TreeCleanup -NewCommit $true -CleanTree $false -GitStatus "?? backup.txt" -TaskNumber 1

        $result.Action | Should -Be "CLEAN_FAILED"
        $result.Message | Should -Match "git clean failed"
    }
```

- [ ] Step 2: Run test to verify it passes (implementation exists)

Run: `pwsh -Command "Invoke-Pester tests/preflight.Tests.ps1 -Output Detailed"`
Expected: PASS

- [ ] Step 3: Write failing test for RESET_FAILED case

Add to `tests/preflight.Tests.ps1` inside the `Invoke-TreeCleanup` describe block:

```powershell
    It "Reports RESET_FAILED when git reset fails" {
        Mock git {
            if ($args[0] -eq 'reset') {
                $global:LASTEXITCODE = 1
                return "fatal: ambiguous argument 'HEAD'"
            }
            if ($args[0] -eq 'clean') {
                $global:LASTEXITCODE = 0
                return ""
            }
        }

        $result = Invoke-TreeCleanup -NewCommit $false -CleanTree $false -GitStatus "M file.txt" -TaskNumber 1

        $result.Action | Should -Be "RESET_FAILED"
        $result.Message | Should -Match "Reset failed"
    }
```

- [ ] Step 4: Run test to verify it passes (implementation exists)

Run: `pwsh -Command "Invoke-Pester tests/preflight.Tests.ps1 -Output Detailed"`
Expected: PASS

- [ ] Step 5: Commit

```bash
git add -A && git commit -m "test(preflight): add edge case tests for cleanup failures"
```

---

### Task 5: Integrate Smart Guard Logic into Main Loop

**Files:**
- Modify: `auto-execute.ps1`

- [ ] Step 1: Locate the failure handling block

The block to modify is in `auto-execute.ps1` around lines 230-280, starting with:
```powershell
} else {
    $consecutiveFailures++
```

And ending before:
```powershell
# Accumulate tokens into overall metrics
```

- [ ] Step 2: Replace the failure handling block with smart guard logic

Replace the entire `else` block (from `} else {` after the success path to the `# Accumulate tokens` comment) with:

```powershell
} else {
    # Task failed one or more signals - analyze and recover
    $consecutiveFailures++

    # --- Smart guard logic ---
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

        # Accumulate tokens before continuing
        $overallMetrics.Input += $taskTokens.Input
        $overallMetrics.Output += $taskTokens.Output
        $overallMetrics.CacheRead += $taskTokens.CacheRead
        $overallMetrics.CacheWrite += $taskTokens.CacheWrite
        $overallMetrics.CostUSD += $taskTokens.CostUSD
        if ($taskPeakContext -gt $overallPeakContext) {
            $overallPeakContext = $taskPeakContext
        }
        continue
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

        # Accumulate tokens before continuing
        $overallMetrics.Input += $taskTokens.Input
        $overallMetrics.Output += $taskTokens.Output
        $overallMetrics.CacheRead += $taskTokens.CacheRead
        $overallMetrics.CacheWrite += $taskTokens.CacheWrite
        $overallMetrics.CostUSD += $taskTokens.CostUSD
        if ($taskPeakContext -gt $overallPeakContext) {
            $overallPeakContext = $taskPeakContext
        }
        continue
    }

    # Failure with debris and reset failed: Stop execution
    if ($cleanup.Action -eq "RESET_FAILED") {
        $running = $false
        $stopReason = "Reset failed after dirty tree: $($cleanup.Message)"

        # Accumulate tokens before stopping
        $overallMetrics.Input += $taskTokens.Input
        $overallMetrics.Output += $taskTokens.Output
        $overallMetrics.CacheRead += $taskTokens.CacheRead
        $overallMetrics.CacheWrite += $taskTokens.CacheWrite
        $overallMetrics.CostUSD += $taskTokens.CostUSD
        if ($taskPeakContext -gt $overallPeakContext) {
            $overallPeakContext = $taskPeakContext
        }
        break
    }

    # RESET case or NONE with failure: Determine failure reasons and retry logic
    $failReasons = @()

    # Include specific error details if captured (e.g., max turns)
    if ($taskErrorDetails) {
        $failReasons += $taskErrorDetails
    } elseif (-not $signals.ExitOk) {
        $failReasons += "exit code $taskExitCode"
    }

    if (-not $signals.NewCommit) { $failReasons += "no new commit" }

    # Can retry with backup if: backup exists, not already using backup,
    # and not a context-limit kill
    $canRetry = $BackupClaudeBin -and (-not $useBackup) -and
                ($monitorResult.StopReason -notmatch "^Context limit")

    if ($monitorResult.StopReason -match "^Context limit") {
        $failReason = $monitorResult.StopReason
        $running = $false
    } else {
        $failReason = $failReasons -join ", "
    }

    $failSuffix = if ($canRetry) { "retrying with backup" } else { "STOPPED" }
    $entry = Format-TaskLogEntry -TaskNumber $currentTask -Passed $false `
        -Duration $taskDuration -FailReason $failReason -TokenString $tokenStr `
        -PeakContext $taskPeakContext -ContextLimit $ContextLimit `
        -ClaudeBin $activeClaude -FailSuffix $failSuffix
    Write-Host $entry -ForegroundColor Red
    $summaryEntries += $entry

    if ($canRetry) {
        # Backup available — retry same task with clean slate
        $useBackup = $true
        # Accumulate tokens from this attempt before retrying
        $overallMetrics.Input += $taskTokens.Input
        $overallMetrics.Output += $taskTokens.Output
        $overallMetrics.CacheRead += $taskTokens.CacheRead
        $overallMetrics.CacheWrite += $taskTokens.CacheWrite
        $overallMetrics.CostUSD += $taskTokens.CostUSD
        if ($taskPeakContext -gt $overallPeakContext) {
            $overallPeakContext = $taskPeakContext
        }
        continue
    }

    # No backup available or backup already tried — stop
    $running = $false
    $stopReason = "Task failed: $failReason"

    if ($consecutiveFailures -ge $MaxFailures) {
        $stopReason = "Max failures reached ($MaxFailures consecutive)"
    }
}
```

- [ ] Step 3: Remove the now-redundant `Save-DirtyState` function from preflight.ps1

The `Save-DirtyState` function is replaced by `Invoke-TreeCleanup`. Remove it from `src/preflight.ps1`:

Delete these lines:
```powershell
function Save-DirtyState {
    param(
        [int]$TaskNumber
    )

    git reset --hard HEAD 2>&1
    git clean -fd 2>&1
    return $LASTEXITCODE -eq 0
}
```

- [ ] Step 4: Remove the Save-DirtyState test if it exists

Check `tests/preflight.Tests.ps1` for any `Save-DirtyState` tests and remove them.

- [ ] Step 5: Run all tests to verify integration

Run: `pwsh -Command "Invoke-Pester tests/preflight.Tests.ps1 -Output Detailed"`
Expected: All tests PASS

- [ ] Step 6: Commit

```bash
git add -A && git commit -m "feat(auto-execute): integrate smart dirty tree guard logic"
```

---

### Task 6: Add Integration Test for Decision Matrix

**Files:**
- Modify: `tests/preflight.Tests.ps1`

- [ ] Step 1: Add comprehensive decision matrix tests

Add to `tests/preflight.Tests.ps1` inside the `Invoke-TreeCleanup` describe block:

```powershell
    Context "Decision Matrix" {
        It "ExitOk=true, NewCommit=true, CleanTree=false => CLEANED" {
            Mock git { return "Removing backup.txt" }

            $result = Invoke-TreeCleanup -NewCommit $true -CleanTree $false -GitStatus "?? backup.txt" -TaskNumber 1
            $result.Action | Should -Be "CLEANED"
        }

        It "ExitOk=false, NewCommit=true, CleanTree=false => CLEANED (exit code ignored if commit exists)" {
            Mock git { return "Removing backup.txt" }

            $result = Invoke-TreeCleanup -NewCommit $true -CleanTree $false -GitStatus "?? backup.txt" -TaskNumber 1
            $result.Action | Should -Be "CLEANED"
        }

        It "ExitOk=true, NewCommit=false, CleanTree=false => RESET (dirty tree, no commit)" {
            Mock git {
                if ($args[0] -eq 'reset') { return "HEAD is now at abc1234" }
                if ($args[0] -eq 'clean') { return "" }
            }

            $result = Invoke-TreeCleanup -NewCommit $false -CleanTree $false -GitStatus "M file.txt" -TaskNumber 1
            $result.Action | Should -Be "RESET"
        }

        It "ExitOk=false, NewCommit=false, CleanTree=false => RESET (total failure)" {
            Mock git {
                if ($args[0] -eq 'reset') { return "HEAD is now at abc1234" }
                if ($args[0] -eq 'clean') { return "" }
            }

            $result = Invoke-TreeCleanup -NewCommit $false -CleanTree $false -GitStatus "M file.txt" -TaskNumber 1
            $result.Action | Should -Be "RESET"
        }

        It "ExitOk=true, NewCommit=false, CleanTree=true => NONE (clean no-op)" {
            $result = Invoke-TreeCleanup -NewCommit $false -CleanTree $true -GitStatus "" -TaskNumber 1
            $result.Action | Should -Be "NONE"
        }
    }
```

- [ ] Step 2: Run all tests to verify

Run: `pwsh -Command "Invoke-Pester tests/preflight.Tests.ps1 -Output Detailed"`
Expected: All tests PASS

- [ ] Step 3: Commit

```bash
git add -A && git commit -m "test(preflight): add decision matrix integration tests"
```

---

### Task 7: Run Full Test Suite and Verify

**Files:**
- None (verification only)

- [ ] Step 1: Run all tests in the project

Run: `pwsh -Command "Invoke-Pester tests/ -Output Detailed"`
Expected: All tests PASS

- [ ] Step 2: Verify the design goals are met

Manual verification checklist:
1. `Invoke-TreeCleanup` exists in `src/preflight.ps1`
2. Function returns correct action for all 4 state combinations
3. `Save-DirtyState` is removed (replaced by `Invoke-TreeCleanup`)
4. Main loop in `auto-execute.ps1` uses `Invoke-TreeCleanup` for dirty tree handling
5. Success-with-debris cases continue execution (CLEANED, CLEAN_FAILED)
6. Failure-with-debris cases reset and retry (RESET, RESET_FAILED)
7. No filesystem-level cleanup (`rm`, `Remove-Item`) - only `git clean -fd` and `git reset --hard HEAD`

- [ ] Step 3: Final commit if any cleanup needed

```bash
git add -A && git commit -m "chore: final cleanup for smart dirty tree guard"
```

---

## Summary

| Task | Description | Files Changed |
|------|-------------|---------------|
| 1 | Add Invoke-TreeCleanup function (NONE case) | `src/preflight.ps1`, `tests/preflight.Tests.ps1` |
| 2 | Add CLEANED case (success-with-debris) | `src/preflight.ps1`, `tests/preflight.Tests.ps1` |
| 3 | Add RESET case (failure-with-debris) | `src/preflight.ps1`, `tests/preflight.Tests.ps1` |
| 4 | Add edge case tests | `tests/preflight.Tests.ps1` |
| 5 | Integrate into main loop | `auto-execute.ps1`, `src/preflight.ps1` |
| 6 | Add decision matrix tests | `tests/preflight.Tests.ps1` |
| 7 | Run full test suite | None |

## Success Criteria Verification

After implementation:
- [ ] Task that commits successfully but leaves backup files → auto-cleaned, continues
- [ ] Task that fails with dirty tree → reset, retry with backup
- [ ] No `rm`/`Remove-Item` in cleanup logic
- [ ] All cleanup via `git clean -fd` and `git reset --hard HEAD`