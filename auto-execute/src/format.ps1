# src/format.ps1 — Formatting and display

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
        [int]$AttemptNumber = 0,
        [int]$TotalBinaries = 0
    )

    $timestamp = Get-Date -Format "HH:mm:ss"
    $durationStr = "{0}m {1:D2}s" -f [math]::Floor($Duration.TotalMinutes), $Duration.Seconds
    $ctxStr = ""
    if ($PeakContext -gt 0 -and $ContextLimit -gt 0) {
        $ctxStr = " | Peak ctx: $(Format-ContextSize $PeakContext)/$(Format-ContextSize $ContextLimit)"
    }

    # Build attempt info for display
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

function Format-FinalReport {
    param(
        [string]$PlanPath,
        [int]$CompletedTasks,
        [int]$TotalTasks,
        [TimeSpan]$TotalDuration,
        [string]$StopReason,
        [string]$LogFile,
        [string]$TokenString = "",
        [int]$MaxPeakContext = 0,
        [int]$ContextLimit = 0,
        [int]$NextTask = 0
    )

    $durationStr = "{0}m {1:D2}s" -f [math]::Floor($TotalDuration.TotalMinutes), $TotalDuration.Seconds
    $ctxLine = ""
    if ($MaxPeakContext -gt 0 -and $ContextLimit -gt 0) {
        $ctxLine = "`nMax peak ctx: $(Format-ContextSize $MaxPeakContext)/$(Format-ContextSize $ContextLimit)"
    }

    $resumeHint = ""
    if ($StopReason -ne "All tasks complete" -and $NextTask -gt 0) {
        $resumeHint = "`n`nTo resume manually:`n  /executing-plans @$PlanPath do task $NextTask"
    }

    return @"
=== Auto-Execute Summary ===
Plan:       $PlanPath
Tasks:      $CompletedTasks/$TotalTasks completed
Duration:   $durationStr$TokenString$ctxLine
Stop reason: $StopReason
Logs:       $LogFile$resumeHint
"@
}

function Format-ContextSize {
    param(
        [int]$Tokens
    )

    if ($Tokens -ge 1000000) { return "{0:0.0}M" -f ($Tokens / 1000000) }
    if ($Tokens -ge 1000)    { return "{0:0.0}k" -f ($Tokens / 1000) }
    return [string]$Tokens
}

function Format-ToolEvent {
    param(
        [PSObject]$Event
    )

    if ($Event.type -ne "assistant" -or -not $Event.message -or -not $Event.message.content) {
        return $null
    }

    $results = @()

    foreach ($block in $Event.message.content) {
        if ($block.type -eq "tool_use") {
            $toolName = $block.name
            $inputStr = ""

            if ($block.input) {
                if ($toolName -eq "Bash" -and $block.input.command) {
                    $inputStr = $block.input.command
                } elseif ($toolName -match "^(Read|Write|Edit)$" -and $block.input.file_path) {
                    $fileName = [System.IO.Path]::GetFileName($block.input.file_path)
                    $inputStr = if ($fileName) { $fileName } else { $block.input.file_path }
                    if ($toolName -eq "Edit") { $inputStr += " (editing)" }
                } elseif ($toolName -eq "Glob" -and $block.input.pattern) {
                    $inputStr = $block.input.pattern
                } elseif ($toolName -eq "Grep" -and $block.input.pattern) {
                    $inputStr = $block.input.pattern
                } else {
                    $inputStr = $block.input | ConvertTo-Json -Depth 5 -Compress
                }
            }

            if ($inputStr.Length -gt 150) {
                $inputStr = $inputStr.Substring(0, 147) + "..."
            }

            $results += "[TOOL] $toolName | $inputStr"
        }
    }

    if ($results.Count -eq 0) { return $null }
    return $results
}

function Format-TokenMetrics {
    param(
        [hashtable]$Metrics
    )

    if (-not $Metrics -or $Metrics.Total -eq 0) { return "" }

    $fmtNum = {
        param([double]$n)
        if ($n -ge 1000000) { return "{0:0.0}M" -f ($n / 1000000) }
        if ($n -ge 1000) { return "{0:0.0}k" -f ($n / 1000) }
        return [string][int]$n
    }

    $inStr = & $fmtNum $Metrics.Input
    $outStr = & $fmtNum $Metrics.Output
    $cacheStr = & $fmtNum $Metrics.CacheRead
    $hitRate = "{0:0.0}" -f $Metrics.HitRate

    $result = " | Tokens: $inStr In, $outStr Out, $cacheStr Cache R ($hitRate% hit)"

    if ($Metrics.CostUSD -gt 0) {
        $cost = "{0:N2}" -f $Metrics.CostUSD
        $result += " | " + '$' + $cost
    }

    return $result
}

function Clear-LogDirectory {
    param(
        [string]$LogDir
    )

    if (-not (Test-Path $LogDir)) { return }

    Get-ChildItem -Path "$LogDir/*.log" -File -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path "$LogDir/*.log.err" -File -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path "$LogDir/task-*.md" -File -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
}