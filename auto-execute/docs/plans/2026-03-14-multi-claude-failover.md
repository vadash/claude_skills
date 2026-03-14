# Multi-Claude Failover Implementation Plan

**Goal:** Reorder CLI arguments so claude binaries come first (plan last), and add optional backup claude binary that retries failed tasks before counting toward MaxFailures.

**Architecture:** New `Split-AxeArguments` pure function parses positional args into main/backup/plan. `Format-TaskLogEntry` gains parameters for binary name and fail suffix. Main loop in `auto-execute.ps1` uses `$useBackup` state to select between binaries and retry on failure.

**Tech Stack:** PowerShell, Pester 5

---

### Task 1: Split-AxeArguments function

**Files:**
- Modify: `auto-execute-helpers.ps1` (add function)
- Modify: `tests/auto-execute-helpers.Tests.ps1` (add test block)

- [ ] Step 1: Write failing tests for Split-AxeArguments

Append this `Describe` block at the end of `tests/auto-execute-helpers.Tests.ps1`, just before the final newline:

```powershell
Describe "Split-AxeArguments" {
    It "parses single claude binary and plan" {
        $result = Split-AxeArguments -Arguments @("claude_stable_ali", "mask-endpoint")
        $result.MainClaude | Should -Be "claude_stable_ali"
        $result.BackupClaude | Should -BeNull
        $result.PlanInput | Should -Be "mask-endpoint"
    }

    It "parses two claude binaries and plan" {
        $result = Split-AxeArguments -Arguments @("claude_stable_ali", "claude_stable_any", "mask-endpoint")
        $result.MainClaude | Should -Be "claude_stable_ali"
        $result.BackupClaude | Should -Be "claude_stable_any"
        $result.PlanInput | Should -Be "mask-endpoint"
    }

    It "handles plan argument between claude binaries" {
        $result = Split-AxeArguments -Arguments @("claude_stable_ali", "mask-endpoint", "claude_stable_any")
        $result.MainClaude | Should -Be "claude_stable_ali"
        $result.BackupClaude | Should -Be "claude_stable_any"
        $result.PlanInput | Should -Be "mask-endpoint"
    }

    It "matches claude prefix case-insensitively" {
        $result = Split-AxeArguments -Arguments @("Claude_Stable", "my-plan")
        $result.MainClaude | Should -Be "Claude_Stable"
        $result.PlanInput | Should -Be "my-plan"
    }

    It "handles bare claude binary name" {
        $result = Split-AxeArguments -Arguments @("claude", "my-plan")
        $result.MainClaude | Should -Be "claude"
        $result.BackupClaude | Should -BeNull
        $result.PlanInput | Should -Be "my-plan"
    }

    It "throws when no claude binary is provided" {
        { Split-AxeArguments -Arguments @("mask-endpoint") } |
            Should -Throw "*No claude binary*"
    }

    It "throws when no plan argument is provided" {
        { Split-AxeArguments -Arguments @("claude_stable_ali") } |
            Should -Throw "*No plan argument*"
    }

    It "throws when more than 2 claude binaries are provided" {
        { Split-AxeArguments -Arguments @("claude_a", "claude_b", "claude_c", "my-plan") } |
            Should -Throw "*Too many claude binaries*"
    }

    It "throws when more than 1 non-claude argument is provided" {
        { Split-AxeArguments -Arguments @("claude_a", "plan1", "plan2") } |
            Should -Throw "*Too many non-claude arguments*"
    }
}
```

- [ ] Step 2: Run tests to verify they fail

Run: `Invoke-Pester -Path tests/auto-execute-helpers.Tests.ps1 -TagFilter '' -Output Detailed 2>&1 | Select-String 'Split-AxeArguments|Passed|Failed'`

Expected: All 9 `Split-AxeArguments` tests FAIL with "The term 'Split-AxeArguments' is not recognized"

- [ ] Step 3: Write the implementation

Append this function at the end of `auto-execute-helpers.ps1`:

```powershell
function Split-AxeArguments {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $claudeBinaries = @()
    $otherArgs = @()

    foreach ($arg in $Arguments) {
        if ($arg -match '^claude') {
            $claudeBinaries += $arg
        } else {
            $otherArgs += $arg
        }
    }

    if ($claudeBinaries.Count -eq 0) {
        throw "No claude binary specified. At least one argument must start with 'claude'."
    }
    if ($claudeBinaries.Count -gt 2) {
        throw "Too many claude binaries specified (max 2). Got: $($claudeBinaries -join ', ')"
    }
    if ($otherArgs.Count -eq 0) {
        throw "No plan argument found. One non-claude argument is required."
    }
    if ($otherArgs.Count -gt 1) {
        throw "Too many non-claude arguments (max 1). Got: $($otherArgs -join ', ')"
    }

    return @{
        MainClaude   = $claudeBinaries[0]
        BackupClaude = if ($claudeBinaries.Count -gt 1) { $claudeBinaries[1] } else { $null }
        PlanInput    = $otherArgs[0]
    }
}
```

- [ ] Step 4: Run tests to verify they pass

Run: `Invoke-Pester -Path tests/auto-execute-helpers.Tests.ps1 -Output Detailed`

Expected: All tests PASS (including the 9 new ones and all existing tests)

- [ ] Step 5: Commit

```bash
git add -A && git commit -m "feat: add Split-AxeArguments function for new CLI format"
```

---

### Task 2: Format-TaskLogEntry updates

**Files:**
- Modify: `auto-execute-helpers.ps1` (update function signature and body)
- Modify: `tests/auto-execute-helpers.Tests.ps1` (add test cases)

- [ ] Step 1: Write failing tests for ClaudeBin and FailSuffix parameters

Append these `It` blocks inside the existing `Describe "Format-TaskLogEntry"` block in `tests/auto-execute-helpers.Tests.ps1`, after the last existing `It` block ("shows peak context before token string"):

```powershell
    It "includes claude binary name when ClaudeBin is provided" {
        $duration = [TimeSpan]::FromSeconds(120)
        $result = Format-TaskLogEntry -TaskNumber 1 -Passed $true -CommitHash "abc1234def" `
            -Duration $duration -ClaudeBin "claude_stable_ali"
        $result | Should -Match 'PASS \[claude_stable_ali\]'
    }

    It "includes claude binary name in failing entries" {
        $duration = [TimeSpan]::FromSeconds(45)
        $result = Format-TaskLogEntry -TaskNumber 2 -Passed $false -Duration $duration `
            -FailReason "no new commit" -ClaudeBin "claude_stable_any"
        $result | Should -Match 'FAIL \[claude_stable_any\]'
    }

    It "uses custom FailSuffix instead of STOPPED" {
        $duration = [TimeSpan]::FromSeconds(60)
        $result = Format-TaskLogEntry -TaskNumber 3 -Passed $false -Duration $duration `
            -FailReason "no new commit" -FailSuffix "retrying with backup"
        $result | Should -Match 'retrying with backup'
        $result | Should -Not -Match 'STOPPED'
    }

    It "omits binary tag when ClaudeBin is empty" {
        $duration = [TimeSpan]::FromSeconds(120)
        $result = Format-TaskLogEntry -TaskNumber 1 -Passed $true -CommitHash "abc1234def" `
            -Duration $duration
        $result | Should -Match 'PASS \(commit'
        $result | Should -Not -Match '\[.*\] \(commit'
    }
```

- [ ] Step 2: Run tests to verify they fail

Run: `Invoke-Pester -Path tests/auto-execute-helpers.Tests.ps1 -Output Detailed 2>&1 | Select-String 'Format-TaskLogEntry.*claude|Format-TaskLogEntry.*FailSuffix|Format-TaskLogEntry.*omits|Passed|Failed'`

Expected: The 4 new tests FAIL (parameter `ClaudeBin` does not exist). All existing tests still PASS.

- [ ] Step 3: Update Format-TaskLogEntry implementation

In `auto-execute-helpers.ps1`, modify the `Format-TaskLogEntry` function.

**3a.** Add two new parameters to the param block. Find:

```powershell
        [int]$PeakContext = 0,
        [int]$ContextLimit = 0
    )
```

Replace with:

```powershell
        [int]$PeakContext = 0,
        [int]$ContextLimit = 0,
        [string]$ClaudeBin = "",
        [string]$FailSuffix = "STOPPED"
    )
```

**3b.** Add the binary tag variable and update the return statements. Find:

```powershell
    if ($Passed) {
        $shortHash = if ($CommitHash.Length -ge 7) { $CommitHash.Substring(0, 7) } else { $CommitHash }
        return "[$timestamp] Task ${TaskNumber}: PASS (commit $shortHash, $durationStr)$ctxStr$TokenString"
    } else {
        return "[$timestamp] Task ${TaskNumber}: FAIL ($FailReason) — STOPPED$ctxStr$TokenString"
    }
```

Replace with:

```powershell
    $binTag = if ($ClaudeBin) { " [$ClaudeBin]" } else { "" }

    if ($Passed) {
        $shortHash = if ($CommitHash.Length -ge 7) { $CommitHash.Substring(0, 7) } else { $CommitHash }
        return "[$timestamp] Task ${TaskNumber}: PASS$binTag (commit $shortHash, $durationStr)$ctxStr$TokenString"
    } else {
        return "[$timestamp] Task ${TaskNumber}: FAIL$binTag ($FailReason) — $FailSuffix$ctxStr$TokenString"
    }
```

- [ ] Step 4: Run tests to verify they pass

Run: `Invoke-Pester -Path tests/auto-execute-helpers.Tests.ps1 -Output Detailed`

Expected: All tests PASS (new and existing — existing tests use default empty `ClaudeBin` and `FailSuffix = "STOPPED"`, so output is unchanged)

- [ ] Step 5: Commit

```bash
git add -A && git commit -m "feat: add ClaudeBin and FailSuffix params to Format-TaskLogEntry"
```

---

### Task 3: Wire argument parsing and failover into auto-execute.ps1

**Files:**
- Modify: `auto-execute.ps1`

All edits are in `auto-execute.ps1`. Apply them in order.

- [ ] Step 1: Replace the param block

Find:

```powershell
param(
    [Parameter(Mandatory, Position=0)] [string] $Plan,
    [Parameter(Position=1)] [string] $ClaudeBin = "claude",
    [int]    $MaxTurns     = 40,
    [int]    $TaskTimeout  = 900,
    [int]    $ContextLimit = 100000,
    [int]    $MaxFailures  = 2,
    [int]    $StartTask    = 0,
    [string] $LogDir       = "logs/auto-execute"
)
```

Replace with:

```powershell
param(
    [Parameter(Mandatory, ValueFromRemainingArguments)] [string[]] $Arguments,
    [int]    $MaxTurns     = 40,
    [int]    $TaskTimeout  = 900,
    [int]    $ContextLimit = 100000,
    [int]    $MaxFailures  = 2,
    [int]    $StartTask    = 0,
    [string] $LogDir       = "logs/auto-execute"
)
```

- [ ] Step 2: Replace Phase 0 with argument parsing and add backup pre-flight check

Find:

```powershell
# --- Phase 0: Resolve plan path ---
$Plan = Resolve-PlanPath -PlanInput $Plan

# --- Phase 1a: Pre-flight (before hooks) ---
$errors = Test-PreFlightEarly -ClaudeBin $ClaudeBin -PlanPath $Plan
```

Replace with:

```powershell
# --- Phase 0: Parse arguments ---
$parsed = Split-AxeArguments -Arguments $Arguments
$ClaudeBin = $parsed.MainClaude
$BackupClaudeBin = $parsed.BackupClaude
$Plan = Resolve-PlanPath -PlanInput $parsed.PlanInput

# --- Phase 1a: Pre-flight (before hooks) ---
$errors = Test-PreFlightEarly -ClaudeBin $ClaudeBin -PlanPath $Plan
if ($BackupClaudeBin -and -not (Get-Command $BackupClaudeBin -ErrorAction SilentlyContinue)) {
    $errors += "Backup CLI binary '$BackupClaudeBin' not found in PATH."
}
```

- [ ] Step 3: Update the startup banner

Find:

```powershell
Write-Host "CLI: $ClaudeBin | MaxTurns: $MaxTurns | Timeout: ${TaskTimeout}s | MaxFailures: $MaxFailures | ContextLimit: $ctxLimitStr" -ForegroundColor Cyan
```

Replace with:

```powershell
$backupStr = if ($BackupClaudeBin) { " (backup: $BackupClaudeBin)" } else { "" }
Write-Host "CLI: $ClaudeBin$backupStr | MaxTurns: $MaxTurns | Timeout: ${TaskTimeout}s | MaxFailures: $MaxFailures | ContextLimit: $ctxLimitStr" -ForegroundColor Cyan
```

- [ ] Step 4: Add `$useBackup` state variable

Find:

```powershell
$running = $true
$consecutiveFailures = 0
$completedCount = 0
```

Replace with:

```powershell
$running = $true
$consecutiveFailures = 0
$completedCount = 0
$useBackup = $false
```

- [ ] Step 5: Replace `$ClaudeBin` with `$activeClaude` in the loop body

Find:

```powershell
        # Build prompt and execute
        # Resolve full path to handle .cmd/.ps1 extensions
        $claudeCmd = (Get-Command $ClaudeBin).Source
```

Replace with:

```powershell
        # Build prompt and execute
        # Pick main or backup binary; resolve full path to handle .cmd/.ps1 extensions
        $activeClaude = if ($useBackup -and $BackupClaudeBin) { $BackupClaudeBin } else { $ClaudeBin }
        $claudeCmd = (Get-Command $activeClaude).Source
```

- [ ] Step 6: Update the success path to reset `$useBackup` and pass `$activeClaude`

Find:

```powershell
        if ($signals.AllPassed) {
            $consecutiveFailures = 0
            $completedCount++
            $entry = Format-TaskLogEntry -TaskNumber $currentTask -Passed $true `
                -CommitHash $afterHash -Duration $taskDuration -TokenString $tokenStr `
                -PeakContext $taskPeakContext -ContextLimit $ContextLimit
            Write-Host $entry -ForegroundColor Green
            $summaryEntries += $entry
            $currentTask++
```

Replace with:

```powershell
        if ($signals.AllPassed) {
            $consecutiveFailures = 0
            $completedCount++
            $useBackup = $false
            $entry = Format-TaskLogEntry -TaskNumber $currentTask -Passed $true `
                -CommitHash $afterHash -Duration $taskDuration -TokenString $tokenStr `
                -PeakContext $taskPeakContext -ContextLimit $ContextLimit `
                -ClaudeBin $activeClaude
            Write-Host $entry -ForegroundColor Green
            $summaryEntries += $entry
            $currentTask++
```

- [ ] Step 7: Restructure the failure path with failover logic

Find:

```powershell
        } else {
            $consecutiveFailures++
            $failReasons = @()
            if (-not $signals.ExitOk)    { $failReasons += "exit code $taskExitCode" }
            if (-not $signals.NewCommit) { $failReasons += "no new commit" }
            if (-not $signals.CleanTree) { $failReasons += "dirty tree" }

            if ($stopReason -match "^Context limit") {
                $failReason = $stopReason
                $running = $false
            } else {
                $failReason = $failReasons -join ", "
            }

            $entry = Format-TaskLogEntry -TaskNumber $currentTask -Passed $false `
                -Duration $taskDuration -FailReason $failReason -TokenString $tokenStr `
                -PeakContext $taskPeakContext -ContextLimit $ContextLimit
            Write-Host $entry -ForegroundColor Red
            $summaryEntries += $entry

            # Dirty tree handling
            if (-not $signals.CleanTree) {
                $stashed = Save-DirtyState -TaskNumber $currentTask
                if ($stashed) {
                    Write-Host "Task $currentTask left uncommitted changes. Stashed." -ForegroundColor Yellow
                }
                $running = $false
                $stopReason = "Dirty tree (changes stashed)"
                continue
            }

            if ($consecutiveFailures -ge $MaxFailures) {
                $running = $false
                $stopReason = "Max failures reached ($MaxFailures consecutive)"
            }
        }
```

Replace with:

```powershell
        } else {
            $consecutiveFailures++
            $failReasons = @()
            if (-not $signals.ExitOk)    { $failReasons += "exit code $taskExitCode" }
            if (-not $signals.NewCommit) { $failReasons += "no new commit" }
            if (-not $signals.CleanTree) { $failReasons += "dirty tree" }

            # Can retry with backup if: backup exists, not already using backup,
            # tree is clean, and not a context-limit kill
            $canRetry = $BackupClaudeBin -and (-not $useBackup) -and
                        $signals.CleanTree -and ($stopReason -notmatch "^Context limit")

            if ($stopReason -match "^Context limit") {
                $failReason = $stopReason
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

            # Dirty tree handling — no retry
            if (-not $signals.CleanTree) {
                $stashed = Save-DirtyState -TaskNumber $currentTask
                if ($stashed) {
                    Write-Host "Task $currentTask left uncommitted changes. Stashed." -ForegroundColor Yellow
                }
                $running = $false
                $stopReason = "Dirty tree (changes stashed)"
                continue
            }

            if ($canRetry) {
                # Main failed, backup available — retry same task
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

            # Normal failure or backup already tried
            $useBackup = $false
            if ($consecutiveFailures -ge $MaxFailures) {
                $running = $false
                $stopReason = "Max failures reached ($MaxFailures consecutive)"
            }
        }
```

- [ ] Step 8: Run all tests to verify no regressions

Run: `Invoke-Pester -Path tests/auto-execute-helpers.Tests.ps1 -Output Detailed`

Expected: All tests PASS (the helper function tests are unchanged; the main script changes are integration-level)

- [ ] Step 9: Commit

```bash
git add -A && git commit -m "feat: wire argument parsing and backup failover into main loop"
```

---

### Task 4: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] Step 1: Update the Running section

Find:

```markdown
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
```

Replace with:

````markdown
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

# Run tests
Invoke-Pester -Path tests/ -Output Detailed
```
````

- [ ] Step 2: Commit

```bash
git add -A && git commit -m "docs: update CLAUDE.md with new CLI argument format"
```
