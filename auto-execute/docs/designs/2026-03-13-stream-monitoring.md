# Stream-JSON Real-Time Monitoring + Token Tracking

**Goal:** Add real-time tool visibility and token usage metrics to auto-execute by parsing the Claude CLI's `--output-format stream-json` output.

**Parent design:** [auto-execute.md](2026-03-13-auto-execute.md)

**Approach:** Replace the initially proposed hook-stderr + transcript-file-hunting approach with a single mechanism: parse stream-json output from the CLI. This gives both real-time tool calls AND token usage from the same stream, with no hook modifications and no fragile file discovery.

---

## Validated Stream-JSON Schema

Captured from `claude_stable_age -p "run pwd" --output-format stream-json --verbose --max-turns 2 --dangerously-skip-permissions` (CLI v2.1.71).

The output is **newline-delimited JSON** — one JSON object per line, 5 event types observed:

### Event 1: `system` (init)

```json
{
  "type": "system",
  "subtype": "init",
  "cwd": "C:\\Users\\vadash\\.claude\\skills",
  "session_id": "afb1dc22-...",
  "tools": ["Task", "Bash", "Read", "Edit", "Write", ...],
  "model": "claude-opus-4-6",
  "claude_code_version": "2.1.71"
}
```

### Event 2: `assistant` (tool use)

Tool calls live inside `message.content[]` where `type == "tool_use"`. Full tool input arrives in a **single line** — no delta streaming.

```json
{
  "type": "assistant",
  "message": {
    "model": "claude-opus-4-6",
    "usage": {
      "input_tokens": 2943,
      "cache_creation_input_tokens": 5305,
      "cache_read_input_tokens": 0,
      "output_tokens": 27,
      "cache_creation": {
        "ephemeral_5m_input_tokens": 5305,
        "ephemeral_1h_input_tokens": 0
      }
    },
    "content": [
      {
        "type": "tool_use",
        "id": "toolu_0189x8qFYqnbp3HtirakgiDu",
        "name": "Bash",
        "input": { "command": "pwd", "description": "Print working directory" }
      }
    ]
  },
  "session_id": "afb1dc22-..."
}
```

### Event 3: `user` (tool result)

```json
{
  "type": "user",
  "message": {
    "content": [
      {
        "tool_use_id": "toolu_0189x8qFYqnbp3HtirakgiDu",
        "type": "tool_result",
        "content": "/c/Users/vadash/.claude/skills",
        "is_error": false
      }
    ]
  },
  "tool_use_result": {
    "stdout": "/c/Users/vadash/.claude/skills",
    "stderr": "",
    "interrupted": false
  }
}
```

### Event 4: `assistant` (text response)

```json
{
  "type": "assistant",
  "message": {
    "usage": {
      "input_tokens": 3037,
      "cache_creation_input_tokens": 0,
      "cache_read_input_tokens": 5305,
      "output_tokens": 1
    },
    "content": [
      { "type": "text", "text": "The current working directory is `/c/Users/vadash/.claude/skills`." }
    ]
  }
}
```

### Event 5: `result` (final summary)

Contains aggregate usage, cost, and duration. **This is the authoritative source for per-task token counts.**

```json
{
  "type": "result",
  "subtype": "success",
  "is_error": false,
  "duration_ms": 7903,
  "duration_api_ms": 5853,
  "num_turns": 2,
  "result": "The current working directory is ...",
  "total_cost_usd": 0.06800875,
  "usage": {
    "input_tokens": 5980,
    "cache_creation_input_tokens": 5305,
    "cache_read_input_tokens": 5305,
    "output_tokens": 92,
    "service_tier": "standard"
  },
  "modelUsage": {
    "claude-opus-4-6": {
      "inputTokens": 5980,
      "outputTokens": 92,
      "cacheReadInputTokens": 5305,
      "cacheCreationInputTokens": 5305,
      "costUSD": 0.06800875,
      "contextWindow": 200000,
      "maxOutputTokens": 32000
    }
  },
  "stop_reason": "end_turn"
}
```

### Key Findings

1. **`--verbose` is REQUIRED** — `--output-format stream-json` requires `--verbose` flag with `-p` mode. Without it: `Error: When using --print, --output-format=stream-json requires --verbose`.
2. **Tool calls are NOT delta-streamed** — full tool input arrives in a single JSON line. No need for chunk accumulation.
3. **Cost is available** — `total_cost_usd` in the `result` event gives exact USD cost per task.
4. **Dual token strategy** — accumulate from `assistant` events during tailing (for timeout/crash fallback), but prefer the `result` event's aggregate when available (authoritative).
5. **Encoding** — `Start-Process -RedirectStandardOutput` preserves UTF-8 from the CLI. PowerShell's `>` operator produces UTF-16 BOM (only relevant for manual testing, not for the actual wrapper).

---

## Changes Overview

| File | Change |
|------|--------|
| `auto-execute.ps1` | Add `--output-format stream-json --verbose`, rewrite tailing loop, add log cleanup, add token/cost aggregation, tail stderr for fatal errors |
| `auto-execute-helpers.ps1` | Add stream parsing + token/cost formatting functions, update `Format-TaskLogEntry` and `Format-FinalReport` |
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

**Returns:** hashtable `@{ Input=N; Output=N; CacheRead=N; CacheWrite=N }` or `$null` if no usage data.

**Logic:**
- For `assistant` events: check `$Event.message.usage`
- For `result` events: check `$Event.usage`
- Extract: `input_tokens`, `output_tokens`, `cache_read_input_tokens`, `cache_creation_input_tokens`
- `cache_read_input_tokens` = tokens read FROM cache (cache hits)
- `cache_creation_input_tokens` = tokens written TO cache (tracked separately as `CacheWrite`)

### `Get-CostFromEvent`

Extracts cost from the `result` event.

**Parameters:**
- `[PSObject]$Event` — a parsed stream-json event

**Returns:** `[double]` cost in USD, or `$null` if not a result event.

**Logic:**
- Check `$Event.type -eq "result"` and `$Event.total_cost_usd`
- Return the value

### `Format-ToolEvent`

Formats a tool_use event for terminal display.

**Parameters:**
- `[PSObject]$Event` — a parsed stream-json event

**Returns:** formatted string like `"[TOOL] Bash | pwd"` or `$null` for non-tool events.

**Logic:**
- Check `$Event.type -eq "assistant"`
- Iterate `$Event.message.content` for items where `type -eq "tool_use"`
- Extract `.name` for tool name, `.input` for tool input
- Serialize input to JSON, truncate to 150 characters
- Return one formatted string per tool_use block (an assistant message can contain multiple tool calls)

### `Format-TokenMetrics`

Formats token counters into a display string.

**Parameters:**
- `[hashtable]$Metrics` — `@{ Input=N; Output=N; CacheRead=N; CacheWrite=N; Total=N; HitRate=F; CostUSD=F }`

**Returns:** `" | Tokens: 1.5k In, 200 Out, 10.0k Cache R (87.0% hit) | $0.07"` or `""` if total is zero.

**Logic:**
- Format numbers: `>= 1M` → `"1.5M"`, `>= 1k` → `"1.5k"`, else raw number
- Hit rate: `cache_read / (input + cache_read) * 100`
- Cost: `$X.XX` format, included only if > 0
- `CacheWrite` excluded from display (it inflates perceived cache efficiency). Available in the raw log for post-mortem.

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
After:  `[04:22:25] Task 1: PASS (commit 744443d, 2m 15s) | Tokens: 45.2k In, 3.1k Out, 38.0k Cache R (84.1% hit) | $0.07`

### `Format-FinalReport`

**New parameter:** `[string]$TokenString = ""` — appended to the duration line.

```
=== Auto-Execute Summary ===
Plan:       docs/plans/2026-03-13-feature.md
Tasks:      4/4 completed
Duration:   12m 55s | Tokens: 180.5k In, 12.4k Out, 152.0k Cache R (84.3% hit) | $1.23
Stop reason: All tasks complete
Logs:       logs/auto-execute/run-20260313-042010.log
```

---

## Tailing Loop Redesign (`auto-execute.ps1`)

### CLI Invocation Change

Add `--output-format stream-json --verbose` to the argument list:

```powershell
$argString = "-p `"$promptText`" --dangerously-skip-permissions --max-turns $MaxTurns --output-format stream-json --verbose"
```

Remove `--no-color` (not needed — output is JSON, no ANSI codes).

### New Tailing Logic

Replace the current raw-text tailing with JSON-aware parsing:

```
$buffer = ""
$taskTokens = @{ Input=0; Output=0; CacheRead=0; CacheWrite=0; Total=0; HitRate=0; CostUSD=0 }

while (-not $exited) {
    $exited = $process.WaitForExit(200)

    # Read new bytes from stdout log file
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

            # Accumulate tokens from assistant messages (fallback)
            $usage = Get-TokensFromEvent -Event $event
            if ($usage) {
                $taskTokens.Input += $usage.Input
                $taskTokens.Output += $usage.Output
                $taskTokens.CacheRead += $usage.CacheRead
                $taskTokens.CacheWrite += $usage.CacheWrite
            }

            # Check for authoritative result event
            $cost = Get-CostFromEvent -Event $event
            if ($null -ne $cost) {
                $taskTokens.CostUSD = $cost
                # Overwrite accumulated tokens with result aggregate
                $resultUsage = Get-TokensFromEvent -Event $event
                if ($resultUsage) {
                    $taskTokens.Input = $resultUsage.Input
                    $taskTokens.Output = $resultUsage.Output
                    $taskTokens.CacheRead = $resultUsage.CacheRead
                    $taskTokens.CacheWrite = $resultUsage.CacheWrite
                }
            }
        }

        $lastSize = <new position>
    }

    # Tail stderr for fatal CLI errors (auth failures, API errors, etc.)
    <read new content from "$taskLogPath.err" since $errLastSize>
    if ($newErrContent) {
        Write-Host $newErrContent -NoNewline -ForegroundColor Red
        $errLastSize = <new position>
    }

    # Timeout check (unchanged)
}

# Finalize task token metrics
$taskTokens.Total = $taskTokens.Input + $taskTokens.Output + $taskTokens.CacheRead
$totalInput = $taskTokens.Input + $taskTokens.CacheRead
if ($totalInput -gt 0) {
    $taskTokens.HitRate = [math]::Round(($taskTokens.CacheRead / $totalInput) * 100, 1)
}
$tokenStr = Format-TokenMetrics -Metrics $taskTokens
```

### Stderr Tailing

The tailing loop also reads `$taskLogPath.err` and displays new content in Red. This ensures fatal CLI errors (authentication failures, API 500s, crashes) are visible immediately rather than swallowed until timeout.

### Log Cleanup

After pre-flight checks pass and before the main loop starts:

```powershell
Clear-LogDirectory -LogDir $LogDir
```

### Token Aggregation

Maintain `$overallMetrics` hashtable across tasks. Accumulate per-task tokens and cost into it. Format for the final report.

---

## Design Decisions & Gotcha Resolutions

### Tool input deltas (not an issue)

**Concern:** The Anthropic API streams tool inputs as content_block_delta chunks. If the CLI mirrors this, we'd need to accumulate chunks before displaying.

**Resolution:** Validated experimentally — the CLI's `stream-json` delivers complete tool inputs in a single JSON line. No delta accumulation needed.

### `cache_creation_input_tokens` handling

**Concern:** These tokens cost 25% more than standard input tokens. Dropping them entirely misrepresents cost.

**Resolution:** Track as separate `CacheWrite` field. Excluded from the display string (it would inflate perceived cache efficiency), but included in the raw metrics hashtable for cost accuracy. The `total_cost_usd` from the `result` event already accounts for the 25% premium, so cost display is accurate regardless.

### Fatal CLI errors swallowed

**Concern:** If Claude CLI crashes (auth error, API 500), it writes to stderr. With stream-json on stdout, the error would be invisible until timeout.

**Resolution:** The tailing loop reads both stdout (stream-json) and stderr (raw text). Stderr content is displayed immediately in Red.

### Token source: accumulated vs aggregate

**Concern:** Using per-message accumulation might give slightly different numbers than the result event's aggregate.

**Resolution:** Dual strategy — accumulate from `assistant` events during tailing as a fallback (covers timeout/kill scenarios where no `result` event arrives). When the `result` event is seen, overwrite with its authoritative aggregate.

---

## Testing Strategy

### New Tests

| Test | What it validates |
|------|-------------------|
| `Read-StreamJsonChunk` basic parsing | Valid JSON lines → parsed events |
| `Read-StreamJsonChunk` partial lines | Incomplete last line → buffered, returned on next call |
| `Read-StreamJsonChunk` invalid JSON | Malformed lines → skipped, no error |
| `Read-StreamJsonChunk` empty input | Empty chunk + empty buffer → no events, empty buffer |
| `Get-TokensFromEvent` assistant with usage | Extracts input/output/cacheRead/cacheWrite from `message.usage` |
| `Get-TokensFromEvent` result with usage | Extracts from `usage` (top-level on result event) |
| `Get-TokensFromEvent` without usage | Returns null for events without usage data (system, user) |
| `Get-CostFromEvent` result event | Returns `total_cost_usd` value |
| `Get-CostFromEvent` non-result | Returns null |
| `Format-ToolEvent` tool_use | Formats `[TOOL] Bash \| pwd` from assistant event with tool_use content |
| `Format-ToolEvent` multiple tools | Returns multiple formatted strings for multi-tool assistant messages |
| `Format-ToolEvent` non-tool | Returns null for text-only assistant, user, system, result events |
| `Format-ToolEvent` long input | Truncates tool input to 150 chars |
| `Format-TokenMetrics` thousands | `" \| Tokens: 1.5k In, 200 Out, 10.0k Cache R (87.0% hit) \| $0.07"` |
| `Format-TokenMetrics` millions | `" \| Tokens: 1.5M In, 200 Out, 10.0k Cache R (0.7% hit) \| $1.23"` |
| `Format-TokenMetrics` zero | Returns empty string |
| `Format-TokenMetrics` no cost | Omits cost portion when CostUSD is 0 |
| `Clear-LogDirectory` | Removes `.log` and `.log.err` files, preserves directory and non-log files |

### Updated Tests

- `Format-TaskLogEntry` — add cases with `$TokenString` parameter
- `Format-FinalReport` — add cases with `$TokenString` parameter

---

## Deliverables

| # | What |
|---|------|
| 1 | Add new helper functions to `auto-execute-helpers.ps1` |
| 2 | Update `Format-TaskLogEntry` and `Format-FinalReport` signatures |
| 3 | Rewrite tailing loop in `auto-execute.ps1` with stream-json parsing + stderr tailing |
| 4 | Add `--output-format stream-json --verbose` to CLI args |
| 5 | Add log cleanup to `auto-execute.ps1` |
| 6 | Add/update Pester tests |
