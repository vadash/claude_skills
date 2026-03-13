# auto-execute.ps1 — Automated plan execution with safety circuit breakers
# Drives the outer loop: pre-flight checks, task execution, post-task verification.
# Each task runs in a fresh Claude process via the auto-execute skill.

param(
    [Parameter(Mandatory)] [string] $Plan,
    [string] $ClaudeBin    = "claude",
    [int]    $MaxTurns     = 40,
    [int]    $TaskTimeout  = 900,
    [int]    $ContextLimit = 70000,
    [int]    $MaxFailures  = 2,
    [int]    $StartTask    = 0,
    [string] $LogDir       = "logs/auto-execute"
)

# Dot-source helper functions
. "$PSScriptRoot/auto-execute-helpers.ps1"

# --- Phase 1: Pre-flight Checks ---
$errors = Test-PreFlightChecks -ClaudeBin $ClaudeBin -PlanPath $Plan -LogDir $LogDir
if ($errors.Count -gt 0) {
    Write-Host "Pre-flight checks failed:" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}

# Warn if LogDir is not in .gitignore
$gitRoot = git rev-parse --show-toplevel 2>$null
if ($gitRoot) {
    $gitignorePath = Join-Path $gitRoot ".gitignore"
    if (Test-Path $gitignorePath) {
        $gitignoreContent = Get-Content $gitignorePath -Raw
        $logDirBase = ($LogDir -split '[/\\]')[0]
        if ($gitignoreContent -notmatch [regex]::Escape($logDirBase)) {
            Write-Host "WARNING: '$logDirBase/' is not in .gitignore. Logs may be committed." -ForegroundColor Yellow
        }
    }
}

# Set environment for hooks
$env:AXE_ACTIVE = "true"
$env:AXE_CONTEXT_LIMIT = $ContextLimit

# --- Phase 2: Task Tracking ---
$planContent = Get-Content $Plan -Raw
$totalTasks = Get-TotalTaskCount -PlanContent $planContent

if ($StartTask -gt 0) {
    $currentTask = $StartTask
} else {
    $currentTask = Find-FirstUncheckedTask -PlanContent $planContent
    if ($currentTask -eq 0) {
        Write-Host "All tasks in the plan are already complete!" -ForegroundColor Green
        exit 0
    }
}

Write-Host "Starting auto-execute: tasks $currentTask to $totalTasks" -ForegroundColor Cyan
Write-Host "Plan: $Plan" -ForegroundColor Cyan
Write-Host "CLI: $ClaudeBin | MaxTurns: $MaxTurns | Timeout: ${TaskTimeout}s | MaxFailures: $MaxFailures" -ForegroundColor Cyan

# Clean old log files from previous runs
Clear-LogDirectory -LogDir $LogDir

# --- Phase 3: Main Loop ---
$running = $true
$consecutiveFailures = 0
$completedCount = 0
$overallStart = [System.Diagnostics.Stopwatch]::StartNew()
$runTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$summaryLogPath = Join-Path $LogDir "run-$runTimestamp.log"
$summaryEntries = @()
$stopReason = "Unknown"
$overallMetrics = @{ Input=0; Output=0; CacheRead=0; CacheWrite=0; Total=0; HitRate=0; CostUSD=0 }

try {
    while ($running -and $currentTask -le $totalTasks) {
        # Record baseline
        $beforeHash = (git rev-parse HEAD 2>&1).ToString().Trim()
        $taskStart = [System.Diagnostics.Stopwatch]::StartNew()
        $taskTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $taskLogPath = Join-Path $LogDir "task-$currentTask-$taskTimestamp.log"

        Write-Host "`n--- Task $currentTask/$totalTasks ---" -ForegroundColor Cyan

        # Build prompt and execute
        # Resolve full path to handle .cmd/.ps1 extensions
        $claudeCmd = (Get-Command $ClaudeBin).Source
        $promptText = "/auto-execute @$Plan do task $currentTask"
        $claudeArgs = "-p `"$promptText`" --dangerously-skip-permissions --max-turns $MaxTurns --output-format stream-json --verbose"

        # .ps1 scripts can't be launched directly by Start-Process; wrap with powershell
        if ($claudeCmd -like '*.ps1') {
            $argString = "-NoProfile -File `"$claudeCmd`" $claudeArgs"
            $claudeCmd = "powershell"
        } else {
            $argString = $claudeArgs
        }

        $process = Start-Process -FilePath $claudeCmd `
            -ArgumentList $argString `
            -PassThru -NoNewWindow `
            -RedirectStandardOutput $taskLogPath `
            -RedirectStandardError "$taskLogPath.err"

        # Tail the log file with stream-json parsing
        $taskExitCode = $null
        $lastSize = 0
        $errLastSize = 0
        $exited = $false
        $buffer = ""
        $taskTokens = @{ Input=0; Output=0; CacheRead=0; CacheWrite=0; Total=0; HitRate=0; CostUSD=0 }

        while (-not $exited) {
            $exited = $process.WaitForExit(200)

            # Read new bytes from stdout (stream-json)
            if (Test-Path $taskLogPath) {
                $stream = [System.IO.File]::Open($taskLogPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                $reader = New-Object System.IO.StreamReader($stream)
                $null = $reader.BaseStream.Seek($lastSize, [System.IO.SeekOrigin]::Begin)
                $newContent = $reader.ReadToEnd()
                $lastSize = $reader.BaseStream.Position
                $reader.Close()

                if ($newContent) {
                    $parsed = Read-StreamJsonChunk -Chunk $newContent -Buffer $buffer
                    $buffer = $parsed.Buffer

                    foreach ($event in $parsed.Events) {
                        # Display tool calls
                        $toolLines = Format-ToolEvent -Event $event
                        if ($toolLines) {
                            foreach ($line in @($toolLines)) {
                                Write-Host $line -ForegroundColor DarkGray
                            }
                        }

                        # Accumulate tokens from assistant messages (fallback)
                        $usage = Get-TokensFromEvent -Event $event
                        if ($usage) {
                            $taskTokens.Input += $usage.Input
                            $taskTokens.Output += $usage.Output
                            $taskTokens.CacheRead += $usage.CacheRead
                            $taskTokens.CacheWrite += $usage.CacheWrite
                        }

                        # Authoritative result event overwrites accumulated tokens
                        $cost = Get-CostFromEvent -Event $event
                        if ($null -ne $cost) {
                            $taskTokens.CostUSD = $cost
                            $resultUsage = Get-TokensFromEvent -Event $event
                            if ($resultUsage) {
                                $taskTokens.Input = $resultUsage.Input
                                $taskTokens.Output = $resultUsage.Output
                                $taskTokens.CacheRead = $resultUsage.CacheRead
                                $taskTokens.CacheWrite = $resultUsage.CacheWrite
                            }
                        }
                    }
                }
            }

            # Tail stderr for fatal CLI errors
            $errPath = "$taskLogPath.err"
            if (Test-Path $errPath) {
                $errStream = [System.IO.File]::Open($errPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                $errReader = New-Object System.IO.StreamReader($errStream)
                $null = $errReader.BaseStream.Seek($errLastSize, [System.IO.SeekOrigin]::Begin)
                $newErrContent = $errReader.ReadToEnd()
                $errLastSize = $errReader.BaseStream.Position
                $errReader.Close()

                if ($newErrContent) {
                    Write-Host $newErrContent -NoNewline -ForegroundColor Red
                }
            }

            # Timeout check
            if (-not $exited -and $taskStart.Elapsed.TotalSeconds -gt $TaskTimeout) {
                Write-Host "`n[TIMEOUT] Task $currentTask exceeded $TaskTimeout seconds." -ForegroundColor Red
                & taskkill /F /T /PID $process.Id 2>$null | Out-Null
                $taskExitCode = 1
                $exited = $true
            }
        }

        # Finalize task token metrics
        $taskTokens.Total = $taskTokens.Input + $taskTokens.Output + $taskTokens.CacheRead
        $totalInput = $taskTokens.Input + $taskTokens.CacheRead
        if ($totalInput -gt 0) {
            $taskTokens.HitRate = [math]::Round(($taskTokens.CacheRead / $totalInput) * 100, 1)
        }
        $tokenStr = Format-TokenMetrics -Metrics $taskTokens

        if ($null -eq $taskExitCode) { $taskExitCode = $process.ExitCode }

        $taskStart.Stop()
        $taskDuration = $taskStart.Elapsed

        # Post-task verification (multi-signal)
        $afterHash = (git rev-parse HEAD 2>&1).ToString().Trim()
        $gitStatus = (git status --porcelain 2>&1) -join ""

        $signals = Test-TaskSuccess -ExitCode $taskExitCode `
            -BeforeHash $beforeHash -AfterHash $afterHash -GitStatus $gitStatus

        if ($signals.AllPassed) {
            $consecutiveFailures = 0
            $completedCount++
            $entry = Format-TaskLogEntry -TaskNumber $currentTask -Passed $true `
                -CommitHash $afterHash -Duration $taskDuration -TokenString $tokenStr
            Write-Host $entry -ForegroundColor Green
            $summaryEntries += $entry
            $currentTask++
        } else {
            $consecutiveFailures++
            $failReasons = @()
            if (-not $signals.ExitOk)    { $failReasons += "exit code $taskExitCode" }
            if (-not $signals.NewCommit) { $failReasons += "no new commit" }
            if (-not $signals.CleanTree) { $failReasons += "dirty tree" }
            $failReason = $failReasons -join ", "

            $entry = Format-TaskLogEntry -TaskNumber $currentTask -Passed $false `
                -Duration $taskDuration -FailReason $failReason -TokenString $tokenStr
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

        # Accumulate tokens into overall metrics (regardless of task outcome)
        $overallMetrics.Input += $taskTokens.Input
        $overallMetrics.Output += $taskTokens.Output
        $overallMetrics.CacheRead += $taskTokens.CacheRead
        $overallMetrics.CacheWrite += $taskTokens.CacheWrite
        $overallMetrics.CostUSD += $taskTokens.CostUSD

        # Clean up temp counter files between tasks (fresh session = fresh counter)
        Get-ChildItem -Path $env:TEMP -Filter "axe-calls-*.jsonl" -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }

    if ($currentTask -gt $totalTasks -and $running) {
        $stopReason = "All tasks complete"
    }
} catch {
    $stopReason = "Error: $_"
} finally {
    # Clean up environment
    $env:AXE_ACTIVE = $null
    $env:AXE_CONTEXT_LIMIT = $null
    $overallStart.Stop()

    # Warn about possible background Claude process on Ctrl+C
    if ($stopReason -eq "Unknown" -or $stopReason -match "^Error:") {
        Write-Host "NOTE: A Claude process may still be running in the background." -ForegroundColor Yellow
        Write-Host "Check with: Get-Process -Name node -ErrorAction SilentlyContinue" -ForegroundColor Yellow
    }

    # Clean up temp counter files
    Get-ChildItem -Path $env:TEMP -Filter "axe-calls-*.jsonl" -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue

    # Write summary log
    if ($summaryEntries.Count -gt 0) {
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
    $report = Format-FinalReport -PlanPath $Plan -CompletedTasks $completedCount `
        -TotalTasks $totalTasks -TotalDuration $overallStart.Elapsed `
        -StopReason $stopReason -LogFile $summaryLogPath -TokenString $overallTokenStr
    Write-Host "`n$report" -ForegroundColor Cyan
}
