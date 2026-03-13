# Stream Monitoring Implementation Plan

**Goal:** Add real-time tool visibility and token usage metrics to auto-execute by parsing Claude CLI's `--output-format stream-json` output.

**Architecture:** Add 6 new pure functions to `auto-execute-helpers.ps1` for stream-json parsing and formatting, update 2 existing functions to accept token display strings, then rewrite the tailing loop in `auto-execute.ps1` to parse stream-json events instead of raw text — adding stderr tailing, log cleanup, and token aggregation across tasks.

**Tech Stack:** PowerShell 5.1+, Pester 5.x, Claude Code CLI `--output-format stream-json --verbose`.

---

### File Structure

**Modified:**

| # | File | Change |
|---|------|--------|
| 1 | `auto-execute-helpers.ps1` | Add 6 new functions (`Read-StreamJsonChunk`, `Get-TokensFromEvent`, `Get-CostFromEvent`, `Format-ToolEvent`, `Format-TokenMetrics`, `Clear-LogDirectory`), update 2 existing functions (`Format-TaskLogEntry`, `Format-FinalReport`) |
| 2 | `auto-execute.ps1` | Add `--output-format stream-json --verbose` to CLI args, rewrite tailing loop for JSON parsing + stderr tailing, add log cleanup, add per-task and overall token aggregation |
| 3 | `tests/auto-execute-helpers.Tests.ps1` | Add 8 new Describe blocks for new functions, add new It blocks to 2 existing Describe blocks |

**No new files created.**

---

### Task 1: Read-StreamJsonChunk

**Files:**
- Modify: `auto-execute-helpers.ps1`
- Modify: `tests/auto-execute-helpers.Tests.ps1`

- [ ] Step 1: Write the failing tests

Append to `tests/auto-execute-helpers.Tests.ps1`:

```powershell
Describe "Read-StreamJsonChunk" {
    It "parses valid JSON lines into events" {
        $chunk = "{`"type`":`"system`"}`n{`"type`":`"result`"}`n"
        $result = Read-StreamJsonChunk -Chunk $chunk -Buffer ""
        $result.Events.Count | Should -Be 2
        $result.Events[0].type | Should -Be "system"
        $result.Events[1].type | Should -Be "result"
        $result.Buffer | Should -Be ""
    }

    It "buffers incomplete last line" {
        $chunk = "{`"type`":`"system`"}`n{`"type`":`"parti"
        $result = Read-StreamJsonChunk -Chunk $chunk -Buffer ""
        $result.Events.Count | Should -Be 1
        $result.Events[0].type | Should -Be "system"
        $result.Buffer | Should -Be "{`"type`":`"parti"
    }

    It "completes buffered partial line on next call" {
        $result1 = Read-StreamJsonChunk -Chunk "{`"type`":`"sys" -Buffer ""
        $result1.Events.Count | Should -Be 0
        $result1.Buffer | Should -Be "{`"type`":`"sys"

        $result2 = Read-StreamJsonChunk -Chunk "tem`"}`n" -Buffer $result1.Buffer
        $result2.Events.Count | Should -Be 1
        $result2.Events[0].type | Should -Be "system"
        $result2.Buffer | Should -Be ""
    }

    It "skips invalid JSON lines without error" {
        $chunk = "not json`n{`"type`":`"system`"}`nalso bad{{`n"
        $result = Read-StreamJsonChunk -Chunk $chunk -Buffer ""
        $result.Events.Count | Should -Be 1
        $result.Events[0].type | Should -Be "system"
    }

    It "returns empty events and buffer for empty input" {
        $result = Read-StreamJsonChunk -Chunk "" -Buffer ""
        $result.Events.Count | Should -Be 0
        $result.Buffer | Should -Be ""
    }
}
```

- [ ] Step 2: Run tests to verify they fail

Run:
```powershell
Invoke-Pester -Path auto-execute/tests/auto-execute-helpers.Tests.ps1 -Output Detailed
```
Expected: FAIL — `Read-StreamJsonChunk` function not found.

- [ ] Step 3: Write minimal implementation

Append to `auto-execute-helpers.ps1` (before the closing comment or at the end):

```powershell
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
```

- [ ] Step 4: Run tests to verify they pass

Run:
```powershell
Invoke-Pester -Path auto-execute/tests/auto-execute-helpers.Tests.ps1 -Output Detailed
```
Expected: PASS — all tests pass (existing + new).

- [ ] Step 5: Commit

```bash
git add -A && git commit -m "feat: add Read-StreamJsonChunk parser with tests"
```

---

### Task 2: Get-TokensFromEvent

**Files:**
- Modify: `auto-execute-helpers.ps1`
- Modify: `tests/auto-execute-helpers.Tests.ps1`

- [ ] Step 1: Write the failing tests

Append to `tests/auto-execute-helpers.Tests.ps1`:

```powershell
Describe "Get-TokensFromEvent" {
    It "extracts tokens from an assistant event" {
        $json = '{"type":"assistant","message":{"usage":{"input_tokens":2943,"output_tokens":27,"cache_read_input_tokens":0,"cache_creation_input_tokens":5305}}}'
        $event = $json | ConvertFrom-Json
        $result = Get-TokensFromEvent -Event $event
        $result | Should -Not -BeNull
        $result.Input | Should -Be 2943
        $result.Output | Should -Be 27
        $result.CacheRead | Should -Be 0
        $result.CacheWrite | Should -Be 5305
    }

    It "extracts tokens from a result event" {
        $json = '{"type":"result","usage":{"input_tokens":5980,"output_tokens":92,"cache_read_input_tokens":5305,"cache_creation_input_tokens":5305}}'
        $event = $json | ConvertFrom-Json
        $result = Get-TokensFromEvent -Event $event
        $result | Should -Not -BeNull
        $result.Input | Should -Be 5980
        $result.Output | Should -Be 92
        $result.CacheRead | Should -Be 5305
        $result.CacheWrite | Should -Be 5305
    }

    It "returns null for system events (no usage)" {
        $json = '{"type":"system","subtype":"init"}'
        $event = $json | ConvertFrom-Json
        $result = Get-TokensFromEvent -Event $event
        $result | Should -BeNull
    }

    It "returns null for user events (no usage)" {
        $json = '{"type":"user","message":{"content":[{"type":"tool_result","content":"ok"}]}}'
        $event = $json | ConvertFrom-Json
        $result = Get-TokensFromEvent -Event $event
        $result | Should -BeNull
    }
}
```

- [ ] Step 2: Run tests to verify they fail

Run:
```powershell
Invoke-Pester -Path auto-execute/tests/auto-execute-helpers.Tests.ps1 -Output Detailed
```
Expected: FAIL — `Get-TokensFromEvent` function not found.

- [ ] Step 3: Write minimal implementation

Append to `auto-execute-helpers.ps1`:

```powershell
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
```

- [ ] Step 4: Run tests to verify they pass

Run:
```powershell
Invoke-Pester -Path auto-execute/tests/auto-execute-helpers.Tests.ps1 -Output Detailed
```
Expected: PASS — all tests pass.

- [ ] Step 5: Commit

```bash
git add -A && git commit -m "feat: add Get-TokensFromEvent extractor with tests"
```

---

### Task 3: Get-CostFromEvent

**Files:**
- Modify: `auto-execute-helpers.ps1`
- Modify: `tests/auto-execute-helpers.Tests.ps1`

- [ ] Step 1: Write the failing tests

Append to `tests/auto-execute-helpers.Tests.ps1`:

```powershell
Describe "Get-CostFromEvent" {
    It "returns cost from a result event" {
        $json = '{"type":"result","total_cost_usd":0.06800875}'
        $event = $json | ConvertFrom-Json
        $result = Get-CostFromEvent -Event $event
        $result | Should -Be 0.06800875
    }

    It "returns null for an assistant event" {
        $json = '{"type":"assistant","message":{"usage":{"input_tokens":100,"output_tokens":10}}}'
        $event = $json | ConvertFrom-Json
        $result = Get-CostFromEvent -Event $event
        $result | Should -BeNull
    }

    It "returns null for a system event" {
        $json = '{"type":"system","subtype":"init"}'
        $event = $json | ConvertFrom-Json
        $result = Get-CostFromEvent -Event $event
        $result | Should -BeNull
    }
}
```

- [ ] Step 2: Run tests to verify they fail

Run:
```powershell
Invoke-Pester -Path auto-execute/tests/auto-execute-helpers.Tests.ps1 -Output Detailed
```
Expected: FAIL — `Get-CostFromEvent` function not found.

- [ ] Step 3: Write minimal implementation

Append to `auto-execute-helpers.ps1`:

```powershell
function Get-CostFromEvent {
    param(
        [PSObject]$Event
    )

    if ($Event.type -eq "result" -and $null -ne $Event.total_cost_usd) {
        return [double]$Event.total_cost_usd
    }

    return $null
}
```

- [ ] Step 4: Run tests to verify they pass

Run:
```powershell
Invoke-Pester -Path auto-execute/tests/auto-execute-helpers.Tests.ps1 -Output Detailed
```
Expected: PASS — all tests pass.

- [ ] Step 5: Commit

```bash
git add -A && git commit -m "feat: add Get-CostFromEvent extractor with tests"
```

---

### Task 4: Format-ToolEvent

**Files:**
- Modify: `auto-execute-helpers.ps1`
- Modify: `tests/auto-execute-helpers.Tests.ps1`

- [ ] Step 1: Write the failing tests

Append to `tests/auto-execute-helpers.Tests.ps1`:

```powershell
Describe "Format-ToolEvent" {
    It "formats a tool_use event" {
        $json = '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"pwd"}}]}}'
        $event = $json | ConvertFrom-Json
        $result = @(Format-ToolEvent -Event $event)
        $result.Count | Should -Be 1
        $result[0] | Should -Match '^\[TOOL\] Bash \|'
        $result[0] | Should -Match 'pwd'
    }

    It "formats multiple tool_use blocks in one message" {
        $json = '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"config.json"}},{"type":"tool_use","name":"Bash","input":{"command":"echo hello"}}]}}'
        $event = $json | ConvertFrom-Json
        $result = @(Format-ToolEvent -Event $event)
        $result.Count | Should -Be 2
        $result[0] | Should -Match '^\[TOOL\] Read \|'
        $result[1] | Should -Match '^\[TOOL\] Bash \|'
    }

    It "returns null for a text-only assistant event" {
        $json = '{"type":"assistant","message":{"content":[{"type":"text","text":"hello"}]}}'
        $event = $json | ConvertFrom-Json
        $result = Format-ToolEvent -Event $event
        $result | Should -BeNull
    }

    It "returns null for non-assistant events" {
        $json = '{"type":"system","subtype":"init"}'
        $event = $json | ConvertFrom-Json
        $result = Format-ToolEvent -Event $event
        $result | Should -BeNull

        $json2 = '{"type":"user","message":{"content":[{"type":"tool_result","content":"ok"}]}}'
        $event2 = $json2 | ConvertFrom-Json
        $result2 = Format-ToolEvent -Event $event2
        $result2 | Should -BeNull

        $json3 = '{"type":"result","subtype":"success"}'
        $event3 = $json3 | ConvertFrom-Json
        $result3 = Format-ToolEvent -Event $event3
        $result3 | Should -BeNull
    }

    It "truncates long tool input to 150 characters" {
        $longCommand = "a" * 200
        $eventObj = @{
            type = "assistant"
            message = @{
                content = @(
                    @{
                        type = "tool_use"
                        name = "Bash"
                        input = @{ command = $longCommand }
                    }
                )
            }
        } | ConvertTo-Json -Depth 5
        $event = $eventObj | ConvertFrom-Json
        $result = @(Format-ToolEvent -Event $event)[0]
        $result | Should -Match '^\[TOOL\] Bash \|'
        $result | Should -Match '\.\.\.$'
    }
}
```

- [ ] Step 2: Run tests to verify they fail

Run:
```powershell
Invoke-Pester -Path auto-execute/tests/auto-execute-helpers.Tests.ps1 -Output Detailed
```
Expected: FAIL — `Format-ToolEvent` function not found.

- [ ] Step 3: Write minimal implementation

Append to `auto-execute-helpers.ps1`:

```powershell
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
```

- [ ] Step 4: Run tests to verify they pass

Run:
```powershell
Invoke-Pester -Path auto-execute/tests/auto-execute-helpers.Tests.ps1 -Output Detailed
```
Expected: PASS — all tests pass.

- [ ] Step 5: Commit

```bash
git add -A && git commit -m "feat: add Format-ToolEvent display formatter with tests"
```

---

### Task 5: Format-TokenMetrics

**Files:**
- Modify: `auto-execute-helpers.ps1`
- Modify: `tests/auto-execute-helpers.Tests.ps1`

- [ ] Step 1: Write the failing tests

Append to `tests/auto-execute-helpers.Tests.ps1`:

```powershell
Describe "Format-TokenMetrics" {
    It "formats thousands with k suffix" {
        $metrics = @{ Input=1500; Output=200; CacheRead=10000; CacheWrite=0; Total=11700; HitRate=87.0; CostUSD=0.07 }
        $result = Format-TokenMetrics -Metrics $metrics
        $result | Should -Match '1\.5k In'
        $result | Should -Match '200 Out'
        $result | Should -Match '10\.0k Cache R'
        $result | Should -Match '87\.0% hit'
        $result | Should -Match '\$0\.07'
    }

    It "formats millions with M suffix" {
        $metrics = @{ Input=1500000; Output=200; CacheRead=10000; CacheWrite=0; Total=1510200; HitRate=0.7; CostUSD=1.23 }
        $result = Format-TokenMetrics -Metrics $metrics
        $result | Should -Match '1\.5M In'
        $result | Should -Match '200 Out'
        $result | Should -Match '10\.0k Cache R'
        $result | Should -Match '0\.7% hit'
        $result | Should -Match '\$1\.23'
    }

    It "returns empty string when Total is 0" {
        $metrics = @{ Input=0; Output=0; CacheRead=0; CacheWrite=0; Total=0; HitRate=0; CostUSD=0 }
        $result = Format-TokenMetrics -Metrics $metrics
        $result | Should -Be ""
    }

    It "omits cost portion when CostUSD is 0" {
        $metrics = @{ Input=1500; Output=200; CacheRead=10000; CacheWrite=0; Total=11700; HitRate=87.0; CostUSD=0 }
        $result = Format-TokenMetrics -Metrics $metrics
        $result | Should -Match 'Tokens:'
        $result | Should -Not -Match '\$'
    }

    It "returns empty string for null metrics" {
        $result = Format-TokenMetrics -Metrics $null
        $result | Should -Be ""
    }
}
```

- [ ] Step 2: Run tests to verify they fail

Run:
```powershell
Invoke-Pester -Path auto-execute/tests/auto-execute-helpers.Tests.ps1 -Output Detailed
```
Expected: FAIL — `Format-TokenMetrics` function not found.

- [ ] Step 3: Write minimal implementation

Append to `auto-execute-helpers.ps1`:

```powershell
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
```

- [ ] Step 4: Run tests to verify they pass

Run:
```powershell
Invoke-Pester -Path auto-execute/tests/auto-execute-helpers.Tests.ps1 -Output Detailed
```
Expected: PASS — all tests pass.

- [ ] Step 5: Commit

```bash
git add -A && git commit -m "feat: add Format-TokenMetrics display formatter with tests"
```

---

### Task 6: Clear-LogDirectory

**Files:**
- Modify: `auto-execute-helpers.ps1`
- Modify: `tests/auto-execute-helpers.Tests.ps1`

- [ ] Step 1: Write the failing tests

Append to `tests/auto-execute-helpers.Tests.ps1`:

```powershell
Describe "Clear-LogDirectory" {
    BeforeEach {
        $script:tempLogDir = Join-Path ([System.IO.Path]::GetTempPath()) "pester-clear-$(Get-Random)"
        New-Item -ItemType Directory -Path $script:tempLogDir -Force | Out-Null
    }

    AfterEach {
        Remove-Item -Path $script:tempLogDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "removes .log and .log.err files, preserves directory and non-log files" {
        "log content" | Out-File (Join-Path $script:tempLogDir "task-1.log")
        "err content" | Out-File (Join-Path $script:tempLogDir "task-1.log.err")
        "log content" | Out-File (Join-Path $script:tempLogDir "task-2.log")
        "keep me" | Out-File (Join-Path $script:tempLogDir "notes.txt")

        Clear-LogDirectory -LogDir $script:tempLogDir

        Test-Path (Join-Path $script:tempLogDir "task-1.log") | Should -BeFalse
        Test-Path (Join-Path $script:tempLogDir "task-1.log.err") | Should -BeFalse
        Test-Path (Join-Path $script:tempLogDir "task-2.log") | Should -BeFalse
        Test-Path (Join-Path $script:tempLogDir "notes.txt") | Should -BeTrue
        Test-Path $script:tempLogDir | Should -BeTrue
    }

    It "does not error when directory does not exist" {
        { Clear-LogDirectory -LogDir "C:/nonexistent/path/$(Get-Random)" } | Should -Not -Throw
    }

    It "does not error when directory is empty" {
        { Clear-LogDirectory -LogDir $script:tempLogDir } | Should -Not -Throw
    }
}
```

- [ ] Step 2: Run tests to verify they fail

Run:
```powershell
Invoke-Pester -Path auto-execute/tests/auto-execute-helpers.Tests.ps1 -Output Detailed
```
Expected: FAIL — `Clear-LogDirectory` function not found.

- [ ] Step 3: Write minimal implementation

Append to `auto-execute-helpers.ps1`:

```powershell
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
```

- [ ] Step 4: Run tests to verify they pass

Run:
```powershell
Invoke-Pester -Path auto-execute/tests/auto-execute-helpers.Tests.ps1 -Output Detailed
```
Expected: PASS — all tests pass.

- [ ] Step 5: Commit

```bash
git add -A && git commit -m "feat: add Clear-LogDirectory cleanup function with tests"
```

---

### Task 7: Update Format-TaskLogEntry with TokenString

**Files:**
- Modify: `auto-execute-helpers.ps1`
- Modify: `tests/auto-execute-helpers.Tests.ps1`

- [ ] Step 1: Write the failing test

Add the following `It` block inside the existing `Describe "Format-TaskLogEntry"` block in `tests/auto-execute-helpers.Tests.ps1`, after the last existing `It` block:

```powershell
    It "appends token string to passing entry" {
        $duration = [TimeSpan]::FromSeconds(135)
        $tokenStr = " | Tokens: 45.2k In, 3.1k Out, 38.0k Cache R (84.1% hit) | `$0.07"
        $result = Format-TaskLogEntry -TaskNumber 1 -Passed $true -CommitHash "abc1234def" -Duration $duration -TokenString $tokenStr
        $result | Should -Match 'PASS'
        $result | Should -Match '84\.1% hit'
        $result | Should -Match '\$0\.07'
    }

    It "appends token string to failing entry" {
        $duration = [TimeSpan]::FromSeconds(45)
        $tokenStr = " | Tokens: 10.0k In, 1.0k Out, 8.0k Cache R (44.4% hit) | `$0.52"
        $result = Format-TaskLogEntry -TaskNumber 2 -Passed $false -Duration $duration -FailReason "no new commit" -TokenString $tokenStr
        $result | Should -Match 'FAIL'
        $result | Should -Match 'Tokens:'
        $result | Should -Match '\$0\.52'
    }
```

- [ ] Step 2: Run tests to verify the new tests fail

Run:
```powershell
Invoke-Pester -Path auto-execute/tests/auto-execute-helpers.Tests.ps1 -Output Detailed
```
Expected: FAIL — parameter `TokenString` does not exist on `Format-TaskLogEntry`.

- [ ] Step 3: Update the implementation

In `auto-execute-helpers.ps1`, modify the `Format-TaskLogEntry` function:

Add `[string]$TokenString = ""` parameter:

```powershell
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
```

The only changes from the existing function are:
1. Added `[string]$TokenString = ""` parameter
2. Appended `$TokenString` to both PASS and FAIL return strings

Existing callers that don't pass `TokenString` get `""` (no change in output).

- [ ] Step 4: Run tests to verify they pass

Run:
```powershell
Invoke-Pester -Path auto-execute/tests/auto-execute-helpers.Tests.ps1 -Output Detailed
```
Expected: PASS — all existing + new tests pass.

- [ ] Step 5: Commit

```bash
git add -A && git commit -m "feat: add TokenString parameter to Format-TaskLogEntry"
```

---

### Task 8: Update Format-FinalReport with TokenString

**Files:**
- Modify: `auto-execute-helpers.ps1`
- Modify: `tests/auto-execute-helpers.Tests.ps1`

- [ ] Step 1: Write the failing test

Add the following `It` block inside the existing `Describe "Format-FinalReport"` block in `tests/auto-execute-helpers.Tests.ps1`, after the last existing `It` block:

```powershell
    It "appends token string to the duration line" {
        $duration = [TimeSpan]::FromSeconds(775)
        $tokenStr = " | Tokens: 180.5k In, 12.4k Out, 152.0k Cache R (84.3% hit) | `$1.23"
        $result = Format-FinalReport -PlanPath "docs/plans/test.md" `
            -CompletedTasks 4 -TotalTasks 4 `
            -TotalDuration $duration `
            -StopReason "All tasks complete" `
            -LogFile "logs/auto-execute/run.log" `
            -TokenString $tokenStr
        $result | Should -Match '12m 55s'
        $result | Should -Match '84\.3% hit'
        $result | Should -Match '\$1\.23'
    }
```

- [ ] Step 2: Run tests to verify the new test fails

Run:
```powershell
Invoke-Pester -Path auto-execute/tests/auto-execute-helpers.Tests.ps1 -Output Detailed
```
Expected: FAIL — parameter `TokenString` does not exist on `Format-FinalReport`.

- [ ] Step 3: Update the implementation

In `auto-execute-helpers.ps1`, modify the `Format-FinalReport` function:

Add `[string]$TokenString = ""` parameter and append to duration line:

```powershell
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
```

The only changes from the existing function are:
1. Added `[string]$TokenString = ""` parameter
2. Appended `$TokenString` to the duration line

- [ ] Step 4: Run tests to verify they pass

Run:
```powershell
Invoke-Pester -Path auto-execute/tests/auto-execute-helpers.Tests.ps1 -Output Detailed
```
Expected: PASS — all existing + new tests pass.

- [ ] Step 5: Commit

```bash
git add -A && git commit -m "feat: add TokenString parameter to Format-FinalReport"
```

---

### Task 9: Rewrite auto-execute.ps1 Tailing Loop

**Files:**
- Modify: `auto-execute.ps1`

This task modifies the main wrapper script with four changes:
1. Add `--output-format stream-json --verbose` to CLI args
2. Rewrite the tailing loop for JSON-aware parsing + stderr tailing
3. Add log cleanup before the main loop
4. Add per-task and overall token aggregation

- [ ] Step 1: Change CLI args

In `auto-execute.ps1`, find the line:

```powershell
        $claudeArgs = "-p `"$promptText`" --dangerously-skip-permissions --max-turns $MaxTurns"
```

Replace with:

```powershell
        $claudeArgs = "-p `"$promptText`" --dangerously-skip-permissions --max-turns $MaxTurns --output-format stream-json --verbose"
```

- [ ] Step 2: Add log cleanup before main loop

In `auto-execute.ps1`, find the line `Write-Host "CLI: $ClaudeBin | MaxTurns:` (the last info line before `# --- Phase 3: Main Loop ---`).

After that Write-Host line and before `# --- Phase 3: Main Loop ---`, add:

```powershell
# Clean old log files from previous runs
Clear-LogDirectory -LogDir $LogDir
```

- [ ] Step 3: Add overall metrics initialization

In `auto-execute.ps1`, find the line `$stopReason = "Unknown"` (inside Phase 3 initialization).

After that line, add:

```powershell
$overallMetrics = @{ Input=0; Output=0; CacheRead=0; CacheWrite=0; Total=0; HitRate=0; CostUSD=0 }
```

- [ ] Step 4: Rewrite the tailing loop

In `auto-execute.ps1`, find the tailing loop block. Replace from:

```powershell
        # Tail the log file in real-time while monitoring timeout
        $taskExitCode = $null
        $lastSize = 0
        $exited = $false
        while (-not $exited) {
            $exited = $process.WaitForExit(500)

            if (Test-Path $taskLogPath) {
                $stream = [System.IO.File]::Open($taskLogPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                $reader = New-Object System.IO.StreamReader($stream)
                $null = $reader.BaseStream.Seek($lastSize, [System.IO.SeekOrigin]::Begin)
                $newContent = $reader.ReadToEnd()
                if ($newContent) { Write-Host $newContent -NoNewline }
                $lastSize = $reader.BaseStream.Position
                $reader.Close()
            }

            if (-not $exited -and $taskStart.Elapsed.TotalSeconds -gt $TaskTimeout) {
                Write-Host "`n[TIMEOUT] Task $currentTask exceeded $TaskTimeout seconds." -ForegroundColor Red
                & taskkill /F /T /PID $process.Id 2>$null | Out-Null
                $taskExitCode = 1
                $exited = $true
            }
        }
```

With:

```powershell
        # Tail the log file with stream-json parsing
        $taskExitCode = $null
        $lastSize = 0
        $errLastSize = 0
        $exited = $false
        $buffer = ""
        $taskTokens = @{ Input=0; Output=0; CacheRead=0; CacheWrite=0; Total=0; HitRate=0; CostUSD=0 }

        while (-not $exited) {
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
                    }
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

        # Finalize task token metrics
        $taskTokens.Total = $taskTokens.Input + $taskTokens.Output + $taskTokens.CacheRead
        $totalInput = $taskTokens.Input + $taskTokens.CacheRead
        if ($totalInput -gt 0) {
            $taskTokens.HitRate = [math]::Round(($taskTokens.CacheRead / $totalInput) * 100, 1)
        }
        $tokenStr = Format-TokenMetrics -Metrics $taskTokens
```

- [ ] Step 5: Wire token strings into task log entries

In `auto-execute.ps1`, find the success branch inside the `if ($signals.AllPassed)` block. Replace:

```powershell
            $entry = Format-TaskLogEntry -TaskNumber $currentTask -Passed $true `
                -CommitHash $afterHash -Duration $taskDuration
```

With:

```powershell
            $entry = Format-TaskLogEntry -TaskNumber $currentTask -Passed $true `
                -CommitHash $afterHash -Duration $taskDuration -TokenString $tokenStr
```

And in the failure branch, find:

```powershell
            $entry = Format-TaskLogEntry -TaskNumber $currentTask -Passed $false `
                -Duration $taskDuration -FailReason $failReason
```

Replace with:

```powershell
            $entry = Format-TaskLogEntry -TaskNumber $currentTask -Passed $false `
                -Duration $taskDuration -FailReason $failReason -TokenString $tokenStr
```

- [ ] Step 6: Accumulate overall metrics unconditionally

In `auto-execute.ps1`, add the following block **after** the entire `if ($signals.AllPassed) { ... } else { ... }` block and **before** the `# Clean up temp counter files between tasks` comment — so it runs for every task regardless of success or failure:

```powershell
        # Accumulate tokens into overall metrics (regardless of task outcome)
        $overallMetrics.Input += $taskTokens.Input
        $overallMetrics.Output += $taskTokens.Output
        $overallMetrics.CacheRead += $taskTokens.CacheRead
        $overallMetrics.CacheWrite += $taskTokens.CacheWrite
        $overallMetrics.CostUSD += $taskTokens.CostUSD
```

- [ ] Step 7: Wire token string into final report

In `auto-execute.ps1`, find the final report block in the `finally` section. Replace:

```powershell
    $report = Format-FinalReport -PlanPath $Plan -CompletedTasks $completedCount `
        -TotalTasks $totalTasks -TotalDuration $overallStart.Elapsed `
        -StopReason $stopReason -LogFile $summaryLogPath
```

With:

```powershell
    # Finalize overall token metrics
    $overallMetrics.Total = $overallMetrics.Input + $overallMetrics.Output + $overallMetrics.CacheRead
    $overallTotalInput = $overallMetrics.Input + $overallMetrics.CacheRead
    if ($overallTotalInput -gt 0) {
        $overallMetrics.HitRate = [math]::Round(($overallMetrics.CacheRead / $overallTotalInput) * 100, 1)
    }
    $overallTokenStr = Format-TokenMetrics -Metrics $overallMetrics

    $report = Format-FinalReport -PlanPath $Plan -CompletedTasks $completedCount `
        -TotalTasks $totalTasks -TotalDuration $overallStart.Elapsed `
        -StopReason $stopReason -LogFile $summaryLogPath -TokenString $overallTokenStr
```

- [ ] Step 8: Run all tests to verify nothing is broken

Run:
```powershell
Invoke-Pester -Path auto-execute/tests/ -Output Detailed
```
Expected: PASS — all tests across all test files pass.

- [ ] Step 9: Verify the script loads without syntax errors

Run:
```powershell
powershell.exe -ExecutionPolicy Bypass -Command "& { . './auto-execute/auto-execute.ps1' }" 2>&1 | Select-Object -First 5
```
Expected: Error about missing mandatory parameter `$Plan` (confirming the script parses without syntax errors).

- [ ] Step 10: Commit

```bash
git add -A && git commit -m "feat: rewrite tailing loop for stream-json parsing with token tracking"
```
