# AXE Rename + Hook Auto-Installer + Cleaner Tool Output

**Goal:** Three improvements in one pass — rename the `RALPH` prefix to `AXE` across the entire codebase, add automatic hook installation/update for target projects, and make real-time tool output human-readable.

**Parent design:** [auto-execute.md](2026-03-13-auto-execute.md)

**Approach:** Clean cut. No migration from old naming. No backward compatibility.

---

## Feature 1: RALPH → AXE Rename

Global find-and-replace across all implementation files, tests, and docs.

### Environment Variables

| Old | New |
|-----|-----|
| `RALPH_ACTIVE` | `AXE_ACTIVE` |
| `RALPH_CONTEXT_LIMIT` | `AXE_CONTEXT_LIMIT` |

### Temp Files

| Old | New |
|-----|-----|
| `ralph-calls-*.jsonl` | `axe-calls-*.jsonl` |

### Hook Script Filenames

| Old | New |
|-----|-----|
| `.claude/hooks/context-check.ps1` | `.claude/hooks/axe-context-check.ps1` |
| `.claude/hooks/loop-detect.ps1` | `.claude/hooks/axe-loop-detect.ps1` |

### Files Affected

**Implementation:**
- `auto-execute.ps1` — env vars, temp file filter
- `auto-execute-helpers.ps1` — no RALPH references (confirmed)
- `.claude/hooks/context-check.ps1` → renamed + internal references
- `.claude/hooks/loop-detect.ps1` → renamed + internal references
- `.claude/settings.json` — hook command paths

**Tests:**
- `tests/context-check.Tests.ps1` — env var references
- `tests/loop-detect.Tests.ps1` — env var + temp file references

**Docs:**
- `CLAUDE.md`
- `README.md`
- `docs/designs/2026-03-13-auto-execute.md`
- `docs/designs/2026-03-13-stream-monitoring.md` (if any references)
- `docs/plans/2026-03-13-auto-execute.md`
- `docs/plans/2026-03-13-stream-monitoring.md` (if any references)

### Function Parameter Renames

Inside hook scripts, the `Test-ContextLimit` and `Test-LoopDetection` functions use a `-RalphActive` parameter. Rename to `-AxeActive`.

---

## Feature 2: Hook Auto-Installer

### Overview

When `auto-execute.ps1` starts, it checks if the target project has the `axe-` safety hooks installed and up-to-date. Three states, three behaviors:

| State | Condition | Behavior |
|-------|-----------|----------|
| **Missing** | No `axe-` hooks in project | Yellow notice, prompt Y/N. If N → red warning, continue without hooks |
| **Outdated** | `axe-` hooks exist but content differs from source | Auto-update silently, cyan message |
| **Ok** | Content matches source | No output, proceed |

### Execution Order

Hook check runs **after** confirming a clean working tree but **before** the remaining pre-flight checks. The clean-tree check must come first — otherwise `git commit` in Phase 1.5 could accidentally include the user's staged files alongside the hooks.

```
Phase 1: Pre-flight (partial)
  ├── CLI exists?
  ├── Plan file exists?
  ├── Git repo?
  ├── Clean working tree? ← BEFORE hooks (prevents accidental commits)
  │
  ├── Phase 1.5: Hook Auto-Installer ← NEW
  │     ├── Get-ProjectHooksStatus
  │     ├── If Missing → prompt → Install-ProjectHooks → git commit
  │     ├── If Outdated → Install-ProjectHooks → git commit → message
  │     └── If Ok → continue
  │
  ├── Plan has unchecked tasks?
  └── Log directory exists?
```

### New Functions (`auto-execute-helpers.ps1`)

#### `Compare-NormalizedFileContent`

```
Parameters: [string]$PathA, [string]$PathB
Returns:    [bool]
```

Reads both files, normalizes CRLF → LF, compares. Prevents false "Outdated" from line-ending differences across Git clones on different platforms.

#### `Get-ProjectHooksStatus`

```
Parameters: [string]$SourceDir, [string]$GitRoot
Returns:    'Missing' | 'Outdated' | 'Ok'
```

Logic:
1. Check if `axe-context-check.ps1` and `axe-loop-detect.ps1` exist in `<GitRoot>/.claude/hooks/`
2. Check if `<GitRoot>/.claude/settings.json` contains commands referencing both `axe-` scripts
3. If any file or registration missing → `'Missing'`
4. Content-compare each hook against source in `<SourceDir>/.claude/hooks/` → if different, `'Outdated'`
5. Otherwise → `'Ok'`

#### `Install-ProjectHooks`

```
Parameters: [string]$SourceDir, [string]$GitRoot
Returns:    void
```

Logic:
1. Create `<GitRoot>/.claude/hooks/` if needed
2. Copy `axe-context-check.ps1` and `axe-loop-detect.ps1` from `<SourceDir>/.claude/hooks/`
3. Load `<GitRoot>/.claude/settings.json` (or create empty `{}`)
4. Ensure `hooks.PreToolUse` array exists
5. Find existing `matcher: "*"` entry or create one
6. Append our two hook commands to the `hooks[]` array (skip if already present — match by `axe-` in command string)
7. Write back JSON

Hook commands registered in settings.json:
```json
{
  "type": "command",
  "command": "powershell.exe -ExecutionPolicy Bypass -File .claude/hooks/axe-context-check.ps1"
},
{
  "type": "command",
  "command": "powershell.exe -ExecutionPolicy Bypass -File .claude/hooks/axe-loop-detect.ps1"
}
```

### Changes to `auto-execute.ps1`

Split `Test-PreFlightChecks` into two phases:

**Phase 1a** (before hooks): CLI exists, plan file exists, git repo check, clean working tree.
**Phase 1.5**: Hook auto-installer (new code in main script).
**Phase 1b** (after hooks): Unchecked tasks, log directory.

The clean-tree check is in Phase 1a to guarantee that when Phase 1.5 runs `git commit`, only hook files are committed — no accidental inclusion of user's staged changes.

The hook installer block:

```
$gitRoot = (git rev-parse --show-toplevel).Trim()
$hookStatus = Get-ProjectHooksStatus -SourceDir $PSScriptRoot -GitRoot $gitRoot

switch ($hookStatus) {
    'Missing' {
        Write-Host "[NOTICE] Safety hooks not installed in this project." -Yellow
        $response = Read-Host "Install them? [Y/n]"
        if (empty or 'y') {
            Install-ProjectHooks ...
            git add .claude/hooks/ .claude/settings.json
            git commit -m "chore: add axe safety hooks"
            Write-Host "Hooks installed." -Green
        } else {
            Write-Host "WARNING: Running without safety hooks!" -Red
            Start-Sleep 2
        }
    }
    'Outdated' {
        Install-ProjectHooks ...
        git add .claude/hooks/ .claude/settings.json
        git commit -m "chore: update axe safety hooks"
        Write-Host "Safety hooks updated to latest version." -Cyan
    }
    'Ok' { }  # silent
}
```

---

## Feature 3: Cleaner Tool Output

### What Changes

`Format-ToolEvent` in `auto-execute-helpers.ps1`. Instead of serializing the entire `input` object to JSON, extract the human-relevant field per tool type.

### Tool Display Rules

| Tool | Field Extracted | Example Output |
|------|----------------|----------------|
| `Bash` | `.input.command` | `[TOOL] Bash \| npm test 2>&1` |
| `Read` | `.input.file_path` → filename only | `[TOOL] Read \| reporter.test.js` |
| `Write` | `.input.file_path` → filename only | `[TOOL] Write \| index.ts` |
| `Edit` | `.input.file_path` → filename + " (editing)" | `[TOOL] Edit \| index.ts (editing)` |
| `Glob` | `.input.pattern` | `[TOOL] Glob \| **/*.ts` |
| `Grep` | `.input.pattern` | `[TOOL] Grep \| function main` |
| Everything else | JSON fallback (current behavior) | `[TOOL] Agent \| {"prompt":"..."}` |

### Implementation

```powershell
function Format-ToolEvent {
    param([PSObject]$Event)

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
```

Truncation stays at 150 chars. No other functions change.

---

## Testing Strategy

### Feature 1 (Rename)

No new tests. Run existing test suite after rename to verify nothing breaks.

### Feature 2 (Hook Auto-Installer)

| Test | Validates |
|------|-----------|
| `Compare-NormalizedFileContent` identical files | Returns `$true` |
| `Compare-NormalizedFileContent` CRLF vs LF | Returns `$true` (normalized) |
| `Compare-NormalizedFileContent` different content | Returns `$false` |
| `Get-ProjectHooksStatus` no hooks at all | Returns `'Missing'` |
| `Get-ProjectHooksStatus` files exist but no settings.json | Returns `'Missing'` |
| `Get-ProjectHooksStatus` files + settings but outdated content | Returns `'Outdated'` |
| `Get-ProjectHooksStatus` everything matches | Returns `'Ok'` |
| `Install-ProjectHooks` fresh project (no .claude dir) | Creates dir, copies files, creates settings.json |
| `Install-ProjectHooks` existing settings with other hooks | Appends to hooks[] array, preserves existing entries |
| `Install-ProjectHooks` idempotent re-install | Running twice doesn't duplicate hook entries |

### Feature 3 (Cleaner Tool Output)

| Test | Validates |
|------|-----------|
| `Format-ToolEvent` Bash tool | Shows command, not JSON |
| `Format-ToolEvent` Read tool | Shows filename only |
| `Format-ToolEvent` Write tool | Shows filename only |
| `Format-ToolEvent` Edit tool | Shows filename + " (editing)" |
| `Format-ToolEvent` Glob tool | Shows pattern |
| `Format-ToolEvent` Grep tool | Shows pattern |
| `Format-ToolEvent` unknown tool | Falls back to JSON |
| `Format-ToolEvent` long input | Truncates at 150 chars |

Existing tests for `Format-ToolEvent` (truncation, non-tool events, multiple tools) are updated to match new output format.

---

## Deliverables

| # | What |
|---|------|
| 1 | Rename all `RALPH` → `AXE` references across implementation, tests, and docs |
| 2 | Rename hook files: `context-check.ps1` → `axe-context-check.ps1`, `loop-detect.ps1` → `axe-loop-detect.ps1` |
| 3 | Rename `-RalphActive` parameter → `-AxeActive` in hook scripts and tests |
| 4 | Add `Compare-NormalizedFileContent`, `Get-ProjectHooksStatus`, `Install-ProjectHooks` to helpers |
| 5 | Split pre-flight checks, insert Phase 1.5 hook installer in `auto-execute.ps1` |
| 6 | Rewrite `Format-ToolEvent` with per-tool extraction |
| 7 | Add new tests, update existing tests |

---

## Review Notes

Findings from external review, evaluated against codebase and prior decisions:

| # | Finding | Verdict | Resolution |
|---|---------|---------|------------|
| 1 | Silent auto-update overwrites user's local hook customizations | **Rejected** | User explicitly chose auto-update for Outdated state. Configurable values (context limit, max turns) are already exposed as parameters/env vars, not hardcoded in hooks. YAGNI. |
| 2 | Dirty tree + `git commit` in Phase 1.5 could accidentally commit user's staged files | **Accepted** | Moved clean-tree check to Phase 1a (before hook installer). Now the tree is guaranteed clean when Phase 1.5 commits. |
| 3 | `Split-Path ""` throws terminating error on empty/null `file_path` | **Accepted** | Replaced `Split-Path` with `[System.IO.Path]::GetFileName()` which safely returns empty string. The `-and $block.input.file_path` guard also catches null, but belt-and-suspenders for robustness. |
