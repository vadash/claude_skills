# Design: Robustness Improvements

Date: 2026-03-14

Addresses bugs, false positives, wasted tokens, and architectural fragility identified from production runs and code review.

## Major Changes

### 1. Task Splitting & Validation

**Problem:** Every task wastes 1-2 turns re-reading the full plan file. The parser only extracts the max task number, so gaps in numbering (Tasks 1, 2, 4 — no 3) cause the loop to ask Claude for a nonexistent task. Passing extracted markdown through the CLI prompt string risks shell injection from special characters.

**Solution:** New pre-flight stage that parses the plan into individual task blocks, validates numbering, and writes per-task temp files.

#### Parser: `Get-PlanTasks`

Replaces `Get-TotalTaskCount`. Returns an array of task objects instead of a single int.

```powershell
# Input: raw plan content
# Output: @( @{Number=1; Content="..."}, @{Number=2; Content="..."}, ... )
function Get-PlanTasks {
    param([string]$PlanContent)
    # ...
}
```

Regex changes from `(?m)^###\s+Task\s+(\d+)` to `(?mi)^#{2,3}\s*Task\s+(\d+)` — accepts `##` and `###`, case-insensitive, tolerates spacing variations. Each task's content is everything from its header to the next task header (or EOF).

The main loop changes from `while ($currentTask -le $totalTasks) { $currentTask++ }` to iterating over the actual array of parsed tasks.

#### Gap Detection

After parsing, compare found task numbers against a perfect `1..N` sequence. If gaps exist, prompt before starting:

```
WARNING: Gap in task numbering. Found tasks: 1, 2, 4, 5 (missing: 3).
Continue anyway? [Y/n]
```

This catches authoring errors before wasting money on a doomed run.

#### Per-Task Temp Files

Before launching Claude for task N, write the extracted task content to `logs/auto-execute/task-N.md`. Append a footer linking the full plan:

```markdown
---
Full plan: docs/plans/2026-03-14-example.md
If this task references other tasks or you need broader context, read the full plan above.
```

The CLI prompt becomes static and shell-safe:

```
-p "/auto-execute logs/auto-execute/task-N.md"
```

No markdown content passes through the command line. Claude reads a small focused file on its first turn instead of the entire plan.

#### Cleanup

Temp task files (`logs/auto-execute/task-*.md`) are cleared at run start alongside existing log cleanup in `Clear-LogDirectory`. The `logs/` directory is already gitignored.

#### SKILL.md Update

The skill's input parsing changes. Instead of receiving a plan path + task number, it receives a single temp file path. The file contains exactly one task's content plus a link to the full plan. Update the Input section accordingly.

#### Changes to existing functions

| Function | Current | New |
|----------|---------|-----|
| `Get-TotalTaskCount` | Returns max task number (int) | **Replaced by** `Get-PlanTasks` returning array of `@{Number; Content}` |
| `Clear-LogDirectory` | Deletes `*.log` and `*.log.err` | Also deletes `task-*.md` temp files |
| `Split-AxeArguments` | Unchanged | Unchanged |
| Main loop variable | `$currentTask` increments `1..max` | Iterates over `$tasks` array |

### 2. Remove Loop Detector

**Problem:** The `axe-loop-detect.ps1` hook produces false positives during normal TDD cycles. Running `npm test` 3 times in a window of 10 calls (with edits between) triggers the detector, even though Claude is making progress. The hook also adds disk I/O overhead (JSONL writes to `$env:TEMP` on every tool call).

**Solution:** Delete the hook entirely. Three native circuit breakers already cover all loop scenarios:

| Guard | What it catches |
|-------|----------------|
| `MaxTurns` (default 80) | Claude Code enforces this natively via `error_max_turns`. Mathematical halt guarantee. |
| `ContextLimit` (default 100k) | Transcript-based polling kills the process in real-time when context exceeds threshold. Catches runaway token consumption. |
| `TaskTimeout` (default 600s, activity-based — see below) | Catches hanging bash commands and true infinite loops where Claude produces no output. |

#### Files to delete

- `.claude/hooks/axe-loop-detect.ps1`

#### Files to update

- `.claude/settings.json` — remove the hook registration (the `PreToolUse` matcher entry). If no other hooks remain, the `hooks` key can be empty or removed.
- `auto-execute.ps1` — remove the temp file cleanup (`axe-calls-*.jsonl`) at task boundaries and in the `finally` block. Remove `$env:AXE_ACTIVE` set/cleanup. Remove the `AXE_ACTIVE` env var entirely (no remaining consumers).
- `auto-execute-helpers.ps1` — remove `Get-ProjectHooksStatus`, `Install-ProjectHooks`, `Compare-NormalizedFileContent`. These exist solely for hook auto-installation.
- `auto-execute.ps1` — remove Phase 1.5 (Hook Auto-Installer) entirely.
- `CLAUDE.md` / `README.md` — update architecture table, safety guards list, file map, and hook references.
- Tests — remove `loop-detect.Tests.ps1`, update any helper tests that reference hook functions.

### 3. Activity-Based Timeout

**Problem:** The current wall-clock `TaskTimeout` (900s) kills Claude even when it's actively making progress on complex tasks. A task with slow E2E tests can legitimately take 10+ minutes while producing output the whole time. Conversely, a truly stuck process (hanging bash command, Claude producing nothing) should be killed faster than 15 minutes.

**Solution:** Replace wall-clock timeout with an activity-based (idle) timeout. Reset the timer every time a valid stream-json event is received. Kill only when Claude has been silent for the timeout duration.

#### Implementation

```powershell
# Before the inner while loop
$lastActivity = [System.Diagnostics.Stopwatch]::StartNew()

# Inside the event processing (after parsing stream-json events)
if ($parsed.Events.Count -gt 0) {
    $lastActivity.Restart()
}

# Replace the current timeout check
if (-not $exited -and $lastActivity.Elapsed.TotalSeconds -gt $TaskTimeout) {
    Write-Host "`n[TIMEOUT] Task $currentTask idle for $TaskTimeout seconds." -ForegroundColor Red
    # ... kill process
}
```

Default changes from 900s to 600s. A 10-minute idle window is generous — if Claude produces zero output for 10 minutes, something is genuinely stuck.

The parameter name stays `-TaskTimeout` for backwards compatibility, but the semantics change. Document clearly that it now measures idle time, not wall-clock time.

## Minor Fixes

### 4. Empty Commits for No-Op Tasks

**Problem:** `Test-TaskSuccess` requires a new commit. Tasks that need no code changes (research, verification, already-correct code) fail the check, triggering stash/retry/failure for no reason.

**Fix:** Add to SKILL.md:

> If a task requires NO code changes (e.g., research, verification, or the code is already correct), create an empty commit: `git commit --allow-empty -m "task N: no changes needed"`. The automation wrapper requires a new commit hash to register success.

No wrapper changes needed — `$afterHash -ne $beforeHash` passes with an empty commit.

### 5. Stash Drop on Backup Success

**Problem:** When main Claude fails with dirty tree, changes are stashed. If backup Claude succeeds (making its own different changes), `git stash pop` causes merge conflicts because the stashed changes are from a failed attempt on the same files.

**Fix:** Change `git stash pop` to `git stash drop` after successful backup retry. The stashed state is garbage from a failed attempt — the backup Claude's successful commit is the correct state.

```powershell
# Current (in success branch):
if ($stashedThisTask) {
    git stash pop 2>&1 | Out-Null
}

# New:
if ($stashedThisTask) {
    git stash drop 2>&1 | Out-Null
}
```

### 6. Ban TodoWrite in SKILL.md

**Problem:** Claude uses `TodoWrite` for micro-step tracking within a single task (observed in Task 8 logs — 6 `TodoWrite` calls). Each call burns a turn and context for no benefit since the task scope fits in immediate reasoning.

**Fix:** Add to SKILL.md under Headless Operation Rules:

> Do NOT use Todo/task-tracking tools (TodoWrite, TaskCreate, etc.). A single task is small enough to track in your reasoning. Keep your context footprint minimal.

### 7. Fix Hook Auto-Install Staging

**Problem:** Phase 1.5 runs `git add .claude/hooks/ .claude/settings.json` then `git commit`. If the user has other files already staged, they get bundled into the hooks commit.

**Fix:** This phase is being removed entirely (see "Remove Loop Detector" above). If hook auto-installation is reintroduced in the future for new hooks, use path-scoped commits:

```powershell
git commit .claude/hooks/ .claude/settings.json -m "chore: add axe safety hooks"
```

This commits only the specified paths regardless of what else is staged.

## Testing Strategy

| Change | Test approach |
|--------|--------------|
| `Get-PlanTasks` parser | Unit tests: various heading formats (`##`/`###`), gaps, single task, content extraction, edge cases (empty plan, no tasks) |
| Gap detection prompt | Unit test for the detection logic; manual test for the interactive Y/N prompt |
| Temp file generation | Unit test: verify file content includes task text + footer with plan link |
| Temp file cleanup | Unit test: `Clear-LogDirectory` removes `task-*.md` alongside logs |
| Loop detector removal | Verify hook files/settings don't reference it; delete `loop-detect.Tests.ps1` |
| Activity-based timeout | Unit test: mock stopwatch, verify reset on events, verify kill on idle |
| Empty commits | Manual: run a no-op task, verify `--allow-empty` commit passes verification |
| Stash drop | Existing test coverage for `Save-DirtyState`; add test verifying drop path |
| SKILL.md changes | Review only (prompt changes, no testable code) |
