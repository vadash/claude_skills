# Context Limit Check Hook
# Trigger: PreToolUse, matcher: *
# Blocks tool calls when estimated context exceeds token threshold.
# Gated by RALPH_ACTIVE environment variable.

function Test-ContextLimit {
    param(
        [string]$RawInput,
        [string]$RalphActive,
        [string]$ContextLimitValue
    )

    # Gate: only active during auto-execute
    if ($RalphActive -ne "true") {
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
    $fileSize = (Get-Item $transcriptPath).Length
    $estimatedTokens = [math]::Floor($fileSize / 4)

    if ($estimatedTokens -gt $limit) {
        $msg = "CONTEXT LIMIT EXCEEDED (~$estimatedTokens tokens > $limit). DO NOT RETRY. Output '[AUTO-EXECUTE] Task N FAILED. Reason: context limit' and stop immediately."
        return @{ ExitCode = 2; Message = $msg }
    }

    return @{ ExitCode = 0; Message = $null }
}

# Main execution — only when invoked directly (not dot-sourced)
if ($MyInvocation.InvocationName -ne '.') {
    $rawInput = [Console]::In.ReadToEnd()
    $result = Test-ContextLimit -RawInput $rawInput -RalphActive $env:RALPH_ACTIVE -ContextLimitValue $env:RALPH_CONTEXT_LIMIT
    if ($result.Message) {
        [Console]::Error.WriteLine($result.Message)
    }
    exit $result.ExitCode
}
