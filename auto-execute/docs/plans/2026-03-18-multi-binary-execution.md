# Multi-Binary Execution Implementation Plan

**Goal:** Support 1-5 Claude binaries with each getting exactly one attempt per task, removing the MaxFailures limit.
**Architecture:** Replace MainClaude/BackupClaude with ClaudeBinaries array, track binaryIndex per task instead of consecutiveFailures.
**Tech Stack:** PowerShell, Pester (testing framework)

---

### File Structure Overview

- **Modify:** `src/args.ps1` — Change return from MainClaude/BackupClaude to ClaudeBinaries array (1-5 items)
- **Modify:** `auto-execute.ps1` — Replace consecutiveFailures/useBackup with binaryIndex loop
- **Modify:** `src/format.ps1` — Add attempt counter display to Format-TaskLogEntry
- **Modify:** `tests/args.Tests.ps1` — Update tests for new return structure

---

### Task 1: Update Argument Parsing to Support Array of Binaries

**Files:**
- Modify: `src/args.ps1`
- Test: `tests/args.Tests.ps1`

**Common Pitfalls:**
- Keep backward compatibility: scripts using MainClaude should still work (but we return ClaudeBinaries instead)
- Validation changes from "max 2" to "max 5"
- Ensure PlanInput and StartTask parsing remains unchanged

---

- [ ] Step 1: Write the failing test for 3-5 binary support

```powershell
# tests/args.Tests.ps1 - add new tests after existing ones
It "parses three claude binaries and plan" {
    $result = Split-AxeArguments -Arguments @("claude_a", "claude_b", "claude_c", "my-plan")
    $result.ClaudeBinaries.Count | Should -Be 3
    $result.ClaudeBinaries[0] | Should -Be "claude_a"
    $result.ClaudeBinaries[1] | Should -Be "claude_b"
    $result.ClaudeBinaries[2] | Should -Be "claude_c"
    $result.PlanInput | Should -Be "my-plan"
    $result.StartTask | Should -Be 0
}

It "parses five claude binaries and plan" {
    $result = Split-AxeArguments -Arguments @("claude_a", "claude_b", "claude_c", "claude_d", "claude_e", "my-plan")
    $result.ClaudeBinaries.Count | Should -Be 5
    $result.ClaudeBinaries[4] | Should -Be "claude_e"
    $result.PlanInput | Should -Be "my-plan"
}

It "throws when more than 5 claude binaries are provided" {
    { Split-AxeArguments -Arguments @("claude_a", "claude_b", "claude_c", "claude_d", "claude_e", "claude_f", "my-plan") } |
        Should -Throw "*max 5*"
}
```

- [ ] Step 2: Run tests to verify they fail

Run: `Invoke-Pester -Path "tests/args.Tests.ps1" -TestName "parses three claude binaries and plan", "parses five claude binaries and plan", "throws when more than 5 claude binaries are provided" -Output Detailed`

Expected: FAIL — "ClaudeBinaries" property not found, or "max 2" validation error

- [ ] Step 3: Update implementation to return array and support up to 5

```powershell
# src/args.ps1 — replace the entire return statement and validation

function Split-AxeArguments {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $claudeBinaries = @()
    $otherArgs = @()
    $startTask = 0

    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        $arg = $Arguments[$i]
        if ($arg -match '^--?Start-?task$' -and ($i + 1) -lt $Arguments.Count -and $Arguments[$i + 1] -match '^\d+$') {
            $startTask = [int]$Arguments[$i + 1]
            $i++
        } elseif ($arg -match '^claude') {
            $claudeBinaries += $arg
        } elseif ($arg -match '^\d+$') {
            $startTask = [int]$arg
        } else {
            $otherArgs += $arg
        }
    }

    if ($claudeBinaries.Count -eq 0) {
        throw "No claude binary specified. At least one argument must start with 'claude'."
    }
    if ($claudeBinaries.Count -gt 5) {
        throw "Too many claude binaries specified (max 5). Got: $($claudeBinaries -join ', ')"
    }
    if ($otherArgs.Count -eq 0) {
        throw "No plan argument found. One non-claude argument is required."
    }
    if ($otherArgs.Count -gt 1) {
        throw "Too many non-claude arguments (max 1). Got: $($otherArgs -join ', ')"
    }

    return @{
        ClaudeBinaries = $claudeBinaries  # Array of 1-5 binaries
        PlanInput      = $otherArgs[0]
        StartTask      = $startTask
    }
}
```

- [ ] Step 4: Update existing tests to use new property names

```powershell
# tests/args.Tests.ps1 — update all existing tests

# Change from:
# $result.MainClaude | Should -Be "claude_stable_ali"
# $result.BackupClaude | Should -BeNull

# To:
# $result.ClaudeBinaries.Count | Should -Be 1
# $result.ClaudeBinaries[0] | Should -Be "claude_stable_ali"

# Update "parses single claude binary and plan"
It "parses single claude binary and plan" {
    $result = Split-AxeArguments -Arguments @("claude_stable_ali", "mask-endpoint")
    $result.ClaudeBinaries.Count | Should -Be 1
    $result.ClaudeBinaries[0] | Should -Be "claude_stable_ali"
    $result.PlanInput | Should -Be "mask-endpoint"
    $result.StartTask | Should -Be 0
}

# Update "parses two claude binaries and plan"
It "parses two claude binaries and plan" {
    $result = Split-AxeArguments -Arguments @("claude_stable_ali", "claude_stable_any", "mask-endpoint")
    $result.ClaudeBinaries.Count | Should -Be 2
    $result.ClaudeBinaries[0] | Should -Be "claude_stable_ali"
    $result.ClaudeBinaries[1] | Should -Be "claude_stable_any"
    $result.PlanInput | Should -Be "mask-endpoint"
    $result.StartTask | Should -Be 0
}

# Update "handles plan argument between claude binaries"
It "handles plan argument between claude binaries" {
    $result = Split-AxeArguments -Arguments @("claude_stable_ali", "mask-endpoint", "claude_stable_any")
    $result.ClaudeBinaries.Count | Should -Be 2
    $result.ClaudeBinaries[0] | Should -Be "claude_stable_ali"
    $result.ClaudeBinaries[1] | Should -Be "claude_stable_any"
    $result.PlanInput | Should -Be "mask-endpoint"
}

# Update "matches claude prefix case-insensitively"
It "matches claude prefix case-insensitively" {
    $result = Split-AxeArguments -Arguments @("Claude_Stable", "my-plan")
    $result.ClaudeBinaries.Count | Should -Be 1
    $result.ClaudeBinaries[0] | Should -Be "Claude_Stable"
    $result.PlanInput | Should -Be "my-plan"
}

# Update "handles bare claude binary name"
It "handles bare claude binary name" {
    $result = Split-AxeArguments -Arguments @("claude", "my-plan")
    $result.ClaudeBinaries.Count | Should -Be 1
    $result.ClaudeBinaries[0] | Should -Be "claude"
    $result.PlanInput | Should -Be "my-plan"
}

# Remove the old "throws when more than 2 claude binaries" test (replaced by 5-binary test)
# Remove: It "throws when more than 2 claude binaries are provided" { ... }

# Update remaining tests similarly for ClaudeBinaries[0] access
It "parses bare numeric argument as StartTask" {
    $result = Split-AxeArguments -Arguments @("claude_stable_kimi", "claude_stable_glm", "latest", "12")
    $result.ClaudeBinaries.Count | Should -Be 2
    $result.ClaudeBinaries[0] | Should -Be "claude_stable_kimi"
    $result.ClaudeBinaries[1] | Should -Be "claude_stable_glm"
    $result.PlanInput | Should -Be "latest"
    $result.StartTask | Should -Be 12
}

It "parses --Start-task flag as StartTask" {
    $result = Split-AxeArguments -Arguments @("claude_stable_kimi", "claude_stable_glm", "latest", "--Start-task", "12")
    $result.ClaudeBinaries.Count | Should -Be 2
    $result.ClaudeBinaries[0] | Should -Be "claude_stable_kimi"
    $result.ClaudeBinaries[1] | Should -Be "claude_stable_glm"
    $result.PlanInput | Should -Be "latest"
    $result.StartTask | Should -Be 12
}

It "parses -StartTask flag as StartTask" {
    $result = Split-AxeArguments -Arguments @("claude_a", "my-plan", "-StartTask", "5")
    $result.ClaudeBinaries.Count | Should -Be 1
    $result.ClaudeBinaries[0] | Should -Be "claude_a"
    $result.PlanInput | Should -Be "my-plan"
    $result.StartTask | Should -Be 5
}
```

- [ ] Step 5: Run all tests to verify they pass

Run: `Invoke-Pester -Path "tests/args.Tests.ps1" -Output Detailed`

Expected: All 14 tests PASS

- [ ] Step 6: Commit

```bash
git add src/args.ps1 tests/args.Tests.ps1
git commit -m "feat: support 1-5 claude binaries in argument parsing"
```

---

### Task 2: Update Format-TaskLogEntry to Show Attempt Info

**Files:**
- Modify: `src/format.ps1`
- Test: (no tests exist for format.ps1, manual verification)

---

- [ ] Step 1: Add AttemptNumber and TotalBinaries parameters

```powershell
# src/format.ps1 — update Format-TaskLogEntry function signature

function Format-TaskLogEntry {
    param(
        [int]$TaskNumber,
        [bool]$Passed,
        [string]$CommitHash,
        [TimeSpan]$Duration,
        [string]$FailReason,
        [string]$TokenString = "",
        [int]$PeakContext = 0,
        [int]$ContextLimit = 0,
        [string]$ClaudeBin = "",
        [string]$FailSuffix = "STOPPED",
        [int]$AttemptNumber = 0,      # NEW: 1-based attempt number
        [int]$TotalBinaries = 0       # NEW: total binaries available
    )

    $timestamp = Get-Date -Format "HH:mm:ss"
    $durationStr = "{0}m {1:D2}s" -f [math]::Floor($Duration.TotalMinutes), $Duration.Seconds
    $ctxStr = ""
    if ($PeakContext -gt 0 -and $ContextLimit -gt 0) {
        $ctxStr = " | Peak ctx: $(Format-ContextSize $PeakContext)/$(Format-ContextSize $ContextLimit)"
    }

    # NEW: Build attempt info for display
    $attemptStr = ""
    if ($AttemptNumber -gt 0 -and $TotalBinaries -gt 0) {
        $attemptStr = " (attempt $AttemptNumber/$TotalBinaries)"
    }

    $binTag = if ($ClaudeBin) { " [$ClaudeBin]$attemptStr" } else { "" }

    if ($Passed) {
        $shortHash = if ($CommitHash.Length -ge 7) { $CommitHash.Substring(0, 7) } else { $CommitHash }
        return "[$timestamp] Task ${TaskNumber}: PASS$binTag (commit $shortHash, $durationStr)$ctxStr$TokenString"
    } else {
        return "[$timestamp] Task ${TaskNumber}: FAIL$binTag ($FailReason) — $FailSuffix$ctxStr$TokenString"
    }
}
```

- [ ] Step 2: Verify syntax is valid

Run: `powershell -Command "Get-Command Format-TaskLogEntry"`

Expected: Command found (no syntax errors)

- [ ] Step 3: Commit

```bash
git add src/format.ps1
git commit -m "feat: add attempt counter to Format-TaskLogEntry"
```

---

### Task 3: Update Main Execution Loop for Binary Array

**Files:**
- Modify: `auto-execute.ps1`

**Common Pitfalls:**
- Remove `$consecutiveFailures` and `$useBackup` variables entirely
- `$binaryIndex` must reset to 0 for each new task
- Update all references from `$ClaudeBin` to `$ClaudeBinaries[0]` for pre-flight
- Update all Format-TaskLogEntry calls to include AttemptNumber/TotalBinaries
- Keep `$MaxFailures` parameter for backward compatibility but add deprecation warning

---

- [ ] Step 1: Update argument extraction and add deprecation warning

```powershell
# auto-execute.ps1 — after Phase 0, replace the argument extraction section

# --- Phase 0: Parse arguments ---
$parsed = Split-AxeArguments -Arguments $Arguments
$ClaudeBinaries = $parsed.ClaudeBinaries  # Array of 1-5 binaries
$Plan = Resolve-PlanPath -PlanInput $parsed.PlanInput
if ($parsed.StartTask -gt 0 -and $StartTask -eq 0) {
    $StartTask = $parsed.StartTask
}

# DEPRECATED: MaxFailures is no longer used (each binary gets 1 try)
if ($MaxFailures -ne 2) {  # 2 is the default, so if it's different, user specified it
    Write-Host "WARNING: -MaxFailures parameter is deprecated. Each binary gets exactly 1 attempt." -ForegroundColor Yellow
}
```

- [ ] Step 2: Update pre-flight check to use first binary

```powershell
# auto-execute.ps1 — Phase 1a

# --- Phase 1a: Pre-flight (before hooks) ---
$errors = Test-PreFlightEarly -ClaudeBin $ClaudeBinaries[0] -PlanPath $Plan
# Validate all binaries exist
for ($i = 1; $i -lt $ClaudeBinaries.Count; $i++) {
    if (-not (Get-Command $ClaudeBinaries[$i] -ErrorAction SilentlyContinue)) {
        $errors += "CLI binary '$($ClaudeBinaries[$i])' (index $i) not found in PATH."
    }
}
if ($errors.Count -gt 0) {
    Write-Host "Pre-flight checks failed:" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}
```

- [ ] Step 3: Update header output to show all binaries

```powershell
# auto-execute.ps1 — after "Starting auto-execute" section

$binariesStr = $ClaudeBinaries -join ", "
$ctxLimitStr = Format-ContextSize $ContextLimit
Write-Host "CLI binaries: $binariesStr | MaxTurns: $MaxTurns | Timeout: ${TaskTimeout}s | ContextLimit: $ctxLimitStr" -ForegroundColor Cyan
```

- [ ] Step 4: Replace main loop with binary-index-based retry logic

```powershell
# auto-execute.ps1 --- Phase 3: Main Loop ---
# Replace the entire Phase 3 section

$running = $true
# REMOVED: $consecutiveFailures = 0
$completedCount = 0
# REMOVED: $useBackup = $false
$overallStart = [System.Diagnostics.Stopwatch]::StartNew()
$runTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$summaryLogPath = Join-Path $LogDir "run-$runTimestamp.log"
$summaryEntries = @()
$stopReason = "Unknown"
$overallMetrics = @{ Input=0; Output=0; CacheRead=0; CacheWrite=0; Total=0; HitRate=0; CostUSD=0 }
$overallPeakContext = 0

# Reclaim Ctrl+C from child process
$originalTreatCtrlC = $false
try { $originalTreatCtrlC = [Console]::TreatControlCAsInput; [Console]::TreatControlCAsInput = $true } catch { }

Write-Host "Press Ctrl+C, Escape, or Q to cancel a running task." -ForegroundColor DarkGray

$emptyStdinPath = [System.IO.Path]::GetTempFileName()

try {
    while ($running -and $taskIndex -lt $planData.Tasks.Count) {
        $currentTask = $planData.Tasks[$taskIndex].Number
        $binaryIndex = 0          # NEW: Track which binary we're using
        $taskSucceeded = $false   # NEW: Track if task succeeded

        # NEW: Inner loop tries each binary until one succeeds or all fail
        while ($binaryIndex -lt $ClaudeBinaries.Count -and $taskSucceeded -eq $false) {
            $activeClaude = $ClaudeBinaries[$binaryIndex]
            $attemptNumber = $binaryIndex + 1  # 1-based for display

            # Record baseline
            $beforeHash = (git rev-parse HEAD 2>&1).ToString().Trim()
            $taskStart = [System.Diagnostics.Stopwatch]::StartNew()
            $taskTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
            $taskLogPath = Join-Path $LogDir "task-$currentTask-$taskTimestamp.log"

            Write-Host "`n--- Task $currentTask/$totalTasks (attempt $attemptNumber/$($ClaudeBinaries.Count) with $activeClaude) ---" -ForegroundColor Cyan

            # Write per-task temp file
            $tempTaskPath = Write-TaskTempFile -LogDir $LogDir -TaskNumber $currentTask `
                -TaskContent $planData.Tasks[$taskIndex].Content `
                -Preamble $planData.Preamble -PlanPath $Plan

            # Build prompt and execute
            $claudeCmd = (Get-Command $activeClaude).Source
            $promptText = "/auto-execute $tempTaskPath"
            $claudeArgs = "-p `"$promptText`" --dangerously-skip-permissions --max-turns $MaxTurns --output-format stream-json --verbose"

            if ($claudeCmd -like '*.ps1') {
                $argString = "-NoProfile -File `"$claudeCmd`" $claudeArgs"
                $claudeCmd = "powershell"
            } else {
                $argString = $claudeArgs
            }

            $process = Start-Process -FilePath $claudeCmd `
                -ArgumentList $argString `
                -PassThru -NoNewWindow `
                -RedirectStandardInput $emptyStdinPath `
                -RedirectStandardOutput $taskLogPath `
                -RedirectStandardError "$taskLogPath.err"

            $monitorResult = Invoke-TaskMonitor -Process $process -TaskLogPath $taskLogPath `
                -TaskTimeout $TaskTimeout -ContextLimit $ContextLimit `
                -MaxTurns $MaxTurns -GitRoot $gitRoot -TaskNumber $currentTask

            $taskExitCode = $monitorResult.ExitCode
            $taskTokens = $monitorResult.Tokens
            $taskPeakContext = $monitorResult.PeakContext
            $taskSessionId = $monitorResult.SessionId
            $taskErrorDetails = $monitorResult.ErrorDetails
            $tokenStr = Format-TokenMetrics -Metrics $taskTokens

            # Check if run was cancelled
            if ($monitorResult.Cancelled -or $taskExitCode -eq 130 -or $taskExitCode -eq 3221225786) {
                $taskStart.Stop()
                Write-Host "`n[!] Run cancelled by user." -ForegroundColor Yellow
                $running = $false
                $stopReason = "Cancelled by user (Ctrl+C)"

                $overallMetrics.Input += $taskTokens.Input
                $overallMetrics.Output += $taskTokens.Output
                $overallMetrics.CacheRead += $taskTokens.CacheRead
                $overallMetrics.CacheWrite += $taskTokens.CacheWrite
                $overallMetrics.CostUSD += $taskTokens.CostUSD
                if ($taskPeakContext -gt $overallPeakContext) {
                    $overallPeakContext = $taskPeakContext
                }
                break  # Exit inner while
            }

            $taskStart.Stop()
            $taskDuration = $taskStart.Elapsed

            # Post-task verification
            $afterHash = (git rev-parse HEAD 2>&1).ToString().Trim()
            $gitStatus = (git status --porcelain 2>&1) -join ""

            $signals = Test-TaskSuccess -ExitCode $taskExitCode `
                -BeforeHash $beforeHash -AfterHash $afterHash -GitStatus $gitStatus

            $isCleanNoop = $signals.ExitOk -and $signals.CleanTree -and (-not $signals.NewCommit)
            $isLastTask = ($taskIndex -eq $planData.Tasks.Count - 1)

            if ($signals.AllPassed -or ($isCleanNoop -and $isLastTask)) {
                $taskSucceeded = $true
                $completedCount++
                $entry = Format-TaskLogEntry -TaskNumber $currentTask -Passed $true `
                    -CommitHash $afterHash -Duration $taskDuration -TokenString $tokenStr `
                    -PeakContext $taskPeakContext -ContextLimit $ContextLimit `
                    -ClaudeBin $activeClaude -AttemptNumber $attemptNumber -TotalBinaries $ClaudeBinaries.Count
                Write-Host $entry -ForegroundColor Green
                $summaryEntries += $entry
                # Task succeeded, will exit inner while and advance taskIndex
            } else {
                # Task failed - try next binary if available
                $failReasons = @()
                if ($taskErrorDetails) {
                    $failReasons += $taskErrorDetails
                } elseif (-not $signals.ExitOk) {
                    $failReasons += "exit code $taskExitCode"
                }
                if (-not $signals.NewCommit) { $failReasons += "no new commit" }
                if ($monitorResult.StopReason) { $failReasons += $monitorResult.StopReason }

                $failReason = $failReasons -join ", "

                # Determine if we have more binaries to try
                $hasMoreBinaries = ($binaryIndex + 1) -lt $ClaudeBinaries.Count
                $failSuffix = if ($hasMoreBinaries) { "trying next binary" } else { "STOPPED" }

                $entry = Format-TaskLogEntry -TaskNumber $currentTask -Passed $false `
                    -Duration $taskDuration -FailReason $failReason -TokenString $tokenStr `
                    -PeakContext $taskPeakContext -ContextLimit $ContextLimit `
                    -ClaudeBin $activeClaude -FailSuffix $failSuffix `
                    -AttemptNumber $attemptNumber -TotalBinaries $ClaudeBinaries.Count
                Write-Host $entry -ForegroundColor Red
                $summaryEntries += $entry

                # Accumulate tokens before potentially continuing
                $overallMetrics.Input += $taskTokens.Input
                $overallMetrics.Output += $taskTokens.Output
                $overallMetrics.CacheRead += $taskTokens.CacheRead
                $overallMetrics.CacheWrite += $taskTokens.CacheWrite
                $overallMetrics.CostUSD += $taskTokens.CostUSD
                if ($taskPeakContext -gt $overallPeakContext) {
                    $overallPeakContext = $taskPeakContext
                }

                if ($hasMoreBinaries) {
                    $binaryIndex++  # Try next binary (stay on same task)
                    continue
                } else {
                    # All binaries exhausted
                    $running = $false
                    $stopReason = "Task $currentTask failed after trying all $($ClaudeBinaries.Count) binaries"
                    break  # Exit inner while
                }
            }

            # Accumulate tokens for successful task
            $overallMetrics.Input += $taskTokens.Input
            $overallMetrics.Output += $taskTokens.Output
            $overallMetrics.CacheRead += $taskTokens.CacheRead
            $overallMetrics.CacheWrite += $taskTokens.CacheWrite
            $overallMetrics.CostUSD += $taskTokens.CostUSD
            if ($taskPeakContext -gt $overallPeakContext) {
                $overallPeakContext = $taskPeakContext
            }
        }

        if ($taskSucceeded) {
            $taskIndex++  # Advance to next task only after success
        }

        if (-not $running) {
            break  # Exit outer while if stopped
        }
    }

    if ($taskIndex -ge $planData.Tasks.Count -and $running) {
        $stopReason = "All tasks complete"
    }
} catch {
    $stopReason = "Error: $_"
} finally {
    # Restore console Ctrl+C behavior
    try { [Console]::TreatControlCAsInput = $originalTreatCtrlC } catch { }

    # Kill child process if still running
    if ($process -and -not $process.HasExited) {
        & taskkill /F /T /PID $process.Id 2>$null | Out-Null
        Write-Host "Killed running Claude process (PID $($process.Id))." -ForegroundColor Yellow
    }

    $overallStart.Stop()

    # Clean up temp stdin file
    if ($emptyStdinPath -and (Test-Path $emptyStdinPath)) {
        Remove-Item $emptyStdinPath -Force -ErrorAction SilentlyContinue
    }

    # Write summary log
    if ($summaryEntries.Count -gt 0) {
        $logParent = Split-Path $summaryLogPath -Parent
        if (-not (Test-Path $logParent)) {
            New-Item -ItemType Directory -Path $logParent -Force | Out-Null
        }
        $summaryEntries | Out-File -FilePath $summaryLogPath -Encoding UTF8
    }

    # Finalize overall token metrics
    $overallMetrics.Total = $overallMetrics.Input + $overallMetrics.Output + $overallMetrics.CacheRead
    $overallTotalInput = $overallMetrics.Input + $overallMetrics.CacheRead
    if ($overallTotalInput -gt 0) {
        $overallMetrics.HitRate = [math]::Round(($overallMetrics.CacheRead / $overallTotalInput) * 100, 1)
    }
    $overallTokenStr = Format-TokenMetrics -Metrics $overallMetrics

    # Final report
    $binariesLine = "Binaries: $($ClaudeBinaries -join ', ')"
    $report = Format-FinalReport -PlanPath $Plan -CompletedTasks $completedCount `
        -TotalTasks $totalTasks -TotalDuration $overallStart.Elapsed `
        -StopReason $stopReason -LogFile $summaryLogPath -TokenString $overallTokenStr `
        -MaxPeakContext $overallPeakContext -ContextLimit $ContextLimit `
        -NextTask $(if ($taskIndex -lt $planData.Tasks.Count) { $planData.Tasks[$taskIndex].Number } else { 0 })
    Write-Host "`n$report" -ForegroundColor Cyan
    Write-Host $binariesLine -ForegroundColor Cyan
}
```

- [ ] Step 5: Verify script loads without syntax errors

Run: `powershell -Command "Get-Command auto-execute.ps1"`

Expected: No syntax errors (may show file not found, that's OK)

- [ ] Step 6: Commit

```bash
git add auto-execute.ps1
git commit -m "feat: implement multi-binary execution with binary index retry"
```

---

### Task 4: Run Full Test Suite

**Files:**
- All modified files

---

- [ ] Step 1: Run all tests

Run: `Invoke-Pester -Path "tests" -Output Detailed`

Expected: All tests PASS

- [ ] Step 2: Commit

```bash
git add -A
git commit -m "test: verify all tests pass after multi-binary changes"
```

---

## Summary of Changes

| File | Change |
|------|--------|
| `src/args.ps1` | Return `ClaudeBinaries` array instead of `MainClaude`/`BackupClaude`, support up to 5 |
| `tests/args.Tests.ps1` | Update all tests for new property names, add 3-5 binary tests |
| `src/format.ps1` | Add `AttemptNumber` and `TotalBinaries` parameters to `Format-TaskLogEntry` |
| `auto-execute.ps1` | Replace `consecutiveFailures`/`useBackup` with `binaryIndex` inner loop, add deprecation warning |

## Usage After Implementation

```powershell
# 1 binary = 1 try per task
auto-execute claude_stable_kimi latest

# 3 binaries = 3 tries per task (1 each)
auto-execute claude_stable_kimi claude_stable_any claude-opus-4-6 latest

# 5 binaries = 5 tries per task (1 each)
auto-execute claude_stable_kimi claude_stable_any claude-opus-4-6 claude-sonnet-4-6 claude-haiku-4-5 latest
```
