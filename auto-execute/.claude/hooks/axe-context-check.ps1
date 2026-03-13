# Context Limit Check Hook
# Trigger: PreToolUse, matcher: *
# Blocks tool calls when estimated context exceeds token threshold.
# Gated by AXE_ACTIVE environment variable.

function Test-ContextLimit {
    param(
        [string]$RawInput,
        [string]$AxeActive,
        [string]$ContextLimitValue
    )

    # Gate: only active during auto-execute
    if ($AxeActive -ne "true") {
        return @{ ExitCode = 0; Message = $null }
    }

    # Read threshold (default 70000)
    $limit = if ($ContextLimitValue) { [int]$ContextLimitValue } else { 70000 }

    # Parse hook input JSON
    try {
        $hookData = $RawInput | ConvertFrom-Json
        $transcriptPath = $hookData.transcript_path
    } catch {
        return @{ ExitCode = 0; Message = $null }
    }

    if (-not $transcriptPath -or -not (Test-Path $transcriptPath)) {
        return @{ ExitCode = 0; Message = $null }
    }

    # Estimate tokens: file bytes / 4 (O(1) heuristic)
    # Context limit enforcement is now handled accurately in real-time by the auto-execute.ps1
    # wrapper loop using stream-json token counts.
    # This hook remains as a no-op to prevent breaking existing settings.json registrations.

    return @{ ExitCode = 0; Message = $null }
}

# Main execution — only when invoked directly (not dot-sourced)
if ($MyInvocation.InvocationName -ne '.') {
    $rawInput = [Console]::In.ReadToEnd()
    $result = Test-ContextLimit -RawInput $rawInput -AxeActive $env:AXE_ACTIVE -ContextLimitValue $env:AXE_CONTEXT_LIMIT
    if ($result.Message) {
        [Console]::Error.WriteLine($result.Message)
    }
    exit $result.ExitCode
}
