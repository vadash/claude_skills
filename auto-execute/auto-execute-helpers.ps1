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
