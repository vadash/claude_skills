# Loop Detector Hook
# Trigger: PreToolUse, matcher: *
# Blocks tool calls when Claude is stuck in a loop.
# Gated by RALPH_ACTIVE environment variable.

function Get-InputHash {
    param([string]$Text)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $sha.ComputeHash($bytes)
    return [BitConverter]::ToString($hashBytes).Replace("-", "").Substring(0, 16)
}

function Test-LoopDetection {
    param(
        [string]$RawInput,
        [string]$RalphActive,
        [string]$TempDir,
        [int]$MaxCalls = 100,
        [int]$RepeatThreshold = 3,
        [int]$WindowSize = 10
    )

    # Gate: only active during auto-execute
    if ($RalphActive -ne "true") {
        return @{ ExitCode = 0; Message = $null }
    }

    # Parse hook input
    try {
        $hookData = $RawInput | ConvertFrom-Json
    } catch {
        return @{ ExitCode = 0; Message = $null }
    }

    $tool = $hookData.tool
    $toolInputStr = if ($hookData.tool_input) {
        $hookData.tool_input | ConvertTo-Json -Depth 10 -Compress
    } else {
        ""
    }
    $sessionId = $hookData.session_id

    if (-not $sessionId) {
        return @{ ExitCode = 0; Message = $null }
    }

    # Counter file per session
    $counterFile = Join-Path $TempDir "ralph-calls-$sessionId.jsonl"

    # Normalize and hash the tool call
    $normalized = ($tool + "|" + ($toolInputStr -replace '\s+', ' ')).ToLower()
    $hash = Get-InputHash -Text $normalized

    # Append entry
    $entry = @{ hash = $hash; tool = $tool; ts = (Get-Date -Format o) } | ConvertTo-Json -Compress
    Add-Content -Path $counterFile -Value $entry

    # Count total calls
    $lines = @(Get-Content -Path $counterFile)
    $totalCalls = $lines.Count

    if ($totalCalls -gt $MaxCalls) {
        $msg = "TOO MANY TOOL CALLS (>$MaxCalls). DO NOT RETRY. Output '[AUTO-EXECUTE] Task N FAILED. Reason: stuck/loop detected' and stop immediately."
        return @{ ExitCode = 2; Message = $msg }
    }

    # Check repetition in last N calls
    $recent = $lines | Select-Object -Last $WindowSize | ForEach-Object {
        try { ($_ | ConvertFrom-Json).hash } catch { "" }
    }
    $groups = $recent | Group-Object
    foreach ($g in $groups) {
        if ($g.Name -and $g.Count -ge $RepeatThreshold) {
            $msg = "REPEATED IDENTICAL TOOL CALLS DETECTED. DO NOT RETRY. Output '[AUTO-EXECUTE] Task N FAILED. Reason: loop detected' and stop immediately."
            return @{ ExitCode = 2; Message = $msg }
        }
    }

    return @{ ExitCode = 0; Message = $null }
}

# Main execution — only when invoked directly (not dot-sourced)
if ($MyInvocation.InvocationName -ne '.') {
    $rawInput = [Console]::In.ReadToEnd()
    $tempDir = if ($env:TEMP) { $env:TEMP } else { [System.IO.Path]::GetTempPath() }
    $result = Test-LoopDetection -RawInput $rawInput -RalphActive $env:RALPH_ACTIVE -TempDir $tempDir
    if ($result.Message) {
        [Console]::Error.WriteLine($result.Message)
    }
    exit $result.ExitCode
}
