# AXE Rename + Hook Auto-Installer + Cleaner Tool Output — Implementation Plan

**Goal:** Rename RALPH→AXE globally, add automatic hook installation for target projects, and make real-time tool output human-readable.
**Architecture:** Mechanical rename across all files (env vars, params, filenames, docs), three new helper functions for hook management (`Compare-NormalizedFileContent`, `Get-ProjectHooksStatus`, `Install-ProjectHooks`), pre-flight split into early/late phases with hook installer between them, and per-tool-type formatting in `Format-ToolEvent`.
**Tech Stack:** PowerShell 5.1+, Pester 5.x

---

### File Structure

**Renamed:**

| Old Path | New Path |
|----------|----------|
| `.claude/hooks/context-check.ps1` | `.claude/hooks/axe-context-check.ps1` |
| `.claude/hooks/loop-detect.ps1` | `.claude/hooks/axe-loop-detect.ps1` |

**Modified:**

| File | Changes |
|------|---------|
| `.claude/settings.json` | Hook command paths updated |
| `auto-execute.ps1` | Env vars renamed, pre-flight split, Phase 1.5 hook installer added |
| `auto-execute-helpers.ps1` | 3 new functions, `Format-ToolEvent` rewritten, `Test-PreFlightChecks` split into Early/Late |
| `tests/context-check.Tests.ps1` | Source path + param/env var names updated |
| `tests/loop-detect.Tests.ps1` | Source path + param/env var/temp file names updated |
| `tests/auto-execute-helpers.Tests.ps1` | New test blocks, `Format-ToolEvent` tests updated, pre-flight tests refactored |
| `CLAUDE.md` | RALPH→AXE, hook filenames updated |
| `README.md` | RALPH→AXE, hook filenames updated |
| `docs/designs/2026-03-13-auto-execute.md` | RALPH→AXE references |
| `docs/plans/2026-03-13-auto-execute.md` | RALPH→AXE references |

---

### Task 1: Rename hook files and update paths

**Files:**
- Rename: `.claude/hooks/context-check.ps1` → `.claude/hooks/axe-context-check.ps1`
- Rename: `.claude/hooks/loop-detect.ps1` → `.claude/hooks/axe-loop-detect.ps1`
- Modify: `.claude/settings.json`
- Modify: `tests/context-check.Tests.ps1`
- Modify: `tests/loop-detect.Tests.ps1`

This is a mechanical rename — no new tests needed, existing tests verify correctness.

- [ ] Step 1: Rename hook files using git mv

```bash
cd C:/Users/vadash/.claude/skills/auto-execute
git mv .claude/hooks/context-check.ps1 .claude/hooks/axe-context-check.ps1
git mv .claude/hooks/loop-detect.ps1 .claude/hooks/axe-loop-detect.ps1
```

- [ ] Step 2: Update `.claude/settings.json` hook command paths

Replace entire file content with:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "powershell.exe -ExecutionPolicy Bypass -File .claude/hooks/axe-context-check.ps1"
          },
          {
            "type": "command",
            "command": "powershell.exe -ExecutionPolicy Bypass -File .claude/hooks/axe-loop-detect.ps1"
          }
        ]
      }
    ]
  }
}
```

- [ ] Step 3: Update test source paths

In `tests/context-check.Tests.ps1`, change the BeforeAll dot-source:

```powershell
# Old:
. "$PSScriptRoot/../.claude/hooks/context-check.ps1"
# New:
. "$PSScriptRoot/../.claude/hooks/axe-context-check.ps1"
```

In `tests/loop-detect.Tests.ps1`, change the BeforeAll dot-source:

```powershell
# Old:
. "$PSScriptRoot/../.claude/hooks/loop-detect.ps1"
# New:
. "$PSScriptRoot/../.claude/hooks/axe-loop-detect.ps1"
```

- [ ] Step 4: Run tests to verify nothing broke

Run: `cd C:/Users/vadash/.claude/skills/auto-execute && pwsh -Command "Invoke-Pester -Path tests/ -Output Detailed"`
Expected: All tests PASS

- [ ] Step 5: Commit

```bash
cd C:/Users/vadash/.claude/skills/auto-execute
git add -A && git commit -m "refactor: rename hook files to axe- prefix"
```

---

### Task 2: Rename RALPH → AXE in hook scripts and tests

**Files:**
- Modify: `.claude/hooks/axe-context-check.ps1`
- Modify: `.claude/hooks/axe-loop-detect.ps1`
- Modify: `tests/context-check.Tests.ps1`
- Modify: `tests/loop-detect.Tests.ps1`

Mechanical rename of parameter names, env vars, comments, temp file patterns. Existing tests verify correctness once updated in parallel.

- [ ] Step 1: Update `.claude/hooks/axe-context-check.ps1`

Four changes in this file:

1. Comment line 4: `# Gated by RALPH_ACTIVE environment variable.` → `# Gated by AXE_ACTIVE environment variable.`
2. Parameter line 9: `[string]$RalphActive,` → `[string]$AxeActive,`
3. Gate line 14: `if ($RalphActive -ne "true") {` → `if ($AxeActive -ne "true") {`
4. Main block line 48: `$result = Test-ContextLimit -RawInput $rawInput -RalphActive $env:RALPH_ACTIVE -ContextLimitValue $env:RALPH_CONTEXT_LIMIT` → `$result = Test-ContextLimit -RawInput $rawInput -AxeActive $env:AXE_ACTIVE -ContextLimitValue $env:AXE_CONTEXT_LIMIT`

- [ ] Step 2: Update `.claude/hooks/axe-loop-detect.ps1`

Five changes in this file:

1. Comment line 4: `# Gated by RALPH_ACTIVE environment variable.` → `# Gated by AXE_ACTIVE environment variable.`
2. Parameter line 17: `[string]$RalphActive,` → `[string]$AxeActive,`
3. Gate line 25: `if ($RalphActive -ne "true") {` → `if ($AxeActive -ne "true") {`
4. Counter file line 49: `$counterFile = Join-Path $TempDir "ralph-calls-$sessionId.jsonl"` → `$counterFile = Join-Path $TempDir "axe-calls-$sessionId.jsonl"`
5. Main block line 87: `$result = Test-LoopDetection -RawInput $rawInput -RalphActive $env:RALPH_ACTIVE -TempDir $tempDir` → `$result = Test-LoopDetection -RawInput $rawInput -AxeActive $env:AXE_ACTIVE -TempDir $tempDir`

- [ ] Step 3: Update `tests/context-check.Tests.ps1`

Replace all `-RalphActive` with `-AxeActive` (9 occurrences). Update test descriptions:

- `"returns ExitCode 0 when RALPH_ACTIVE is not 'true'"` → `"returns ExitCode 0 when AXE_ACTIVE is not 'true'"`
- `"returns ExitCode 0 when RALPH_ACTIVE is unset (null)"` → `"returns ExitCode 0 when AXE_ACTIVE is unset (null)"`

The full updated file:

```powershell
BeforeAll {
    . "$PSScriptRoot/../.claude/hooks/axe-context-check.ps1"
}

Describe "Test-ContextLimit" {
    It "returns ExitCode 0 when AXE_ACTIVE is not 'true'" {
        $result = Test-ContextLimit -RawInput '{}' -AxeActive '' -ContextLimitValue ''
        $result.ExitCode | Should -Be 0
    }

    It "returns ExitCode 0 when AXE_ACTIVE is unset (null)" {
        $result = Test-ContextLimit -RawInput '{}' -AxeActive $null -ContextLimitValue ''
        $result.ExitCode | Should -Be 0
    }

    It "returns ExitCode 0 when transcript_path is missing from input" {
        $result = Test-ContextLimit -RawInput '{"tool": "Bash"}' -AxeActive 'true' -ContextLimitValue '70000'
        $result.ExitCode | Should -Be 0
    }

    It "returns ExitCode 0 when transcript file does not exist" {
        $json = @{ transcript_path = "C:/nonexistent/path/transcript.jsonl" } | ConvertTo-Json
        $result = Test-ContextLimit -RawInput $json -AxeActive 'true' -ContextLimitValue '70000'
        $result.ExitCode | Should -Be 0
    }

    It "returns ExitCode 0 when transcript file is small (under limit)" {
        $tempFile = [System.IO.FileInfo]([System.IO.Path]::GetTempFileName())
        try {
            # 100 bytes -> ~25 tokens, well under 70000
            Set-Content -Path $tempFile.FullName -Value ("x" * 100) -NoNewline
            $json = @{ transcript_path = $tempFile.FullName } | ConvertTo-Json

            $result = Test-ContextLimit -RawInput $json -AxeActive 'true' -ContextLimitValue '70000'
            $result.ExitCode | Should -Be 0
        } finally {
            Remove-Item $tempFile.FullName -ErrorAction SilentlyContinue
        }
    }

    It "returns ExitCode 2 with message when transcript exceeds limit" {
        $tempFile = [System.IO.FileInfo]([System.IO.Path]::GetTempFileName())
        try {
            # 400000 bytes -> ~100000 tokens, over 70000
            [System.IO.File]::WriteAllText($tempFile.FullName, ("x" * 400000))
            $json = @{ transcript_path = $tempFile.FullName } | ConvertTo-Json

            $result = Test-ContextLimit -RawInput $json -AxeActive 'true' -ContextLimitValue '70000'
            $result.ExitCode | Should -Be 2
            $result.Message | Should -Match 'CONTEXT LIMIT EXCEEDED'
            $result.Message | Should -Match 'DO NOT RETRY'
        } finally {
            Remove-Item $tempFile.FullName -ErrorAction SilentlyContinue
        }
    }

    It "uses custom limit from ContextLimitValue parameter" {
        $tempFile = [System.IO.FileInfo]([System.IO.Path]::GetTempFileName())
        try {
            # 100 bytes -> ~25 tokens, over a limit of 10
            Set-Content -Path $tempFile.FullName -Value ("x" * 100) -NoNewline
            $json = @{ transcript_path = $tempFile.FullName } | ConvertTo-Json

            $result = Test-ContextLimit -RawInput $json -AxeActive 'true' -ContextLimitValue '10'
            $result.ExitCode | Should -Be 2
        } finally {
            Remove-Item $tempFile.FullName -ErrorAction SilentlyContinue
        }
    }

    It "defaults to 70000 when ContextLimitValue is empty" {
        $tempFile = [System.IO.FileInfo]([System.IO.Path]::GetTempFileName())
        try {
            Set-Content -Path $tempFile.FullName -Value ("x" * 100) -NoNewline
            $json = @{ transcript_path = $tempFile.FullName } | ConvertTo-Json

            $result = Test-ContextLimit -RawInput $json -AxeActive 'true' -ContextLimitValue ''
            $result.ExitCode | Should -Be 0
        } finally {
            Remove-Item $tempFile.FullName -ErrorAction SilentlyContinue
        }
    }

    It "returns ExitCode 0 when input JSON is invalid" {
        $result = Test-ContextLimit -RawInput 'not valid json {{' -AxeActive 'true' -ContextLimitValue '70000'
        $result.ExitCode | Should -Be 0
    }
}
```

- [ ] Step 4: Update `tests/loop-detect.Tests.ps1`

Replace all `-RalphActive` with `-AxeActive` (10 occurrences). Update test descriptions. Replace `"ralph-calls-s1.jsonl"` with `"axe-calls-s1.jsonl"` (1 occurrence).

The full updated file:

```powershell
BeforeAll {
    . "$PSScriptRoot/../.claude/hooks/axe-loop-detect.ps1"
}

Describe "Get-InputHash" {
    It "returns a consistent hash for the same input" {
        $hash1 = Get-InputHash -Text "hello world"
        $hash2 = Get-InputHash -Text "hello world"
        $hash1 | Should -Be $hash2
    }

    It "returns different hashes for different inputs" {
        $hash1 = Get-InputHash -Text "hello"
        $hash2 = Get-InputHash -Text "world"
        $hash1 | Should -Not -Be $hash2
    }

    It "returns a 16-character hex string" {
        $hash = Get-InputHash -Text "test"
        $hash.Length | Should -Be 16
        $hash | Should -Match '^[0-9A-F]{16}$'
    }
}

Describe "Test-LoopDetection" {
    BeforeEach {
        $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "pester-loop-$(Get-Random)"
        New-Item -ItemType Directory -Path $script:tempDir -Force | Out-Null
    }

    AfterEach {
        Remove-Item -Path $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "returns ExitCode 0 when AXE_ACTIVE is not 'true'" {
        $json = @{ tool = "Bash"; tool_input = @{ command = "echo hi" }; session_id = "s1" } | ConvertTo-Json
        $result = Test-LoopDetection -RawInput $json -AxeActive '' -TempDir $script:tempDir
        $result.ExitCode | Should -Be 0
    }

    It "returns ExitCode 0 when AXE_ACTIVE is null" {
        $json = @{ tool = "Bash"; tool_input = @{ command = "echo hi" }; session_id = "s1" } | ConvertTo-Json
        $result = Test-LoopDetection -RawInput $json -AxeActive $null -TempDir $script:tempDir
        $result.ExitCode | Should -Be 0
    }

    It "returns ExitCode 0 for a normal single call" {
        $json = @{ tool = "Bash"; tool_input = @{ command = "echo hi" }; session_id = "s1" } | ConvertTo-Json
        $result = Test-LoopDetection -RawInput $json -AxeActive 'true' -TempDir $script:tempDir
        $result.ExitCode | Should -Be 0
    }

    It "returns ExitCode 0 when session_id is missing" {
        $json = @{ tool = "Bash"; tool_input = @{ command = "echo hi" } } | ConvertTo-Json
        $result = Test-LoopDetection -RawInput $json -AxeActive 'true' -TempDir $script:tempDir
        $result.ExitCode | Should -Be 0
    }

    It "returns ExitCode 2 when total calls exceed MaxCalls" {
        $counterFile = Join-Path $script:tempDir "axe-calls-s1.jsonl"
        # Pre-populate with 100 entries
        1..100 | ForEach-Object {
            $entry = @{ hash = "unique$_"; tool = "Bash"; ts = (Get-Date -Format o) } | ConvertTo-Json -Compress
            Add-Content -Path $counterFile -Value $entry
        }

        $json = @{ tool = "Bash"; tool_input = @{ command = "echo new" }; session_id = "s1" } | ConvertTo-Json
        $result = Test-LoopDetection -RawInput $json -AxeActive 'true' -TempDir $script:tempDir -MaxCalls 100
        $result.ExitCode | Should -Be 2
        $result.Message | Should -Match 'TOO MANY TOOL CALLS'
    }

    It "returns ExitCode 2 when same call repeats 3 times in last 10" {
        $json = @{ tool = "Bash"; tool_input = @{ command = "echo stuck" }; session_id = "s2" } | ConvertTo-Json

        # First 2 calls pass
        $result1 = Test-LoopDetection -RawInput $json -AxeActive 'true' -TempDir $script:tempDir
        $result1.ExitCode | Should -Be 0

        $result2 = Test-LoopDetection -RawInput $json -AxeActive 'true' -TempDir $script:tempDir
        $result2.ExitCode | Should -Be 0

        # 3rd identical call triggers detection
        $result3 = Test-LoopDetection -RawInput $json -AxeActive 'true' -TempDir $script:tempDir
        $result3.ExitCode | Should -Be 2
        $result3.Message | Should -Match 'REPEATED IDENTICAL TOOL CALLS'
    }

    It "does not trigger repetition when calls are varied" {
        $session = "s3"
        1..10 | ForEach-Object {
            $json = @{ tool = "Bash"; tool_input = @{ command = "echo $_" }; session_id = $session } | ConvertTo-Json
            $result = Test-LoopDetection -RawInput $json -AxeActive 'true' -TempDir $script:tempDir
            $result.ExitCode | Should -Be 0
        }
    }

    It "returns ExitCode 0 when input JSON is invalid" {
        $result = Test-LoopDetection -RawInput 'not json {{' -AxeActive 'true' -TempDir $script:tempDir
        $result.ExitCode | Should -Be 0
    }
}
```

- [ ] Step 5: Run tests to verify

Run: `cd C:/Users/vadash/.claude/skills/auto-execute && pwsh -Command "Invoke-Pester -Path tests/context-check.Tests.ps1,tests/loop-detect.Tests.ps1 -Output Detailed"`
Expected: All tests PASS

- [ ] Step 6: Commit

```bash
cd C:/Users/vadash/.claude/skills/auto-execute
git add -A && git commit -m "refactor: rename RALPH to AXE in hook scripts and tests"
```

---

### Task 3: Rename RALPH → AXE in auto-execute.ps1

**Files:**
- Modify: `auto-execute.ps1`

Six replacements, no new tests needed — existing tests don't test `auto-execute.ps1` directly.

- [ ] Step 1: Update env var assignments (lines 41-42)

```powershell
# Old:
$env:RALPH_ACTIVE = "true"
$env:RALPH_CONTEXT_LIMIT = $ContextLimit
# New:
$env:AXE_ACTIVE = "true"
$env:AXE_CONTEXT_LIMIT = $ContextLimit
```

- [ ] Step 2: Update temp file cleanup in main loop (line 254)

```powershell
# Old:
Get-ChildItem -Path $env:TEMP -Filter "ralph-calls-*.jsonl" -ErrorAction SilentlyContinue |
# New:
Get-ChildItem -Path $env:TEMP -Filter "axe-calls-*.jsonl" -ErrorAction SilentlyContinue |
```

- [ ] Step 3: Update env var cleanup in finally block (lines 265-266)

```powershell
# Old:
$env:RALPH_ACTIVE = $null
$env:RALPH_CONTEXT_LIMIT = $null
# New:
$env:AXE_ACTIVE = $null
$env:AXE_CONTEXT_LIMIT = $null
```

- [ ] Step 4: Update temp file cleanup in finally block (line 276)

```powershell
# Old:
Get-ChildItem -Path $env:TEMP -Filter "ralph-calls-*.jsonl" -ErrorAction SilentlyContinue |
# New:
Get-ChildItem -Path $env:TEMP -Filter "axe-calls-*.jsonl" -ErrorAction SilentlyContinue |
```

- [ ] Step 5: Run tests to verify nothing broke

Run: `cd C:/Users/vadash/.claude/skills/auto-execute && pwsh -Command "Invoke-Pester -Path tests/ -Output Detailed"`
Expected: All tests PASS

- [ ] Step 6: Commit

```bash
cd C:/Users/vadash/.claude/skills/auto-execute
git add -A && git commit -m "refactor: rename RALPH to AXE in auto-execute.ps1"
```

---

### Task 4: Rename RALPH → AXE in docs

**Files:**
- Modify: `CLAUDE.md`
- Modify: `README.md`
- Modify: `docs/designs/2026-03-13-auto-execute.md`
- Modify: `docs/plans/2026-03-13-auto-execute.md`

Mechanical text replacements. No tests needed for documentation.

- [ ] Step 1: Update `CLAUDE.md`

Three changes:
1. `RALPH_ACTIVE` → `AXE_ACTIVE` (line 7, architecture table description)
2. `context-check.ps1` → `axe-context-check.ps1` (if referenced by filename)
3. `loop-detect.ps1` → `axe-loop-detect.ps1` (if referenced by filename)

Apply these replacements with `replace_all`:
- `RALPH_ACTIVE` → `AXE_ACTIVE`

- [ ] Step 2: Update `README.md`

Apply `replace_all` replacements:
- `RALPH_ACTIVE` → `AXE_ACTIVE` (2 occurrences)
- `context-check.ps1` → `axe-context-check.ps1` (all occurrences — file references, code blocks, file map)
- `loop-detect.ps1` → `axe-loop-detect.ps1` (all occurrences)

Also update the Installation section's copy instructions to mention `axe-` prefixed hooks, and update the file map section.

- [ ] Step 3: Update `docs/designs/2026-03-13-auto-execute.md`

Apply `replace_all` replacements:
- `RALPH_ACTIVE` → `AXE_ACTIVE`
- `$env:RALPH_ACTIVE` → `$env:AXE_ACTIVE`
- `RALPH_CONTEXT_LIMIT` → `AXE_CONTEXT_LIMIT`
- `$env:RALPH_CONTEXT_LIMIT` → `$env:AXE_CONTEXT_LIMIT`
- `ralph-calls-` → `axe-calls-`

- [ ] Step 4: Update `docs/plans/2026-03-13-auto-execute.md`

Apply `replace_all` replacements (same set as Step 3 plus parameter rename):
- `RALPH_ACTIVE` → `AXE_ACTIVE`
- `RALPH_CONTEXT_LIMIT` → `AXE_CONTEXT_LIMIT`
- `ralph-calls-` → `axe-calls-`
- `$RalphActive` → `$AxeActive`
- `-RalphActive` → `-AxeActive`
- `RalphActive` → `AxeActive` (for any remaining references like `$env:RALPH_ACTIVE`)

Note: This is a historical plan document. The rename keeps it consistent with the current codebase state.

- [ ] Step 5: Commit

```bash
cd C:/Users/vadash/.claude/skills/auto-execute
git add -A && git commit -m "docs: rename RALPH to AXE across all documentation"
```

---

### Task 5: Rewrite Format-ToolEvent for per-tool extraction

**Files:**
- Modify: `tests/auto-execute-helpers.Tests.ps1` (update existing + add new tests)
- Modify: `auto-execute-helpers.ps1` (rewrite `Format-ToolEvent`)

- [ ] Step 1: Write updated and new tests for Format-ToolEvent

Replace the entire `Describe "Format-ToolEvent"` block in `tests/auto-execute-helpers.Tests.ps1` with:

```powershell
Describe "Format-ToolEvent" {
    It "shows command for Bash tool" {
        $json = '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"npm test 2>&1"}}]}}'
        $event = $json | ConvertFrom-Json
        $result = @(Format-ToolEvent -Event $event)
        $result.Count | Should -Be 1
        $result[0] | Should -Be '[TOOL] Bash | npm test 2>&1'
    }

    It "shows filename only for Read tool" {
        $json = '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"/home/user/project/reporter.test.js"}}]}}'
        $event = $json | ConvertFrom-Json
        $result = @(Format-ToolEvent -Event $event)
        $result[0] | Should -Be '[TOOL] Read | reporter.test.js'
    }

    It "shows filename only for Write tool" {
        $json = '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"/home/user/project/index.ts","content":"hello world"}}]}}'
        $event = $json | ConvertFrom-Json
        $result = @(Format-ToolEvent -Event $event)
        $result[0] | Should -Be '[TOOL] Write | index.ts'
    }

    It "shows filename with (editing) for Edit tool" {
        $json = '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/home/user/project/index.ts","old_string":"foo","new_string":"bar"}}]}}'
        $event = $json | ConvertFrom-Json
        $result = @(Format-ToolEvent -Event $event)
        $result[0] | Should -Be '[TOOL] Edit | index.ts (editing)'
    }

    It "shows pattern for Glob tool" {
        $json = '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Glob","input":{"pattern":"**/*.ts"}}]}}'
        $event = $json | ConvertFrom-Json
        $result = @(Format-ToolEvent -Event $event)
        $result[0] | Should -Be '[TOOL] Glob | **/*.ts'
    }

    It "shows pattern for Grep tool" {
        $json = '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Grep","input":{"pattern":"function main","path":"src/"}}]}}'
        $event = $json | ConvertFrom-Json
        $result = @(Format-ToolEvent -Event $event)
        $result[0] | Should -Be '[TOOL] Grep | function main'
    }

    It "falls back to JSON for unknown tools" {
        $json = '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Agent","input":{"prompt":"do something"}}]}}'
        $event = $json | ConvertFrom-Json
        $result = @(Format-ToolEvent -Event $event)
        $result[0] | Should -Match '^\[TOOL\] Agent \|'
        $result[0] | Should -Match '"prompt"'
    }

    It "formats multiple tool_use blocks in one message" {
        $json = '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"/project/config.json"}},{"type":"tool_use","name":"Bash","input":{"command":"echo hello"}}]}}'
        $event = $json | ConvertFrom-Json
        $result = @(Format-ToolEvent -Event $event)
        $result.Count | Should -Be 2
        $result[0] | Should -Be '[TOOL] Read | config.json'
        $result[1] | Should -Be '[TOOL] Bash | echo hello'
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

    It "truncates long input to 150 characters" {
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
        # [TOOL] Bash | = 14 chars, then 147 + ... = 150
        $inputPart = $result.Substring(14)
        $inputPart.Length | Should -Be 150
    }
}
```

- [ ] Step 2: Run tests to verify new tests FAIL

Run: `cd C:/Users/vadash/.claude/skills/auto-execute && pwsh -Command "Invoke-Pester -Path tests/auto-execute-helpers.Tests.ps1 -Output Detailed"`
Expected: FAIL — new tests expect per-tool formatting but current implementation produces JSON for all tools

- [ ] Step 3: Rewrite `Format-ToolEvent` in `auto-execute-helpers.ps1`

Replace the entire `Format-ToolEvent` function with:

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

- [ ] Step 4: Run tests to verify they pass

Run: `cd C:/Users/vadash/.claude/skills/auto-execute && pwsh -Command "Invoke-Pester -Path tests/auto-execute-helpers.Tests.ps1 -Output Detailed"`
Expected: All tests PASS

- [ ] Step 5: Commit

```bash
cd C:/Users/vadash/.claude/skills/auto-execute
git add -A && git commit -m "feat: per-tool formatting in Format-ToolEvent"
```

---

### Task 6: Add Compare-NormalizedFileContent

**Files:**
- Modify: `tests/auto-execute-helpers.Tests.ps1` (add new Describe block)
- Modify: `auto-execute-helpers.ps1` (add new function)

- [ ] Step 1: Write failing tests

Add this Describe block to `tests/auto-execute-helpers.Tests.ps1` (after the last existing Describe block):

```powershell
Describe "Compare-NormalizedFileContent" {
    BeforeEach {
        $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "pester-compare-$(Get-Random)"
        New-Item -ItemType Directory -Path $script:tempDir -Force | Out-Null
    }

    AfterEach {
        Remove-Item -Path $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "returns true for identical files" {
        $fileA = Join-Path $script:tempDir "a.txt"
        $fileB = Join-Path $script:tempDir "b.txt"
        [System.IO.File]::WriteAllText($fileA, "line1`nline2`n")
        [System.IO.File]::WriteAllText($fileB, "line1`nline2`n")
        Compare-NormalizedFileContent -PathA $fileA -PathB $fileB | Should -BeTrue
    }

    It "returns true when only difference is CRLF vs LF" {
        $fileA = Join-Path $script:tempDir "a.txt"
        $fileB = Join-Path $script:tempDir "b.txt"
        [System.IO.File]::WriteAllText($fileA, "line1`r`nline2`r`n")
        [System.IO.File]::WriteAllText($fileB, "line1`nline2`n")
        Compare-NormalizedFileContent -PathA $fileA -PathB $fileB | Should -BeTrue
    }

    It "returns false for different content" {
        $fileA = Join-Path $script:tempDir "a.txt"
        $fileB = Join-Path $script:tempDir "b.txt"
        [System.IO.File]::WriteAllText($fileA, "line1")
        [System.IO.File]::WriteAllText($fileB, "line2")
        Compare-NormalizedFileContent -PathA $fileA -PathB $fileB | Should -BeFalse
    }
}
```

- [ ] Step 2: Run tests to verify they fail

Run: `cd C:/Users/vadash/.claude/skills/auto-execute && pwsh -Command "Invoke-Pester -Path tests/auto-execute-helpers.Tests.ps1 -TagFilter 'Compare-NormalizedFileContent' -Output Detailed"`

Actually, Pester doesn't filter by Describe name with -TagFilter. Use:

Run: `cd C:/Users/vadash/.claude/skills/auto-execute && pwsh -Command "Invoke-Pester -Path tests/auto-execute-helpers.Tests.ps1 -Output Detailed"`
Expected: FAIL with "The term 'Compare-NormalizedFileContent' is not recognized"

- [ ] Step 3: Write implementation

Add this function to `auto-execute-helpers.ps1` (before the `Format-ToolEvent` function):

```powershell
function Compare-NormalizedFileContent {
    param(
        [Parameter(Mandatory)]
        [string]$PathA,
        [Parameter(Mandatory)]
        [string]$PathB
    )

    $contentA = [System.IO.File]::ReadAllText($PathA).Replace("`r`n", "`n")
    $contentB = [System.IO.File]::ReadAllText($PathB).Replace("`r`n", "`n")
    return $contentA -eq $contentB
}
```

- [ ] Step 4: Run tests to verify they pass

Run: `cd C:/Users/vadash/.claude/skills/auto-execute && pwsh -Command "Invoke-Pester -Path tests/auto-execute-helpers.Tests.ps1 -Output Detailed"`
Expected: All tests PASS

- [ ] Step 5: Commit

```bash
cd C:/Users/vadash/.claude/skills/auto-execute
git add -A && git commit -m "feat: add Compare-NormalizedFileContent helper"
```

---

### Task 7: Add Get-ProjectHooksStatus

**Files:**
- Modify: `tests/auto-execute-helpers.Tests.ps1` (add new Describe block)
- Modify: `auto-execute-helpers.ps1` (add new function)

- [ ] Step 1: Write failing tests

Add this Describe block to `tests/auto-execute-helpers.Tests.ps1`:

```powershell
Describe "Get-ProjectHooksStatus" {
    BeforeEach {
        $script:sourceDir = Join-Path ([System.IO.Path]::GetTempPath()) "pester-source-$(Get-Random)"
        $script:gitRoot = Join-Path ([System.IO.Path]::GetTempPath()) "pester-project-$(Get-Random)"

        # Create source hooks
        New-Item -ItemType Directory -Path (Join-Path $script:sourceDir ".claude/hooks") -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $script:sourceDir ".claude/hooks/axe-context-check.ps1"), "# context check v1")
        [System.IO.File]::WriteAllText((Join-Path $script:sourceDir ".claude/hooks/axe-loop-detect.ps1"), "# loop detect v1")
    }

    AfterEach {
        Remove-Item -Path $script:sourceDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $script:gitRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "returns 'Missing' when no hooks directory exists" {
        New-Item -ItemType Directory -Path $script:gitRoot -Force | Out-Null
        Get-ProjectHooksStatus -SourceDir $script:sourceDir -GitRoot $script:gitRoot | Should -Be 'Missing'
    }

    It "returns 'Missing' when hook files exist but no settings.json" {
        $hooksDir = Join-Path $script:gitRoot ".claude/hooks"
        New-Item -ItemType Directory -Path $hooksDir -Force | Out-Null
        Copy-Item (Join-Path $script:sourceDir ".claude/hooks/axe-context-check.ps1") $hooksDir
        Copy-Item (Join-Path $script:sourceDir ".claude/hooks/axe-loop-detect.ps1") $hooksDir
        Get-ProjectHooksStatus -SourceDir $script:sourceDir -GitRoot $script:gitRoot | Should -Be 'Missing'
    }

    It "returns 'Outdated' when files exist with settings but content differs" {
        $hooksDir = Join-Path $script:gitRoot ".claude/hooks"
        New-Item -ItemType Directory -Path $hooksDir -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $hooksDir "axe-context-check.ps1"), "# old version")
        [System.IO.File]::WriteAllText((Join-Path $hooksDir "axe-loop-detect.ps1"), "# loop detect v1")
        $settings = @{
            hooks = @{
                PreToolUse = @(
                    @{
                        matcher = "*"
                        hooks = @(
                            @{ type = "command"; command = "powershell.exe -ExecutionPolicy Bypass -File .claude/hooks/axe-context-check.ps1" }
                            @{ type = "command"; command = "powershell.exe -ExecutionPolicy Bypass -File .claude/hooks/axe-loop-detect.ps1" }
                        )
                    }
                )
            }
        }
        $settingsPath = Join-Path $script:gitRoot ".claude/settings.json"
        $settings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath
        Get-ProjectHooksStatus -SourceDir $script:sourceDir -GitRoot $script:gitRoot | Should -Be 'Outdated'
    }

    It "returns 'Ok' when everything matches" {
        $hooksDir = Join-Path $script:gitRoot ".claude/hooks"
        New-Item -ItemType Directory -Path $hooksDir -Force | Out-Null
        Copy-Item (Join-Path $script:sourceDir ".claude/hooks/axe-context-check.ps1") $hooksDir
        Copy-Item (Join-Path $script:sourceDir ".claude/hooks/axe-loop-detect.ps1") $hooksDir
        $settings = @{
            hooks = @{
                PreToolUse = @(
                    @{
                        matcher = "*"
                        hooks = @(
                            @{ type = "command"; command = "powershell.exe -ExecutionPolicy Bypass -File .claude/hooks/axe-context-check.ps1" }
                            @{ type = "command"; command = "powershell.exe -ExecutionPolicy Bypass -File .claude/hooks/axe-loop-detect.ps1" }
                        )
                    }
                )
            }
        }
        $settingsPath = Join-Path $script:gitRoot ".claude/settings.json"
        $settings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath
        Get-ProjectHooksStatus -SourceDir $script:sourceDir -GitRoot $script:gitRoot | Should -Be 'Ok'
    }
}
```

- [ ] Step 2: Run tests to verify they fail

Run: `cd C:/Users/vadash/.claude/skills/auto-execute && pwsh -Command "Invoke-Pester -Path tests/auto-execute-helpers.Tests.ps1 -Output Detailed"`
Expected: FAIL with "The term 'Get-ProjectHooksStatus' is not recognized"

- [ ] Step 3: Write implementation

Add this function to `auto-execute-helpers.ps1` (after `Compare-NormalizedFileContent`):

```powershell
function Get-ProjectHooksStatus {
    param(
        [Parameter(Mandatory)]
        [string]$SourceDir,
        [Parameter(Mandatory)]
        [string]$GitRoot
    )

    $hookNames = @("axe-context-check.ps1", "axe-loop-detect.ps1")
    $projectHooksDir = Join-Path $GitRoot ".claude/hooks"
    $settingsPath = Join-Path $GitRoot ".claude/settings.json"

    # Check if all hook files exist
    foreach ($hook in $hookNames) {
        $projectPath = Join-Path $projectHooksDir $hook
        if (-not (Test-Path $projectPath)) {
            return 'Missing'
        }
    }

    # Check settings.json exists and references both hooks
    if (-not (Test-Path $settingsPath)) {
        return 'Missing'
    }
    $settingsContent = Get-Content $settingsPath -Raw
    foreach ($hook in $hookNames) {
        if ($settingsContent -notmatch [regex]::Escape($hook)) {
            return 'Missing'
        }
    }

    # Content-compare each hook against source
    foreach ($hook in $hookNames) {
        $sourcePath = Join-Path $SourceDir ".claude/hooks/$hook"
        $projectPath = Join-Path $projectHooksDir $hook
        if (-not (Compare-NormalizedFileContent -PathA $sourcePath -PathB $projectPath)) {
            return 'Outdated'
        }
    }

    return 'Ok'
}
```

- [ ] Step 4: Run tests to verify they pass

Run: `cd C:/Users/vadash/.claude/skills/auto-execute && pwsh -Command "Invoke-Pester -Path tests/auto-execute-helpers.Tests.ps1 -Output Detailed"`
Expected: All tests PASS

- [ ] Step 5: Commit

```bash
cd C:/Users/vadash/.claude/skills/auto-execute
git add -A && git commit -m "feat: add Get-ProjectHooksStatus helper"
```

---

### Task 8: Add Install-ProjectHooks

**Files:**
- Modify: `tests/auto-execute-helpers.Tests.ps1` (add new Describe block)
- Modify: `auto-execute-helpers.ps1` (add new function)

- [ ] Step 1: Write failing tests

Add this Describe block to `tests/auto-execute-helpers.Tests.ps1`:

```powershell
Describe "Install-ProjectHooks" {
    BeforeEach {
        $script:sourceDir = Join-Path ([System.IO.Path]::GetTempPath()) "pester-source-$(Get-Random)"
        $script:gitRoot = Join-Path ([System.IO.Path]::GetTempPath()) "pester-project-$(Get-Random)"

        # Create source hooks
        New-Item -ItemType Directory -Path (Join-Path $script:sourceDir ".claude/hooks") -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $script:sourceDir ".claude/hooks/axe-context-check.ps1"), "# context check v1")
        [System.IO.File]::WriteAllText((Join-Path $script:sourceDir ".claude/hooks/axe-loop-detect.ps1"), "# loop detect v1")
    }

    AfterEach {
        Remove-Item -Path $script:sourceDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $script:gitRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "creates directory, copies files, and creates settings.json for a fresh project" {
        New-Item -ItemType Directory -Path $script:gitRoot -Force | Out-Null

        Install-ProjectHooks -SourceDir $script:sourceDir -GitRoot $script:gitRoot

        Test-Path (Join-Path $script:gitRoot ".claude/hooks/axe-context-check.ps1") | Should -BeTrue
        Test-Path (Join-Path $script:gitRoot ".claude/hooks/axe-loop-detect.ps1") | Should -BeTrue
        Get-Content (Join-Path $script:gitRoot ".claude/hooks/axe-context-check.ps1") -Raw | Should -Match "context check v1"

        $settingsPath = Join-Path $script:gitRoot ".claude/settings.json"
        Test-Path $settingsPath | Should -BeTrue
        $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
        $settings.hooks.PreToolUse | Should -Not -BeNullOrEmpty
        $allHooks = @($settings.hooks.PreToolUse[0].hooks)
        ($allHooks | Where-Object { $_.command -match 'axe-context-check' }) | Should -Not -BeNullOrEmpty
        ($allHooks | Where-Object { $_.command -match 'axe-loop-detect' }) | Should -Not -BeNullOrEmpty
    }

    It "preserves existing hooks in settings.json" {
        New-Item -ItemType Directory -Path (Join-Path $script:gitRoot ".claude") -Force | Out-Null
        $existing = @{
            hooks = @{
                PreToolUse = @(
                    @{
                        matcher = "*"
                        hooks = @(
                            @{ type = "command"; command = "some-other-hook.ps1" }
                        )
                    }
                )
            }
        }
        $existing | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $script:gitRoot ".claude/settings.json")

        Install-ProjectHooks -SourceDir $script:sourceDir -GitRoot $script:gitRoot

        $settings = Get-Content (Join-Path $script:gitRoot ".claude/settings.json") -Raw | ConvertFrom-Json
        $allHooks = @($settings.hooks.PreToolUse[0].hooks)
        $allHooks.Count | Should -Be 3
        ($allHooks | Where-Object { $_.command -match 'some-other-hook' }) | Should -Not -BeNullOrEmpty
        ($allHooks | Where-Object { $_.command -match 'axe-context-check' }) | Should -Not -BeNullOrEmpty
        ($allHooks | Where-Object { $_.command -match 'axe-loop-detect' }) | Should -Not -BeNullOrEmpty
    }

    It "does not duplicate hook entries on re-install" {
        New-Item -ItemType Directory -Path $script:gitRoot -Force | Out-Null

        Install-ProjectHooks -SourceDir $script:sourceDir -GitRoot $script:gitRoot
        Install-ProjectHooks -SourceDir $script:sourceDir -GitRoot $script:gitRoot

        $settings = Get-Content (Join-Path $script:gitRoot ".claude/settings.json") -Raw | ConvertFrom-Json
        $axeHooks = @($settings.hooks.PreToolUse[0].hooks | Where-Object { $_.command -match 'axe-' })
        $axeHooks.Count | Should -Be 2
    }
}
```

- [ ] Step 2: Run tests to verify they fail

Run: `cd C:/Users/vadash/.claude/skills/auto-execute && pwsh -Command "Invoke-Pester -Path tests/auto-execute-helpers.Tests.ps1 -Output Detailed"`
Expected: FAIL with "The term 'Install-ProjectHooks' is not recognized"

- [ ] Step 3: Write implementation

Add this function to `auto-execute-helpers.ps1` (after `Get-ProjectHooksStatus`):

```powershell
function Install-ProjectHooks {
    param(
        [Parameter(Mandatory)]
        [string]$SourceDir,
        [Parameter(Mandatory)]
        [string]$GitRoot
    )

    $projectHooksDir = Join-Path $GitRoot ".claude/hooks"
    $settingsPath = Join-Path $GitRoot ".claude/settings.json"

    # Create hooks directory if needed
    if (-not (Test-Path $projectHooksDir)) {
        New-Item -ItemType Directory -Path $projectHooksDir -Force | Out-Null
    }

    # Copy hook files
    Copy-Item (Join-Path $SourceDir ".claude/hooks/axe-context-check.ps1") $projectHooksDir -Force
    Copy-Item (Join-Path $SourceDir ".claude/hooks/axe-loop-detect.ps1") $projectHooksDir -Force

    # Define hook commands
    $axeHookCommands = @(
        "powershell.exe -ExecutionPolicy Bypass -File .claude/hooks/axe-context-check.ps1",
        "powershell.exe -ExecutionPolicy Bypass -File .claude/hooks/axe-loop-detect.ps1"
    )

    # Load or create settings
    if (Test-Path $settingsPath) {
        $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
    } else {
        $settings = [PSCustomObject]@{}
    }

    # Ensure hooks.PreToolUse path exists
    if (-not $settings.hooks) {
        $settings | Add-Member -NotePropertyName "hooks" -NotePropertyValue ([PSCustomObject]@{}) -Force
    }
    if (-not $settings.hooks.PreToolUse) {
        $settings.hooks | Add-Member -NotePropertyName "PreToolUse" -NotePropertyValue @() -Force
    }

    # Find or create matcher: "*" entry
    $allEntries = @($settings.hooks.PreToolUse)
    $matcherEntry = $null
    foreach ($entry in $allEntries) {
        if ($entry.matcher -eq "*") {
            $matcherEntry = $entry
            break
        }
    }

    $addNewEntry = $false
    if (-not $matcherEntry) {
        $matcherEntry = [PSCustomObject]@{ matcher = "*"; hooks = @() }
        $addNewEntry = $true
    }

    # Remove existing axe hooks, then add current versions
    $existingHooks = if ($matcherEntry.hooks) { @($matcherEntry.hooks) } else { @() }
    $keptHooks = @($existingHooks | Where-Object { $_.command -notmatch 'axe-' })
    foreach ($cmd in $axeHookCommands) {
        $keptHooks += [PSCustomObject]@{ type = "command"; command = $cmd }
    }
    $matcherEntry.hooks = $keptHooks

    if ($addNewEntry) {
        $allEntries += $matcherEntry
    }

    $settings.hooks.PreToolUse = $allEntries

    # Write back JSON
    $settings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding UTF8
}
```

- [ ] Step 4: Run tests to verify they pass

Run: `cd C:/Users/vadash/.claude/skills/auto-execute && pwsh -Command "Invoke-Pester -Path tests/auto-execute-helpers.Tests.ps1 -Output Detailed"`
Expected: All tests PASS

- [ ] Step 5: Commit

```bash
cd C:/Users/vadash/.claude/skills/auto-execute
git add -A && git commit -m "feat: add Install-ProjectHooks helper"
```

---

### Task 9: Split pre-flight checks and add Phase 1.5 hook installer

**Files:**
- Modify: `auto-execute-helpers.ps1` (split `Test-PreFlightChecks` into `Test-PreFlightEarly` and `Test-PreFlightLate`)
- Modify: `tests/auto-execute-helpers.Tests.ps1` (refactor pre-flight tests)
- Modify: `auto-execute.ps1` (Phase 1.5 hook installer, call split functions)
- Modify: `CLAUDE.md` (update architecture description)
- Modify: `README.md` (update safety section, file map)

- [ ] Step 1: Write tests for split pre-flight functions

Replace the entire `Describe "Test-PreFlightChecks"` block in `tests/auto-execute-helpers.Tests.ps1` with:

```powershell
Describe "Test-PreFlightEarly" {
    BeforeEach {
        $script:tempPlan = [System.IO.FileInfo]([System.IO.Path]::GetTempFileName())
        Set-Content $script:tempPlan.FullName "### Task 1: Test`n- [ ] Step 1: Do it"
    }

    AfterEach {
        Remove-Item $script:tempPlan.FullName -ErrorAction SilentlyContinue
    }

    It "returns error when CLI binary does not exist" {
        $errors = Test-PreFlightEarly -ClaudeBin "definitely-not-a-real-command-xyz-123" `
            -PlanPath $script:tempPlan.FullName
        ($errors | Where-Object { $_ -match "not found in PATH" }) | Should -Not -BeNullOrEmpty
    }

    It "returns error when plan file does not exist" {
        $errors = Test-PreFlightEarly -ClaudeBin "cmd" `
            -PlanPath "/nonexistent/plan.md"
        $errors | Should -Contain "Plan file '/nonexistent/plan.md' not found."
    }
}

Describe "Test-PreFlightLate" {
    BeforeEach {
        $script:tempLogDir = Join-Path ([System.IO.Path]::GetTempPath()) "pester-logs-$(Get-Random)"
    }

    AfterEach {
        if (Test-Path $script:tempLogDir) {
            Remove-Item $script:tempLogDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "returns error when plan has no unchecked tasks" {
        $tempPlan = [System.IO.FileInfo]([System.IO.Path]::GetTempFileName())
        try {
            Set-Content $tempPlan.FullName "### Task 1: Done`n- [x] Step 1: Done"
            $errors = Test-PreFlightLate -PlanPath $tempPlan.FullName -LogDir $script:tempLogDir
            ($errors | Where-Object { $_ -match "no unchecked tasks" }) | Should -Not -BeNullOrEmpty
        } finally {
            Remove-Item $tempPlan.FullName -ErrorAction SilentlyContinue
        }
    }

    It "creates log directory if it does not exist" {
        $tempPlan = [System.IO.FileInfo]([System.IO.Path]::GetTempFileName())
        try {
            Set-Content $tempPlan.FullName "### Task 1: Test`n- [ ] Step 1: Do it"
            Test-PreFlightLate -PlanPath $tempPlan.FullName -LogDir $script:tempLogDir | Out-Null
            Test-Path $script:tempLogDir | Should -BeTrue
        } finally {
            Remove-Item $tempPlan.FullName -ErrorAction SilentlyContinue
        }
    }
}
```

- [ ] Step 2: Run tests to verify new tests fail

Run: `cd C:/Users/vadash/.claude/skills/auto-execute && pwsh -Command "Invoke-Pester -Path tests/auto-execute-helpers.Tests.ps1 -Output Detailed"`
Expected: FAIL with "The term 'Test-PreFlightEarly' is not recognized"

- [ ] Step 3: Replace `Test-PreFlightChecks` with `Test-PreFlightEarly` and `Test-PreFlightLate`

In `auto-execute-helpers.ps1`, replace the entire `Test-PreFlightChecks` function with these two functions:

```powershell
function Test-PreFlightEarly {
    param(
        [string]$ClaudeBin,
        [string]$PlanPath
    )

    $errors = @()

    # Check CLI is callable
    if (-not (Get-Command $ClaudeBin -ErrorAction SilentlyContinue)) {
        $errors += "CLI binary '$ClaudeBin' not found in PATH."
    }

    # Check plan file exists
    if (-not (Test-Path $PlanPath)) {
        $errors += "Plan file '$PlanPath' not found."
    }

    # Check git repo
    $null = git rev-parse --git-dir 2>&1
    if ($LASTEXITCODE -ne 0) {
        $errors += "Not inside a git repository."
    }

    # Check clean working tree
    $status = git status --porcelain 2>&1
    if ($status) {
        $errors += "Git working tree is not clean."
    }

    return $errors
}

function Test-PreFlightLate {
    param(
        [string]$PlanPath,
        [string]$LogDir
    )

    $errors = @()

    # Check plan has unchecked tasks
    if (Test-Path $PlanPath) {
        $content = Get-Content $PlanPath -Raw
        if ($content -notmatch '\-\s*\[\s\]') {
            $errors += "Plan file has no unchecked tasks (no '- [ ]' found)."
        }
    }

    # Check/create log directory
    if (-not (Test-Path $LogDir)) {
        try {
            New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
        } catch {
            $errors += "Cannot create log directory '$LogDir': $_"
        }
    }

    return $errors
}
```

- [ ] Step 4: Run tests to verify they pass

Run: `cd C:/Users/vadash/.claude/skills/auto-execute && pwsh -Command "Invoke-Pester -Path tests/auto-execute-helpers.Tests.ps1 -Output Detailed"`
Expected: All tests PASS

- [ ] Step 5: Update `auto-execute.ps1` — replace pre-flight + add Phase 1.5

Replace the pre-flight section (from `# --- Phase 1: Pre-flight Checks ---` through the `.gitignore` warning block, ending before `# Set environment for hooks`) with:

```powershell
# --- Phase 1a: Pre-flight (before hooks) ---
$errors = Test-PreFlightEarly -ClaudeBin $ClaudeBin -PlanPath $Plan
if ($errors.Count -gt 0) {
    Write-Host "Pre-flight checks failed:" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}

# --- Phase 1.5: Hook Auto-Installer ---
$gitRoot = (git rev-parse --show-toplevel 2>&1).ToString().Trim()
$hookStatus = Get-ProjectHooksStatus -SourceDir $PSScriptRoot -GitRoot $gitRoot

switch ($hookStatus) {
    'Missing' {
        Write-Host "[NOTICE] Safety hooks not installed in this project." -ForegroundColor Yellow
        $response = Read-Host "Install them? [Y/n]"
        if ([string]::IsNullOrWhiteSpace($response) -or $response -match '^[Yy]') {
            Install-ProjectHooks -SourceDir $PSScriptRoot -GitRoot $gitRoot
            Push-Location $gitRoot
            git add .claude/hooks/ .claude/settings.json
            git commit -m "chore: add axe safety hooks"
            Pop-Location
            Write-Host "Hooks installed." -ForegroundColor Green
        } else {
            Write-Host "WARNING: Running without safety hooks!" -ForegroundColor Red
            Start-Sleep 2
        }
    }
    'Outdated' {
        Install-ProjectHooks -SourceDir $PSScriptRoot -GitRoot $gitRoot
        Push-Location $gitRoot
        git add .claude/hooks/ .claude/settings.json
        git commit -m "chore: update axe safety hooks"
        Pop-Location
        Write-Host "Safety hooks updated to latest version." -ForegroundColor Cyan
    }
    'Ok' { }
}

# --- Phase 1b: Pre-flight (after hooks) ---
$errors = Test-PreFlightLate -PlanPath $Plan -LogDir $LogDir
if ($errors.Count -gt 0) {
    Write-Host "Pre-flight checks failed:" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}

# Warn if LogDir is not in .gitignore
$gitignorePath = Join-Path $gitRoot ".gitignore"
if (Test-Path $gitignorePath) {
    $gitignoreContent = Get-Content $gitignorePath -Raw
    $logDirBase = ($LogDir -split '[/\\]')[0]
    if ($gitignoreContent -notmatch [regex]::Escape($logDirBase)) {
        Write-Host "WARNING: '$logDirBase/' is not in .gitignore. Logs may be committed." -ForegroundColor Yellow
    }
}
```

Note: The `.gitignore` warning now uses the already-computed `$gitRoot` instead of re-running `git rev-parse`. The `if ($gitRoot)` guard is removed since Phase 1a already verified we're in a git repo.

- [ ] Step 6: Update `CLAUDE.md`

Replace the architecture table to reflect the new gating variable and hook filenames. The line `Three components, all gated by \`RALPH_ACTIVE\` environment variable:` was already renamed to `AXE_ACTIVE` in Task 4. No additional changes needed here beyond what Task 4 already covers.

If there are any remaining references to pre-flight as a single phase, update to mention early/late split. Otherwise skip this sub-step.

- [ ] Step 7: Update `README.md`

In the "What it does" section, update step 1 to mention the hook auto-installer:

```markdown
1. **Pre-flight** — verifies clean git tree, plan file exists, CLI available, installs/updates safety hooks if needed
```

In the "Safety Guards" section, add a new bullet:

```markdown
- **Hook auto-installer**: Checks target project for safety hooks, installs or updates them automatically
```

- [ ] Step 8: Run all tests

Run: `cd C:/Users/vadash/.claude/skills/auto-execute && pwsh -Command "Invoke-Pester -Path tests/ -Output Detailed"`
Expected: All tests PASS

- [ ] Step 9: Commit

```bash
cd C:/Users/vadash/.claude/skills/auto-execute
git add -A && git commit -m "feat: split pre-flight checks, add Phase 1.5 hook auto-installer"
```
