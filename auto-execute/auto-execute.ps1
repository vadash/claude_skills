# auto-execute.ps1 — Automated plan execution with safety circuit breakers
# Drives the outer loop: pre-flight checks, task execution, post-task verification.
# Each task runs in a fresh Claude process via the auto-execute skill.

param(
    [int]    $MaxTurns     = 80,
    [int]    $TaskTimeout  = 600,
    [int]    $ContextLimit = 100000,
    [int]    $StartTask    = 0,
    [string] $LogDir       = "logs/auto-execute",
    [Parameter(Mandatory, ValueFromRemainingArguments, Position=0)] [string[]] $Arguments
)

# Dot-source modules
. "$PSScriptRoot/src/args.ps1"
. "$PSScriptRoot/src/plan.ps1"
. "$PSScriptRoot/src/preflight.ps1"
. "$PSScriptRoot/src/stream.ps1"
. "$PSScriptRoot/src/format.ps1"
. "$PSScriptRoot/src/monitor.ps1"

# --- Phase 0: Parse arguments ---
$parsed = Split-AxeArguments -Arguments $Arguments
$ClaudeBinaries = $parsed.ClaudeBinaries  # Array of 1-5 binaries
$Plan = Resolve-PlanPath -PlanInput $parsed.PlanInput
if ($parsed.StartTask -gt 0 -and $StartTask -eq 0) {
    $StartTask = $parsed.StartTask
}

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

# --- Phase 1b: Pre-flight (after hooks) ---
$errors = Test-PreFlightLate -PlanPath $Plan -LogDir $LogDir
if ($errors.Count -gt 0) {
    Write-Host "Pre-flight checks failed:" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}

# Ensure LogDir is in .gitignore (prevents dirty-tree false positives from script's own logs)
$gitRoot = (git rev-parse --show-toplevel 2>&1).ToString().Trim()
$gitignorePath = Join-Path $gitRoot ".gitignore"
$logDirBase = ($LogDir -split '[/\\]')[0]
$logPattern = "/$logDirBase/"
$needsAdd = $true
if (Test-Path $gitignorePath) {
    $lines = Get-Content $gitignorePath
    if ($lines | Where-Object { $_ -match "^/?$([regex]::Escape($logDirBase))/?$" }) {
        $needsAdd = $false
    }
}
if ($needsAdd) {
    Add-Content -Path $gitignorePath -Value "`n$logPattern"
    Push-Location $gitRoot
    git add .gitignore
    git commit -m "chore: add $logDirBase to .gitignore"
    Pop-Location
}

# --- Phase 2: Task Tracking ---
$planContent = Get-Content $Plan -Raw
$planData = Get-PlanTasks -PlanContent $planContent
$totalTasks = $planData.Tasks.Count

if ($totalTasks -eq 0) {
    Write-Host "Error: No tasks found in plan file." -ForegroundColor Red
    exit 1
}

# Gap detection
$taskNumbers = $planData.Tasks | ForEach-Object { $_.Number }
$gaps = Get-TaskNumberGaps -TaskNumbers $taskNumbers
if ($gaps.Count -gt 0) {
    $foundStr = ($taskNumbers | Sort-Object) -join ", "
    $missingStr = $gaps -join ", "
    Write-Host "WARNING: Gap in task numbering. Found: $foundStr (missing: $missingStr)." -ForegroundColor Yellow
    $response = Read-Host "Continue anyway? [Y/n]"
    if ($response -match '^[Nn]') {
        Write-Host "Aborted." -ForegroundColor Red
        exit 1
    }
}

# Determine starting index
$taskIndex = 0
if ($StartTask -gt 0) {
    $found = $false
    for ($i = 0; $i -lt $planData.Tasks.Count; $i++) {
        if ($planData.Tasks[$i].Number -ge $StartTask) {
            $taskIndex = $i
            $found = $true
            break
        }
    }
    if (-not $found) {
        Write-Host "All tasks in the plan are already complete!" -ForegroundColor Green
        exit 0
    }
    Write-Host "Resuming from task $($planData.Tasks[$taskIndex].Number) (user specified)" -ForegroundColor Cyan
} else {
    Write-Host "Starting from task $($planData.Tasks[0].Number)" -ForegroundColor Cyan
}

Write-Host "Starting auto-execute: $totalTasks tasks" -ForegroundColor Cyan
Write-Host "Plan: $Plan" -ForegroundColor Cyan
$binariesStr = $ClaudeBinaries -join ", "
$ctxLimitStr = Format-ContextSize $ContextLimit
Write-Host "CLI binaries: $binariesStr | MaxTurns: $MaxTurns | Timeout: ${TaskTimeout}s | ContextLimit: $ctxLimitStr" -ForegroundColor Cyan

# Clean old log files from previous runs
Clear-LogDirectory -LogDir $LogDir

# --- Phase 3: Main Loop ---
$running = $true
$completedCount = 0
$overallStart = [System.Diagnostics.Stopwatch]::StartNew()
$runTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$summaryLogPath = Join-Path $LogDir "run-$runTimestamp.log"
$summaryEntries = @()
$stopReason = "Unknown"
$overallMetrics = @{ Input=0; Output=0; CacheRead=0; CacheWrite=0; Total=0; HitRate=0; CostUSD=0 }
$overallPeakContext = 0

# Reclaim Ctrl+C from child process — TreatControlCAsInput converts Ctrl+C into a
# regular keystroke detectable via ReadKey, instead of an OS CTRL_C_EVENT that Node.js
# (claude) would handle directly, preventing our handler from ever firing.
$originalTreatCtrlC = $false
try { $originalTreatCtrlC = [Console]::TreatControlCAsInput; [Console]::TreatControlCAsInput = $true } catch { }

Write-Host "Press Ctrl+C, Escape, or Q to cancel a running task." -ForegroundColor DarkGray

# Create an empty temp file for stdin redirect (PowerShell resolves "NUL" as a real
# file path and fails; an actual empty file works reliably across all PS versions)
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
