# src/stream.ps1 — Stream JSON parsing and transcript reading

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

function Get-ContextSizeFromEvent {
    param(
        [PSObject]$Event
    )

    if ($Event.type -eq "result") { return 0 }

    $usage = $null
    if ($null -ne $Event.message -and $null -ne $Event.message.usage) {
        $usage = $Event.message.usage
    } elseif ($null -ne $Event.usage) {
        $usage = $Event.usage
    }

    if ($null -ne $usage) {
        $in = if ($null -ne $usage.input_tokens) { [int]$usage.input_tokens } else { 0 }
        $cache = if ($null -ne $usage.cache_read_input_tokens) { [int]$usage.cache_read_input_tokens } else { 0 }
        return $in + $cache
    }

    return 0
}

function Get-ClaudeProjectHash {
    param(
        [Parameter(Mandatory)]
        [string]$DirPath
    )

    return ($DirPath -replace '[^a-zA-Z0-9]', '-')
}

function Get-TranscriptContextPeak {
    param(
        [Parameter(Mandatory)]
        [string]$TranscriptPath,
        [long]$StartOffset = 0
    )

    if (-not (Test-Path $TranscriptPath)) {
        return @{ PeakContext = 0; BytesRead = $StartOffset }
    }

    $stream = [System.IO.File]::Open(
        $TranscriptPath,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::ReadWrite
    )
    try {
        $null = $stream.Seek($StartOffset, [System.IO.SeekOrigin]::Begin)
        $reader = New-Object System.IO.StreamReader($stream)
        $content = $reader.ReadToEnd()
        $endPos = $stream.Position
    } finally {
        $stream.Close()
    }

    $peakContext = 0
    foreach ($line in ($content -split "`n")) {
        $trimmed = $line.Trim()
        if ($trimmed -eq "") { continue }
        try {
            $entry = $trimmed | ConvertFrom-Json
            $usage = $null
            if ($entry.message -and $entry.message.usage) {
                $usage = $entry.message.usage
            }
            if ($usage) {
                $in = if ($null -ne $usage.input_tokens) { [int]$usage.input_tokens } else { 0 }
                $cacheRead = if ($null -ne $usage.cache_read_input_tokens) { [int]$usage.cache_read_input_tokens } else { 0 }
                $cacheCreate = if ($null -ne $usage.cache_creation_input_tokens) { [int]$usage.cache_creation_input_tokens } else { 0 }
                $ctx = $in + $cacheRead + $cacheCreate
                if ($ctx -gt $peakContext) { $peakContext = $ctx }
            }
        } catch {
        }
    }

    return @{ PeakContext = $peakContext; BytesRead = $endPos }
}