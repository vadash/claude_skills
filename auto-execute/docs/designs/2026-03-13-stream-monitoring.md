# Stream-JSON Real-Time Monitoring + Token Tracking

**Goal:** Add real-time tool visibility and token usage metrics to auto-execute by parsing the Claude CLI's `--output-format stream-json` output.

**Parent design:** [auto-execute.md](2026-03-13-auto-execute.md)

**Approach:** Replace the initially proposed hook-stderr + transcript-file-hunting approach with a single mechanism: parse stream-json output from the CLI. This gives both real-time tool calls AND token usage from the same stream, with no hook modifications and no fragile file discovery.

---

## Changes Overview

| File | Change |
|------|--------|
| `auto-execute.ps1` | Add `--output-format stream-json`, rewrite tailing loop to parse JSON, add log cleanup, add token aggregation |
| `auto-execute-helpers.ps1` | Add stream parsing + token formatting functions, update `Format-TaskLogEntry` and `Format-FinalReport` with `$TokenString` param |
| `tests/auto-execute-helpers.Tests.ps1` | Add tests for new functions, update tests for changed signatures |
| `loop-detect.ps1` | No changes |
| `context-check.ps1` | No changes |

---

## New Helper Functions (`auto-execute-helpers.ps1`)

### `Read-StreamJsonChunk`

Core parser. Handles partial lines at read boundaries.

**Parameters:**
- `[string]$Chunk` — raw text read from the file
- `[string]$Buffer` — leftover partial line from previous read

**Returns:** hashtable with:
- `Events` — array of parsed PSObjects (one per valid JSON line)
- `Buffer` — remaining partial line for next iteration

**Logic:**
1. Prepend `$Buffer` to `$Chunk`
2. Split by newlines
3. Last piece (if no trailing newline) → new buffer
4. Parse each complete line as JSON via `ConvertFrom-Json`
5. Invalid JSON lines → skip silently

### `Get-TokensFromEvent`

Extracts usage metrics from a parsed stream event.

**Parameters:**
- `[PSObject]$Event` — a parsed stream-json event

**Returns:** hashtable `@{ Input=N; Output=N; CacheRead=N }` or `$null` if no usage data.

**Logic:**
- Check for `$Event.message.usage`
- Extract `input_tokens`, `output_tokens`, `cache_read_input_tokens`
- `cache_creation_input_tokens` is NOT included in "Cached" counter (those are writes to cache, not reads)

### `Format-ToolEvent`

Formats a tool_use event for terminal display.

**Parameters:**
- `[PSObject]$Event` — a parsed stream-json event

**Returns:** formatted string like `"[TOOL] Bash | git status --porcelain"` or `$null` for non-tool events.

**Logic:**
- Check if event represents a tool call (exact field TBD — validate against actual stream-json schema during implementation)
- Truncate tool input to 150 characters
- Return formatted string

### `Format-TokenMetrics`

Formats token counters into a display string.

**Parameters:**
- `[hashtable]$Metrics` — `@{ Input=N; Output=N; Cached=N; Total=N; HitRate=F }`

**Returns:** `" | Tokens: 1.5k In, 200 Out, 10.0k Cached (87.0% hit rate)"` or `""` if total is zero.

**Logic:**
- Format numbers: `>= 1M` → `"1.5M"`, `>= 1k` → `"1.5k"`, else raw number
- Hit rate: `cache_read / (input + cache_read) * 100`

### `Clear-LogDirectory`

Removes old log files at the start of each run.

**Parameters:**
- `[string]$LogDir` — path to log directory

**Logic:**
- Delete all `*.log` and `*.log.err` files in `$LogDir`
- Preserve the directory itself
- Runs after pre-flight checks, before the first task

---

## Updated Existing Functions

### `Format-TaskLogEntry`

**New parameter:** `[string]$TokenString = ""` — appended to the end of the log line.

Before: `[04:22:25] Task 1: PASS (commit 744443d, 2m 15s)`
After:  `[04:22:25] Task 1: PASS (commit 744443d, 2m 15s) | Tokens: 45.2k In, 3.1k Out, 38.0k Cached (84.1% hit rate)`

### `Format-FinalReport`

**New parameter:** `[string]$TokenString = ""` — appended to the duration line.

```
=== Auto-Execute Summary ===
Plan:       docs/plans/2026-03-13-feature.md
Tasks:      4/4 completed
Duration:   12m 55s | Tokens: 180.5k In, 12.4k Out, 152.0k Cached (84.3% hit rate)
Stop reason: All tasks complete
Logs:       logs/auto-execute/run-20260313-042010.log
```

---

## Tailing Loop Redesign (`auto-execute.ps1`)

### CLI Invocation Change

Add `--output-format stream-json` to the argument list:

```powershell
$argString = "-p `"$promptText`" --dangerously-skip-permissions --max-turns $MaxTurns --output-format stream-json"
```

Remove `--no-color` (not needed — output is JSON, no ANSI codes).

### New Tailing Logic

Replace the current raw-text tailing with JSON-aware parsing:

```
$buffer = ""
$taskTokens = @{ Input=0; Output=0; Cached=0; Total=0; HitRate=0 }

while (-not $exited) {
    $exited = $process.WaitForExit(200)

    # Read new bytes from log file
    <read new content from $taskLogPath since $lastSize>

    if ($newContent) {
        $parsed = Read-StreamJsonChunk -Chunk $newContent -Buffer $buffer
        $buffer = $parsed.Buffer

        foreach ($event in $parsed.Events) {
            # Display tool calls
            $toolDisplay = Format-ToolEvent -Event $event
            if ($toolDisplay) {
                Write-Host $toolDisplay -ForegroundColor DarkGray
            }

            # Accumulate tokens
            $usage = Get-TokensFromEvent -Event $event
            if ($usage) {
                $taskTokens.Input += $usage.Input
                $taskTokens.Output += $usage.Output
                $taskTokens.Cached += $usage.CacheRead
            }
        }

        $lastSize = <new position>
    }

    # Timeout check (unchanged)
}

# Finalize task token metrics
$taskTokens.Total = $taskTokens.Input + $taskTokens.Output + $taskTokens.Cached
$totalInput = $taskTokens.Input + $taskTokens.Cached
if ($totalInput -gt 0) {
    $taskTokens.HitRate = [math]::Round(($taskTokens.Cached / $totalInput) * 100, 1)
}
$tokenStr = Format-TokenMetrics -Metrics $taskTokens
```

### Log Cleanup

After pre-flight checks pass and before the main loop starts:

```powershell
Clear-LogDirectory -LogDir $LogDir
```

### Token Aggregation

Maintain `$overallMetrics` hashtable across tasks (same as proposed). Accumulate per-task tokens into it. Format for the final report.

---

## Stream-JSON Format Validation

The exact event schema for `--output-format stream-json` must be captured during implementation. The parser is designed to be resilient — it only extracts known fields and ignores everything else.

**First implementation step:** Run a short test command:
```powershell
claude -p "say hello" --output-format stream-json --max-turns 1 > sample.jsonl
```
Capture the output and validate the parser against the actual event types and field names.

Key fields to validate:
- How tool_use events are structured (field names for tool name and input)
- Where `usage` data lives (likely `message.usage` on assistant response events)
- Whether the final `result` event includes summary usage/cost
- Whether `cache_read_input_tokens` and `cache_creation_input_tokens` are present

---

## Testing Strategy

### New Tests

| Test | What it validates |
|------|-------------------|
| `Read-StreamJsonChunk` basic parsing | Valid JSON lines → parsed events |
| `Read-StreamJsonChunk` partial lines | Incomplete last line → buffered, returned on next call |
| `Read-StreamJsonChunk` invalid JSON | Malformed lines → skipped, no error |
| `Get-TokensFromEvent` with usage | Extracts input/output/cached from event with `message.usage` |
| `Get-TokensFromEvent` without usage | Returns null for events without usage data |
| `Format-ToolEvent` tool_use | Formats tool name + truncated input |
| `Format-ToolEvent` non-tool | Returns null for non-tool events |
| `Format-TokenMetrics` thousands | `1.5k In, 200 Out, 10.0k Cached (87.0% hit rate)` |
| `Format-TokenMetrics` millions | `1.5M In, 200 Out, 10.0k Cached (0.7% hit rate)` |
| `Format-TokenMetrics` zero | Returns empty string |
| `Clear-LogDirectory` | Removes `.log` and `.log.err` files, preserves directory |

### Updated Tests

- `Format-TaskLogEntry` — add cases with `$TokenString` parameter
- `Format-FinalReport` — add cases with `$TokenString` parameter

---

## Deliverables

| # | What |
|---|------|
| 1 | Validate stream-json schema with a test capture |
| 2 | Add new helper functions to `auto-execute-helpers.ps1` |
| 3 | Update `Format-TaskLogEntry` and `Format-FinalReport` signatures |
| 4 | Rewrite tailing loop in `auto-execute.ps1` |
| 5 | Add log cleanup to `auto-execute.ps1` |
| 6 | Add/update Pester tests |
