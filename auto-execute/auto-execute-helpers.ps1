# Auto-Execute Helper Functions
# Dot-sourced by auto-execute.ps1 and tests.
# Contains only pure/testable functions.

function Find-FirstUncheckedTask {
    param(
        [Parameter(Mandatory)]
        [string]$PlanContent
    )

    $lines = $PlanContent -split "`n"
    $currentTask = 0

    foreach ($line in $lines) {
        if ($line -match '^###\s+Task\s+(\d+)') {
            $currentTask = [int]$Matches[1]
        }
        if ($currentTask -gt 0 -and $line -match '^\s*-\s*\[\s\]') {
            return $currentTask
        }
    }

    return 0
}

function Get-TotalTaskCount {
    param(
        [Parameter(Mandatory)]
        [string]$PlanContent
    )

    $taskMatches = [regex]::Matches($PlanContent, '(?m)^###\s+Task\s+(\d+)')
    if ($taskMatches.Count -eq 0) { return 0 }

    $max = 0
    foreach ($m in $taskMatches) {
        $num = [int]$m.Groups[1].Value
        if ($num -gt $max) { $max = $num }
    }
    return $max
}

function Test-TaskSuccess {
    param(
        [int]$ExitCode,
        [string]$BeforeHash,
        [string]$AfterHash,
        [string]$GitStatus
    )

    $signals = @{
        ExitOk    = ($ExitCode -eq 0)
        NewCommit = ($AfterHash -ne $BeforeHash)
        CleanTree = ([string]::IsNullOrWhiteSpace($GitStatus))
    }

    $signals.AllPassed = $signals.ExitOk -and $signals.NewCommit -and $signals.CleanTree

    return $signals
}

function Test-PreFlightChecks {
    param(
        [string]$ClaudeBin,
        [string]$PlanPath,
        [string]$LogDir
    )

    $errors = @()

    # Check CLI is callable
    if (-not (Get-Command $ClaudeBin -ErrorAction SilentlyContinue)) {
        $errors += "CLI binary '$ClaudeBin' not found in PATH."
    }

    # Check plan file exists and has unchecked tasks
    if (-not (Test-Path $PlanPath)) {
        $errors += "Plan file '$PlanPath' not found."
    } else {
        $content = Get-Content $PlanPath -Raw
        if ($content -notmatch '\-\s*\[\s\]') {
            $errors += "Plan file has no unchecked tasks (no '- [ ]' found)."
        }
    }

    # Check git repo
    $null = git rev-parse --git-dir 2>&1
    if ($LASTEXITCODE -ne 0) {
        $errors += "Not inside a git repository."
    }

    # Check clean working tree
    $status = git status --porcelain 2>&1
    if ($status) {
        $errors += "Git working tree is not clean."
    }

    # Check/create log directory
    if (-not (Test-Path $LogDir)) {
        try {
            New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
        } catch {
            $errors += "Cannot create log directory '$LogDir': $_"
        }
    }

    return $errors
}

function Save-DirtyState {
    param(
        [int]$TaskNumber
    )

    $stashMsg = "auto-execute: partial task $TaskNumber"
    git stash --include-untracked -m $stashMsg 2>&1
    return $LASTEXITCODE -eq 0
}

function Format-TaskLogEntry {
    param(
        [int]$TaskNumber,
        [bool]$Passed,
        [string]$CommitHash,
        [TimeSpan]$Duration,
        [string]$FailReason
    )

    $timestamp = Get-Date -Format "HH:mm:ss"
    $durationStr = "{0}m {1:D2}s" -f [math]::Floor($Duration.TotalMinutes), $Duration.Seconds

    if ($Passed) {
        $shortHash = if ($CommitHash.Length -ge 7) { $CommitHash.Substring(0, 7) } else { $CommitHash }
        return "[$timestamp] Task ${TaskNumber}: PASS (commit $shortHash, $durationStr)"
    } else {
        return "[$timestamp] Task ${TaskNumber}: FAIL ($FailReason) — STOPPED"
    }
}

function Format-FinalReport {
    param(
        [string]$PlanPath,
        [int]$CompletedTasks,
        [int]$TotalTasks,
        [TimeSpan]$TotalDuration,
        [string]$StopReason,
        [string]$LogFile
    )

    $durationStr = "{0}m {1:D2}s" -f [math]::Floor($TotalDuration.TotalMinutes), $TotalDuration.Seconds

    return @"
=== Auto-Execute Summary ===
Plan:       $PlanPath
Tasks:      $CompletedTasks/$TotalTasks completed
Duration:   $durationStr
Stop reason: $StopReason
Logs:       $LogFile
"@
}

function Read-StreamJsonChunk {
    param(
        [string]$Chunk,
        [string]$Buffer
    )

    $events = @()
    $newBuffer = ""
    $combined = $Buffer + $Chunk

    if ([string]::IsNullOrEmpty($combined)) {
        return @{ Events = $events; Buffer = $newBuffer }
    }

    $lines = $combined -split "`n"

    # If combined doesn't end with newline, last piece is partial
    if (-not $combined.EndsWith("`n")) {
        $newBuffer = $lines[-1]
        if ($lines.Count -gt 1) {
            $lines = $lines[0..($lines.Count - 2)]
        } else {
            $lines = @()
        }
    }

    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($trimmed -eq "") { continue }
        try {
            $parsed = $trimmed | ConvertFrom-Json
            $events += $parsed
        } catch {
            # Skip invalid JSON lines silently
        }
    }

    return @{ Events = $events; Buffer = $newBuffer }
}

function Get-TokensFromEvent {
    param(
        [PSObject]$Event
    )

    $usage = $null

    if ($Event.type -eq "assistant" -and $Event.message -and $Event.message.usage) {
        $usage = $Event.message.usage
    } elseif ($Event.type -eq "result" -and $Event.usage) {
        $usage = $Event.usage
    }

    if (-not $usage) { return $null }

    return @{
        Input      = [int]$usage.input_tokens
        Output     = [int]$usage.output_tokens
        CacheRead  = [int]$usage.cache_read_input_tokens
        CacheWrite = [int]$usage.cache_creation_input_tokens
    }
}

function Get-CostFromEvent {
    param(
        [PSObject]$Event
    )

    if ($Event.type -eq "result" -and $null -ne $Event.total_cost_usd) {
        return [double]$Event.total_cost_usd
    }

    return $null
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
            $inputStr = if ($block.input) {
                $block.input | ConvertTo-Json -Depth 5 -Compress
            } else {
                ""
            }

            if ($inputStr.Length -gt 150) {
                $inputStr = $inputStr.Substring(0, 150) + "..."
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
}
