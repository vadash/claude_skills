# Multi-Claude Failover with Reordered Arguments

## Summary

Reorder CLI arguments so claude binary names come first (better tab-completion), plan path goes last. Add optional backup claude binary — on task failure with main, retry same task with backup before counting toward MaxFailures.

## New CLI Format

```
# Before (removed)
auto-execute <plan> [claude_bin]

# After
auto-execute <main_claude> [backup_claude] <plan>
```

Examples:
```
auto-execute claude_stable_ali mask-endpoint
auto-execute claude_stable_ali claude_stable_any mask-endpoint
auto-execute claude_stable_ali claude_stable_any docs\plans\2026-03-14-mask-endpoint.md
```

Breaking change. Old argument order no longer supported.

## Argument Parsing

Replace the current `$Plan` / `$ClaudeBin` positional params with a single remaining-arguments array:

```powershell
param(
    [Parameter(Mandatory, ValueFromRemainingArguments)] [string[]] $Arguments,
    [int]    $MaxTurns     = 40,
    [int]    $TaskTimeout  = 900,
    [int]    $ContextLimit = 100000,
    [int]    $MaxFailures  = 2,
    [int]    $StartTask    = 0,
    [string] $LogDir       = "logs/auto-execute"
)
```

New helper function `Split-AxeArguments`:
- Input: `[string[]] $Arguments`
- Claude binaries always start with `claude` (case-insensitive prefix match)
- Items starting with `claude` → claude binaries list (ordered: first = main, second = backup)
- Remaining item → plan input (passed to existing `Resolve-PlanPath`)
- Returns: `@{ MainClaude; BackupClaude; PlanInput }`
- Validation errors:
  - No plan argument found → error
  - Zero claude binaries → error
  - More than 2 claude binaries → error
  - More than 1 non-claude argument → error

After parsing, existing `$ClaudeBin` and `$Plan` variables are set from the returned object. New `$BackupClaudeBin` variable is `$null` when no backup provided.

## Failover Logic

### New State Variables

```powershell
$backupClaudeBin = $parsed.BackupClaude   # $null if not provided
$useBackup = $false                        # reset to $false at start of each new task
```

### Main Loop Changes

The `$claudeCmd` resolution (currently hardcoded to `$ClaudeBin`) picks between main and backup:

```powershell
$activeClaude = if ($useBackup) { $backupClaudeBin } else { $ClaudeBin }
$claudeCmd = (Get-Command $activeClaude).Source
```

After post-task verification, when a task fails (and it's not cancellation, dirty-tree, or context-limit):

```
if ($backupClaudeBin -and -not $useBackup) {
    # Main failed, backup available — retry same task
    $useBackup = $true
    $consecutiveFailures++
    # DON'T increment $currentTask — loop runs same task again
    continue
} else {
    # Normal failure path (no backup, or backup already tried)
    $consecutiveFailures++
    $useBackup = $false   # reset for next task
    # existing MaxFailures check
}
```

On task success:
```
$useBackup = $false    # reset for next task
$currentTask++
# ... existing success logic
```

### Failure Counting

Each attempt counts independently toward `$consecutiveFailures`:
- Main fails task 3 → `$consecutiveFailures = 1`, retry with backup
- Backup fails task 3 → `$consecutiveFailures = 2`, hits MaxFailures=2, stop

A successful backup attempt resets `$consecutiveFailures` to 0 (same as current success behavior).

## Log and Display Changes

### Startup Banner

```
CLI: claude_stable_ali (backup: claude_stable_any) | MaxTurns: 40 | Timeout: 900s | ...
```

When no backup:
```
CLI: claude_stable_ali | MaxTurns: 40 | Timeout: 900s | ...
```

### Per-Task Log Entry

Add which binary was used to `Format-TaskLogEntry`:

```
Task 3: PASS [claude_stable_ali] (abc1234, 45s, 50k tok)
Task 3: FAIL [claude_stable_ali] (no new commit, 60s, 30k tok) → retrying with backup
Task 3: PASS [claude_stable_any] (def5678, 55s, 45k tok)
```

### Summary Log

Both attempts appear as separate entries. The summary shows which binary ran each attempt.

## Files Changed

| File | Change |
|------|--------|
| `auto-execute.ps1` | New param block, argument parsing call, `$useBackup` state, `$activeClaude` selection, retry logic after failure |
| `auto-execute-helpers.ps1` | New `Split-AxeArguments` function |
| `auto-execute-helpers.Tests.ps1` | Tests for `Split-AxeArguments` |
| `CLAUDE.md` | Update Running section with new CLI format |

## What Doesn't Change

- Safety guards (hooks, context limit, timeout, dirty tree handling)
- Stream-json parsing, transcript polling
- Post-task verification (3 signals: exit code, new commit, clean tree)
- Hook auto-installer
- `auto-execute.cmd` shim (`%*` forwards all args unchanged)
- `install.ps1`
- `SKILL.md`
