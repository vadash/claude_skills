# auto-execute.ps1 — Automated plan execution with safety circuit breakers
# Drives the outer loop: pre-flight checks, task execution, post-task verification.
# Each task runs in a fresh Claude process via the auto-execute skill.

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

# Dot-source helper functions
. "$PSScriptRoot/auto-execute-helpers.ps1"

# --- Phase 0: Resolve plan path ---
$Plan = Resolve-PlanPath -PlanInput $Plan

# --- Phase 1a: Pre-flight (before hooks) ---
$errors = Test-PreFlightEarly -ClaudeBin $ClaudeBin -PlanPath $Plan
if ($errors.Count -gt 0) {
    Write-Host "Pre-flight checks failed:" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}

# --- Phase 1.5: Hook Auto-Installer ---
$gitRoot = (git rev-parse --show-toplevel 2>&1).ToString().Trim()
$hookStatus = Get-ProjectHooksStatus -SourceDir $PSScriptRoot -GitRoot $gitRoot

switch ($hookStatus) {
    'Missing' {
        Write-Host "[NOTICE] Safety hooks not installed in this project." -ForegroundColor Yellow
        $response = Read-Host "Install them? [Y/n]"
        if ([string]::IsNullOrWhiteSpace($response) -or $response -match '^[Yy]') {
            Install-ProjectHooks -SourceDir $PSScriptRoot -GitRoot $gitRoot
            Push-Location $gitRoot
            git add .claude/hooks/ .claude/settings.json
            git commit -m "chore: add axe safety hooks"
            Pop-Location
            Write-Host "Hooks installed." -ForegroundColor Green
        } else {
            Write-Host "WARNING: Running without safety hooks!" -ForegroundColor Red
            Start-Sleep 2
        }
    }
    'Outdated' {
        Install-ProjectHooks -SourceDir $PSScriptRoot -GitRoot $gitRoot
        Push-Location $gitRoot
        git add .claude/hooks/ .claude/settings.json
        git commit -m "chore: update axe safety hooks"
        Pop-Location
        Write-Host "Safety hooks updated to latest version." -ForegroundColor Cyan
    }
    'Ok' { }
}

# --- Phase 1b: Pre-flight (after hooks) ---
$errors = Test-PreFlightLate -PlanPath $Plan -LogDir $LogDir
if ($errors.Count -gt 0) {
    Write-Host "Pre-flight checks failed:" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}

# Ensure LogDir is in .gitignore (prevents dirty-tree false positives from script's own logs)
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
$ctxLimitStr = Format-ContextSize $ContextLimit
Write-Host "CLI: $ClaudeBin | MaxTurns: $MaxTurns | Timeout: ${TaskTimeout}s | MaxFailures: $MaxFailures | ContextLimit: $ctxLimitStr" -ForegroundColor Cyan

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
$overallPeakContext = 0

# Ctrl+C handler — compiled C# delegate that runs instantly on the OS signal thread.
# PowerShell scriptblocks attached to .NET events are queued on the main runspace thread,
# which never processes them while blocked in our while-loop. A compiled handler bypasses this.
if (-not ("AxeCtrlC" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Diagnostics;
public static class AxeCtrlC {
    public static volatile bool IsCancelled = false;
    public static volatile int ChildPid = -1;
    public static void Handler(object sender, ConsoleCancelEventArgs e) {
        e.Cancel = true;
        IsCancelled = true;
        int pid = ChildPid;
        if (pid > 0) {
            try {
                var psi = new ProcessStartInfo("taskkill", "/F /T /PID " + pid) {
                    CreateNoWindow = true, UseShellExecute = false
                };
                Process.Start(psi);
            } catch { }
        }
    }
}
"@
}
[AxeCtrlC]::IsCancelled = $false
[AxeCtrlC]::ChildPid = -1
$cancelHandler = [System.Delegate]::CreateDelegate(
    [System.ConsoleCancelEventHandler],
    [AxeCtrlC].GetMethod("Handler")
)
[Console]::add_CancelKeyPress($cancelHandler)

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
        [AxeCtrlC]::ChildPid = $process.Id

        # Tail the log file with stream-json parsing
        $taskExitCode = $null
        $lastSize = 0
        $errLastSize = 0
        $exited = $false
        $buffer = ""
        $taskTokens = @{ Input=0; Output=0; CacheRead=0; CacheWrite=0; Total=0; HitRate=0; CostUSD=0 }
        $taskPeakContext = 0
        $taskSessionId = $null
        $transcriptOffset = 0
        $transcriptCheckCounter = 0

        while (-not $exited) {
            # Check for Ctrl+C cancellation
            if ([AxeCtrlC]::IsCancelled) {
                # C# handler already killed the child via taskkill
                if (-not $process.HasExited) {
                    & taskkill /F /T /PID $process.Id 2>$null | Out-Null
                }
                $taskExitCode = 130
                $exited = $true
                $running = $false
                $stopReason = "Cancelled by user (Ctrl+C)"
                break
            }

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
                        # Capture session_id from init event for transcript reading
                        if ($event.type -eq "system" -and $event.subtype -eq "init" -and $event.session_id) {
                            $taskSessionId = $event.session_id
                        }

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

                        # Context tracking moved to transcript-based polling below

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

            # Transcript-based context tracking (every ~1s = 5 poll iterations)
            $transcriptCheckCounter++
            if ($taskSessionId -and $transcriptCheckCounter % 5 -eq 0) {
                $projectHash = Get-ClaudeProjectHash -DirPath $gitRoot
                $transcriptPath = Join-Path $env:USERPROFILE ".claude/projects/$projectHash/$taskSessionId.jsonl"
                $tResult = Get-TranscriptContextPeak -TranscriptPath $transcriptPath -StartOffset $transcriptOffset
                $transcriptOffset = $tResult.BytesRead
                if ($tResult.PeakContext -gt $taskPeakContext) {
                    $taskPeakContext = $tResult.PeakContext
                }

                # Active Context Limit Enforcement
                if ($ContextLimit -gt 0 -and $taskPeakContext -gt $ContextLimit) {
                    Write-Host "`n[CONTEXT LIMIT] Task $currentTask exceeded context limit: $(Format-ContextSize $taskPeakContext) > $(Format-ContextSize $ContextLimit)." -ForegroundColor Red
                    & taskkill /F /T /PID $process.Id 2>$null | Out-Null
                    $taskExitCode = 2
                    $exited = $true
                    $stopReason = "Context limit exceeded ($taskPeakContext > $ContextLimit)"
                    break
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

        # Final transcript read for most accurate peak context
        if ($taskSessionId) {
            $projectHash = Get-ClaudeProjectHash -DirPath $gitRoot
            $transcriptPath = Join-Path $env:USERPROFILE ".claude/projects/$projectHash/$taskSessionId.jsonl"
            $tResult = Get-TranscriptContextPeak -TranscriptPath $transcriptPath -StartOffset $transcriptOffset
            if ($tResult.PeakContext -gt $taskPeakContext) {
                $taskPeakContext = $tResult.PeakContext
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

        # Check if run was cancelled via Ctrl+C (caught by event handler OR child process exiting with SIGINT codes)
        if ([AxeCtrlC]::IsCancelled -or $taskExitCode -eq 130 -or $taskExitCode -eq 3221225786) {
            $taskStart.Stop()
            Write-Host "`n[!] Run cancelled by user." -ForegroundColor Yellow
            $running = $false
            $stopReason = "Cancelled by user (Ctrl+C)"

            # Accumulate tokens for the aborted task before breaking
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
                -CommitHash $afterHash -Duration $taskDuration -TokenString $tokenStr `
                -PeakContext $taskPeakContext -ContextLimit $ContextLimit
            Write-Host $entry -ForegroundColor Green
            $summaryEntries += $entry
            $currentTask++
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

        # Accumulate tokens into overall metrics (regardless of task outcome)
        $overallMetrics.Input += $taskTokens.Input
        $overallMetrics.Output += $taskTokens.Output
        $overallMetrics.CacheRead += $taskTokens.CacheRead
        $overallMetrics.CacheWrite += $taskTokens.CacheWrite
        $overallMetrics.CostUSD += $taskTokens.CostUSD

        # Track max peak context across all tasks
        if ($taskPeakContext -gt $overallPeakContext) {
            $overallPeakContext = $taskPeakContext
        }

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
    # Remove Ctrl+C handler
    [Console]::remove_CancelKeyPress($cancelHandler)

    # Kill child process if still running
    if ($process -and -not $process.HasExited) {
        & taskkill /F /T /PID $process.Id 2>$null | Out-Null
        Write-Host "Killed running Claude process (PID $($process.Id))." -ForegroundColor Yellow
    }
    [AxeCtrlC]::ChildPid = -1
    [AxeCtrlC]::IsCancelled = $false

    # Clean up environment
    $env:AXE_ACTIVE = $null
    $env:AXE_CONTEXT_LIMIT = $null
    $overallStart.Stop()

    # Clean up temp counter files
    Get-ChildItem -Path $env:TEMP -Filter "axe-calls-*.jsonl" -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue

    # Write summary log (re-create dir — git stash --include-untracked may have removed it)
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
    $report = Format-FinalReport -PlanPath $Plan -CompletedTasks $completedCount `
        -TotalTasks $totalTasks -TotalDuration $overallStart.Elapsed `
        -StopReason $stopReason -LogFile $summaryLogPath -TokenString $overallTokenStr `
        -MaxPeakContext $overallPeakContext -ContextLimit $ContextLimit `
        -NextTask $currentTask
    Write-Host "`n$report" -ForegroundColor Cyan
}
