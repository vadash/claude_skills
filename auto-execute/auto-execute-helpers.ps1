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
        [string]$FailReason,
        [string]$TokenString = ""
    )

    $timestamp = Get-Date -Format "HH:mm:ss"
    $durationStr = "{0}m {1:D2}s" -f [math]::Floor($Duration.TotalMinutes), $Duration.Seconds

    if ($Passed) {
        $shortHash = if ($CommitHash.Length -ge 7) { $CommitHash.Substring(0, 7) } else { $CommitHash }
        return "[$timestamp] Task ${TaskNumber}: PASS (commit $shortHash, $durationStr)$TokenString"
    } else {
        return "[$timestamp] Task ${TaskNumber}: FAIL ($FailReason) — STOPPED$TokenString"
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
        [string]$TokenString = ""
    )

    $durationStr = "{0}m {1:D2}s" -f [math]::Floor($TotalDuration.TotalMinutes), $TotalDuration.Seconds

    return @"
=== Auto-Execute Summary ===
Plan:       $PlanPath
Tasks:      $CompletedTasks/$TotalTasks completed
Duration:   $durationStr$TokenString
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

function Compare-NormalizedFileContent {
    param(
        [Parameter(Mandatory)]
        [string]$PathA,
        [Parameter(Mandatory)]
        [string]$PathB
    )

    $contentA = [System.IO.File]::ReadAllText($PathA).Replace("`r`n", "`n")
    $contentB = [System.IO.File]::ReadAllText($PathB).Replace("`r`n", "`n")
    return $contentA -eq $contentB
}

function Get-ProjectHooksStatus {
    param(
        [Parameter(Mandatory)]
        [string]$SourceDir,
        [Parameter(Mandatory)]
        [string]$GitRoot
    )

    $hookNames = @("axe-context-check.ps1", "axe-loop-detect.ps1")
    $projectHooksDir = Join-Path $GitRoot ".claude/hooks"
    $settingsPath = Join-Path $GitRoot ".claude/settings.json"

    # Check if all hook files exist
    foreach ($hook in $hookNames) {
        $projectPath = Join-Path $projectHooksDir $hook
        if (-not (Test-Path $projectPath)) {
            return 'Missing'
        }
    }

    # Check settings.json exists and references both hooks
    if (-not (Test-Path $settingsPath)) {
        return 'Missing'
    }
    $settingsContent = Get-Content $settingsPath -Raw
    foreach ($hook in $hookNames) {
        if ($settingsContent -notmatch [regex]::Escape($hook)) {
            return 'Missing'
        }
    }

    # Content-compare each hook against source
    foreach ($hook in $hookNames) {
        $sourcePath = Join-Path $SourceDir ".claude/hooks/$hook"
        $projectPath = Join-Path $projectHooksDir $hook
        if (-not (Compare-NormalizedFileContent -PathA $sourcePath -PathB $projectPath)) {
            return 'Outdated'
        }
    }

    return 'Ok'
}

function Install-ProjectHooks {
    param(
        [Parameter(Mandatory)]
        [string]$SourceDir,
        [Parameter(Mandatory)]
        [string]$GitRoot
    )

    $projectHooksDir = Join-Path $GitRoot ".claude/hooks"
    $settingsPath = Join-Path $GitRoot ".claude/settings.json"

    # Create hooks directory if needed
    if (-not (Test-Path $projectHooksDir)) {
        New-Item -ItemType Directory -Path $projectHooksDir -Force | Out-Null
    }

    # Copy hook files
    Copy-Item (Join-Path $SourceDir ".claude/hooks/axe-context-check.ps1") $projectHooksDir -Force
    Copy-Item (Join-Path $SourceDir ".claude/hooks/axe-loop-detect.ps1") $projectHooksDir -Force

    # Define hook commands
    $axeHookCommands = @(
        "powershell.exe -ExecutionPolicy Bypass -File .claude/hooks/axe-context-check.ps1",
        "powershell.exe -ExecutionPolicy Bypass -File .claude/hooks/axe-loop-detect.ps1"
    )

    # Load or create settings
    if (Test-Path $settingsPath) {
        $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
    } else {
        $settings = [PSCustomObject]@{}
    }

    # Ensure hooks.PreToolUse path exists
    if (-not $settings.hooks) {
        $settings | Add-Member -NotePropertyName "hooks" -NotePropertyValue ([PSCustomObject]@{}) -Force
    }
    if (-not $settings.hooks.PreToolUse) {
        $settings.hooks | Add-Member -NotePropertyName "PreToolUse" -NotePropertyValue @() -Force
    }

    # Find or create matcher: "*" entry
    $allEntries = @($settings.hooks.PreToolUse)
    $matcherEntry = $null
    foreach ($entry in $allEntries) {
        if ($entry.matcher -eq "*") {
            $matcherEntry = $entry
            break
        }
    }

    $addNewEntry = $false
    if (-not $matcherEntry) {
        $matcherEntry = [PSCustomObject]@{ matcher = "*"; hooks = @() }
        $addNewEntry = $true
    }

    # Remove existing axe hooks, then add current versions
    $existingHooks = if ($matcherEntry.hooks) { @($matcherEntry.hooks) } else { @() }
    $keptHooks = @($existingHooks | Where-Object { $_.command -notmatch 'axe-' })
    foreach ($cmd in $axeHookCommands) {
        $keptHooks += [PSCustomObject]@{ type = "command"; command = $cmd }
    }
    $matcherEntry.hooks = $keptHooks

    if ($addNewEntry) {
        $allEntries += $matcherEntry
    }

    $settings.hooks.PreToolUse = $allEntries

    # Write back JSON
    $settings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding UTF8
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
}
