# src/monitor.ps1 — Task monitoring loop
# Depends on: src/stream.ps1 (Read-StreamJsonChunk, Get-TokensFromEvent, Get-CostFromEvent,
#             Get-ClaudeProjectHash, Get-TranscriptContextPeak)
#             src/format.ps1 (Format-ToolEvent, Format-ContextSize)

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

    $exited = $false
    $lastSize = 0
    $errLastSize = 0
    $buffer = ""
    $taskTokens = @{ Input=0; Output=0; CacheRead=0; CacheWrite=0; Total=0; HitRate=0; CostUSD=0 }
    $taskPeakContext = 0
    $taskSessionId = $null
    $transcriptOffset = 0
    $transcriptCheckCounter = 0
    $taskErrorDetails = $null
    $lastActivity = [System.Diagnostics.Stopwatch]::StartNew()
    $cancelled = $false
    $stopReason = $null
    $taskExitCode = $null

    while (-not $exited) {
        $exited = $Process.WaitForExit(200)

        # Check for user interrupt keys (Ctrl+C, Escape, Q)
        try {
            while ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                if (($key.Key -eq 'C' -and ($key.Modifiers -band [ConsoleModifiers]::Control)) -or
                    $key.Key -eq 'Escape' -or
                    ($key.Key -eq 'Q' -and $key.Modifiers -eq 0)) {
                    if (-not $Process.HasExited) {
                        & taskkill /F /T /PID $Process.Id 2>$null | Out-Null
                    }
                    $taskExitCode = 130
                    $exited = $true
                    $cancelled = $true
                    $stopReason = "Cancelled by user"
                    break
                }
            }
        } catch { }
        if ($exited -and $cancelled) { break }

        # Read new bytes from stdout (stream-json)
        if (Test-Path $TaskLogPath) {
            $stream = [System.IO.File]::Open($TaskLogPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            $reader = New-Object System.IO.StreamReader($stream)
            $null = $reader.BaseStream.Seek($lastSize, [System.IO.SeekOrigin]::Begin)
            $newContent = $reader.ReadToEnd()
            $lastSize = $reader.BaseStream.Position
            $reader.Close()

            if ($newContent) {
                $parsed = Read-StreamJsonChunk -Chunk $newContent -Buffer $buffer
                $buffer = $parsed.Buffer

                if ($parsed.Events.Count -gt 0) {
                    $lastActivity.Restart()
                }

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

                    # Capture error details from result event (e.g., max turns exceeded)
                    if ($event.type -eq "result" -and $event.subtype -eq "error_max_turns") {
                        $turns = if ($event.num_turns) { $event.num_turns } else { "?" }
                        $taskErrorDetails = "max turns exceeded ($turns/$MaxTurns)"
                    }
                }
            }
        }

        # Transcript-based context tracking (every ~1s = 5 poll iterations)
        $transcriptCheckCounter++
        if ($taskSessionId -and $transcriptCheckCounter % 5 -eq 0) {
            $projectHash = Get-ClaudeProjectHash -DirPath $GitRoot
            $transcriptPath = Join-Path $env:USERPROFILE ".claude/projects/$projectHash/$taskSessionId.jsonl"
            $tResult = Get-TranscriptContextPeak -TranscriptPath $transcriptPath -StartOffset $transcriptOffset
            $transcriptOffset = $tResult.BytesRead
            if ($tResult.PeakContext -gt $taskPeakContext) {
                $taskPeakContext = $tResult.PeakContext
            }

            # Active Context Limit Enforcement
            if ($ContextLimit -gt 0 -and $taskPeakContext -gt $ContextLimit) {
                Write-Host "`n[CONTEXT LIMIT] Task $TaskNumber exceeded context limit: $(Format-ContextSize $taskPeakContext) > $(Format-ContextSize $ContextLimit)." -ForegroundColor Red
                & taskkill /F /T /PID $Process.Id 2>$null | Out-Null
                $taskExitCode = 2
                $exited = $true
                $stopReason = "Context limit exceeded ($taskPeakContext > $ContextLimit)"
                break
            }
        }

        # Tail stderr for fatal CLI errors
        $errPath = "$TaskLogPath.err"
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

        # Timeout check (activity-based: resets on stream-json events)
        if (-not $exited -and $lastActivity.Elapsed.TotalSeconds -gt $TaskTimeout) {
            Write-Host "`n[TIMEOUT] Task $TaskNumber idle for $TaskTimeout seconds." -ForegroundColor Red
            & taskkill /F /T /PID $Process.Id 2>$null | Out-Null
            $taskExitCode = 1
            $exited = $true
        }
    }

    # Final transcript read for most accurate peak context
    if ($taskSessionId) {
        $projectHash = Get-ClaudeProjectHash -DirPath $GitRoot
        $transcriptPath = Join-Path $env:USERPROFILE ".claude/projects/$projectHash/$taskSessionId.jsonl"
        $tResult = Get-TranscriptContextPeak -TranscriptPath $transcriptPath -StartOffset $transcriptOffset
        if ($tResult.PeakContext -gt $taskPeakContext) {
            $taskPeakContext = $tResult.PeakContext
        }
    }

    # Finalize token metrics
    $taskTokens.Total = $taskTokens.Input + $taskTokens.Output + $taskTokens.CacheRead
    $totalInput = $taskTokens.Input + $taskTokens.CacheRead
    if ($totalInput -gt 0) {
        $taskTokens.HitRate = [math]::Round(($taskTokens.CacheRead / $totalInput) * 100, 1)
    }

    if ($null -eq $taskExitCode) { $taskExitCode = $Process.ExitCode }

    return @{
        ExitCode     = $taskExitCode
        Tokens       = $taskTokens
        PeakContext  = $taskPeakContext
        SessionId    = $taskSessionId
        Cancelled    = $cancelled
        StopReason   = $stopReason
        ErrorDetails = $taskErrorDetails
    }
}