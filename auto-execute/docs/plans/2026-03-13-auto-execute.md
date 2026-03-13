# Auto-Execute Implementation Plan

**Goal:** Automate the repetitive `/executing-plans` + `/clear` cycle by running each plan task in a fresh Claude process with safety circuit breakers.

**Architecture:** Three-component system — a Claude Code skill (`auto-execute/auto-execute.md`) defines per-task headless behavior, a PowerShell wrapper (`auto-execute.ps1`) drives the outer loop across sessions with pre/post-task verification, and hook scripts (`.claude/hooks/`) provide real-time safety guards (context limits, loop detection). All hooks gated by `RALPH_ACTIVE` environment variable so they stay silent during manual usage.

**Tech Stack:** PowerShell 5.1+, Pester 5.x (testing framework), Claude Code CLI, Claude Code hooks system.

---

### File Structure

**Created:**

| # | File | Purpose |
|---|------|---------|
| 1 | `auto-execute/auto-execute.md` | Claude Code skill definition for headless task execution |
| 2 | `.claude/hooks/context-check.ps1` | PreToolUse hook: blocks tools when context exceeds threshold |
| 3 | `.claude/hooks/loop-detect.ps1` | PreToolUse hook: blocks tools when stuck in a loop |
| 4 | `.claude/settings.json` | Hook registration configuration |
| 5 | `auto-execute-helpers.ps1` | Pure helper functions (testable) |
| 6 | `auto-execute.ps1` | Main wrapper script (outer loop, process management) |
| 7 | `tests/context-check.Tests.ps1` | Pester tests for context-check hook |
| 8 | `tests/loop-detect.Tests.ps1` | Pester tests for loop-detect hook |
| 9 | `tests/auto-execute-helpers.Tests.ps1` | Pester tests for helper functions |

**Modified:**

| # | File | Change |
|---|------|--------|
| 10 | `.gitignore` | Add `logs/` entry |

---

### Task 1: Scaffolding and Test Infrastructure

**Files:**
- Create: `tests/scaffolding.Tests.ps1`

- [ ] Step 1: Verify Pester is installed, install if missing

Run:
```powershell
if (-not (Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version -ge '5.0.0' })) {
    Install-Module -Name Pester -Force -SkipPublisherCheck -Scope CurrentUser
}
Get-Module -ListAvailable -Name Pester | Select-Object -First 1 -ExpandProperty Version
```
Expected: A version number `5.x.x` or higher.

- [ ] Step 2: Create test directory and trivial test

Create `tests/scaffolding.Tests.ps1`:
```powershell
Describe "Test Infrastructure" {
    It "Pester is working" {
        $true | Should -BeTrue
    }
}
```

- [ ] Step 3: Run the test to verify infrastructure works

Run:
```powershell
Invoke-Pester -Path tests/scaffolding.Tests.ps1 -Output Detailed
```
Expected: PASS — `Tests completed in *`, `Passed: 1`

- [ ] Step 4: Commit

```bash
git add -A && git commit -m "chore: add test infrastructure with Pester scaffolding"
```

---

### Task 2: Skill Definition

**Files:**
- Create: `auto-execute/auto-execute.md`

- [ ] Step 1: Create the skill definition file

Create `auto-execute/auto-execute.md`:
```markdown
---
name: auto-execute
description: Executes a single task from a plan in headless automated mode. Use when running automated plan execution via the auto-execute.ps1 wrapper with no human present.
disable-model-invocation: true
argument-hint: <plan-path> do task <N>
---

# Auto-Execute: Headless Task Execution

Execute exactly one task from an implementation plan in automated/headless mode. This skill is invoked by the `auto-execute.ps1` wrapper script — not by humans directly.

<HARD-GATE>
Execute ONLY the single task specified. Do NOT continue to the next task. The PS1 wrapper decides what's next.
</HARD-GATE>

## Input

Parse `$ARGUMENTS` to determine:
1. **Plan path** — the plan file to read
2. **Task number** — which single task to execute (e.g., "do task 3")

Example: `/auto-execute docs/plans/2026-03-13-auth.md do task 3`

## Headless Operation Rules

You are running headless in an automated loop with no human present.

- DO NOT ask the user for clarification.
- DO NOT wait for user input.
- IF BLOCKED by a missing dependency, failing test you cannot solve in 3 attempts, or unclear instruction: STOP immediately with the failure output format below.

## Assumptions

Before starting, these MUST be true:
- All previous tasks in the plan are already completed
- All tests are currently passing
- The git working tree is clean

If any assumption is violated, output the failure format and stop. Do not prompt.

## Execution

1. Read the specified task from the plan
2. Follow the TDD red-green cycle exactly as written:
   - Write the failing test
   - Run it — verify it fails as expected
   - Write the minimal implementation
   - Run tests — verify they pass
3. Commit after the completed task

**If a test fails unexpectedly:** Apply systematic debugging. You have 3 attempts to fix it. After 3 failed attempts, stop with the failure output.

**If blocked:** Stop immediately with the failure output. Do not guess or work around.

## Structured Exit Output

Your FINAL line of output MUST be exactly one of:

**Success:**
```
[AUTO-EXECUTE] Task N COMPLETE. Commit: <hash>
```

**Failure:**
```
[AUTO-EXECUTE] Task N FAILED. Reason: <description>
```

## Completion

After outputting the structured exit line, STOP. Do not suggest next steps. Do not continue to the next task.
```

- [ ] Step 2: Commit

```bash
git add -A && git commit -m "feat: add auto-execute skill definition"
```

> **Deployment note:** This skill is stored in the repo alongside `writing-plans/` and `executing-plans/`. To activate it for Claude Code, copy or symlink to `~/.claude/skills/auto-execute/SKILL.md`.

---

### Task 3: Context-Check Hook

**Files:**
- Create: `tests/context-check.Tests.ps1`
- Create: `.claude/hooks/context-check.ps1`

- [ ] Step 1: Write the failing tests

Create `tests/context-check.Tests.ps1`:
```powershell
BeforeAll {
    . "$PSScriptRoot/../.claude/hooks/context-check.ps1"
}

Describe "Test-ContextLimit" {
    It "returns ExitCode 0 when RALPH_ACTIVE is not 'true'" {
        $result = Test-ContextLimit -RawInput '{}' -RalphActive '' -ContextLimitValue ''
        $result.ExitCode | Should -Be 0
    }

    It "returns ExitCode 0 when RALPH_ACTIVE is unset (null)" {
        $result = Test-ContextLimit -RawInput '{}' -RalphActive $null -ContextLimitValue ''
        $result.ExitCode | Should -Be 0
    }

    It "returns ExitCode 0 when transcript_path is missing from input" {
        $result = Test-ContextLimit -RawInput '{"tool": "Bash"}' -RalphActive 'true' -ContextLimitValue '70000'
        $result.ExitCode | Should -Be 0
    }

    It "returns ExitCode 0 when transcript file does not exist" {
        $json = @{ transcript_path = "C:/nonexistent/path/transcript.jsonl" } | ConvertTo-Json
        $result = Test-ContextLimit -RawInput $json -RalphActive 'true' -ContextLimitValue '70000'
        $result.ExitCode | Should -Be 0
    }

    It "returns ExitCode 0 when transcript file is small (under limit)" {
        $tempFile = New-TemporaryFile
        try {
            # 100 bytes -> ~25 tokens, well under 70000
            Set-Content -Path $tempFile.FullName -Value ("x" * 100) -NoNewline
            $json = @{ transcript_path = $tempFile.FullName } | ConvertTo-Json

            $result = Test-ContextLimit -RawInput $json -RalphActive 'true' -ContextLimitValue '70000'
            $result.ExitCode | Should -Be 0
        } finally {
            Remove-Item $tempFile.FullName -ErrorAction SilentlyContinue
        }
    }

    It "returns ExitCode 2 with message when transcript exceeds limit" {
        $tempFile = New-TemporaryFile
        try {
            # 400000 bytes -> ~100000 tokens, over 70000
            [System.IO.File]::WriteAllText($tempFile.FullName, ("x" * 400000))
            $json = @{ transcript_path = $tempFile.FullName } | ConvertTo-Json

            $result = Test-ContextLimit -RawInput $json -RalphActive 'true' -ContextLimitValue '70000'
            $result.ExitCode | Should -Be 2
            $result.Message | Should -Match 'CONTEXT LIMIT EXCEEDED'
            $result.Message | Should -Match 'DO NOT RETRY'
        } finally {
            Remove-Item $tempFile.FullName -ErrorAction SilentlyContinue
        }
    }

    It "uses custom limit from ContextLimitValue parameter" {
        $tempFile = New-TemporaryFile
        try {
            # 100 bytes -> ~25 tokens, over a limit of 10
            Set-Content -Path $tempFile.FullName -Value ("x" * 100) -NoNewline
            $json = @{ transcript_path = $tempFile.FullName } | ConvertTo-Json

            $result = Test-ContextLimit -RawInput $json -RalphActive 'true' -ContextLimitValue '10'
            $result.ExitCode | Should -Be 2
        } finally {
            Remove-Item $tempFile.FullName -ErrorAction SilentlyContinue
        }
    }

    It "defaults to 70000 when ContextLimitValue is empty" {
        $tempFile = New-TemporaryFile
        try {
            Set-Content -Path $tempFile.FullName -Value ("x" * 100) -NoNewline
            $json = @{ transcript_path = $tempFile.FullName } | ConvertTo-Json

            $result = Test-ContextLimit -RawInput $json -RalphActive 'true' -ContextLimitValue ''
            $result.ExitCode | Should -Be 0
        } finally {
            Remove-Item $tempFile.FullName -ErrorAction SilentlyContinue
        }
    }

    It "returns ExitCode 0 when input JSON is invalid" {
        $result = Test-ContextLimit -RawInput 'not valid json {{' -RalphActive 'true' -ContextLimitValue '70000'
        $result.ExitCode | Should -Be 0
    }
}
```

- [ ] Step 2: Run tests to verify they fail

Run:
```powershell
Invoke-Pester -Path tests/context-check.Tests.ps1 -Output Detailed
```
Expected: FAIL — `Test-ContextLimit` function not found (file does not exist yet).

- [ ] Step 3: Write the implementation

Create `.claude/hooks/context-check.ps1`:
```powershell
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
```

- [ ] Step 4: Run tests to verify they pass

Run:
```powershell
Invoke-Pester -Path tests/context-check.Tests.ps1 -Output Detailed
```
Expected: PASS — all 9 tests pass.

- [ ] Step 5: Commit

```bash
git add -A && git commit -m "feat: add context-check hook with tests"
```

---

### Task 4: Loop-Detect Hook

**Files:**
- Create: `tests/loop-detect.Tests.ps1`
- Create: `.claude/hooks/loop-detect.ps1`

- [ ] Step 1: Write the failing tests

Create `tests/loop-detect.Tests.ps1`:
```powershell
BeforeAll {
    . "$PSScriptRoot/../.claude/hooks/loop-detect.ps1"
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

    It "returns ExitCode 0 when RALPH_ACTIVE is not 'true'" {
        $json = @{ tool = "Bash"; tool_input = @{ command = "echo hi" }; session_id = "s1" } | ConvertTo-Json
        $result = Test-LoopDetection -RawInput $json -RalphActive '' -TempDir $script:tempDir
        $result.ExitCode | Should -Be 0
    }

    It "returns ExitCode 0 when RALPH_ACTIVE is null" {
        $json = @{ tool = "Bash"; tool_input = @{ command = "echo hi" }; session_id = "s1" } | ConvertTo-Json
        $result = Test-LoopDetection -RawInput $json -RalphActive $null -TempDir $script:tempDir
        $result.ExitCode | Should -Be 0
    }

    It "returns ExitCode 0 for a normal single call" {
        $json = @{ tool = "Bash"; tool_input = @{ command = "echo hi" }; session_id = "s1" } | ConvertTo-Json
        $result = Test-LoopDetection -RawInput $json -RalphActive 'true' -TempDir $script:tempDir
        $result.ExitCode | Should -Be 0
    }

    It "returns ExitCode 0 when session_id is missing" {
        $json = @{ tool = "Bash"; tool_input = @{ command = "echo hi" } } | ConvertTo-Json
        $result = Test-LoopDetection -RawInput $json -RalphActive 'true' -TempDir $script:tempDir
        $result.ExitCode | Should -Be 0
    }

    It "returns ExitCode 2 when total calls exceed MaxCalls" {
        $counterFile = Join-Path $script:tempDir "ralph-calls-s1.jsonl"
        # Pre-populate with 100 entries
        1..100 | ForEach-Object {
            $entry = @{ hash = "unique$_"; tool = "Bash"; ts = (Get-Date -Format o) } | ConvertTo-Json -Compress
            Add-Content -Path $counterFile -Value $entry
        }

        $json = @{ tool = "Bash"; tool_input = @{ command = "echo new" }; session_id = "s1" } | ConvertTo-Json
        $result = Test-LoopDetection -RawInput $json -RalphActive 'true' -TempDir $script:tempDir -MaxCalls 100
        $result.ExitCode | Should -Be 2
        $result.Message | Should -Match 'TOO MANY TOOL CALLS'
    }

    It "returns ExitCode 2 when same call repeats 3 times in last 10" {
        $json = @{ tool = "Bash"; tool_input = @{ command = "echo stuck" }; session_id = "s2" } | ConvertTo-Json

        # First 2 calls pass
        $result1 = Test-LoopDetection -RawInput $json -RalphActive 'true' -TempDir $script:tempDir
        $result1.ExitCode | Should -Be 0

        $result2 = Test-LoopDetection -RawInput $json -RalphActive 'true' -TempDir $script:tempDir
        $result2.ExitCode | Should -Be 0

        # 3rd identical call triggers detection
        $result3 = Test-LoopDetection -RawInput $json -RalphActive 'true' -TempDir $script:tempDir
        $result3.ExitCode | Should -Be 2
        $result3.Message | Should -Match 'REPEATED IDENTICAL TOOL CALLS'
    }

    It "does not trigger repetition when calls are varied" {
        $session = "s3"
        1..10 | ForEach-Object {
            $json = @{ tool = "Bash"; tool_input = @{ command = "echo $_" }; session_id = $session } | ConvertTo-Json
            $result = Test-LoopDetection -RawInput $json -RalphActive 'true' -TempDir $script:tempDir
            $result.ExitCode | Should -Be 0
        }
    }

    It "returns ExitCode 0 when input JSON is invalid" {
        $result = Test-LoopDetection -RawInput 'not json {{' -RalphActive 'true' -TempDir $script:tempDir
        $result.ExitCode | Should -Be 0
    }
}
```

- [ ] Step 2: Run tests to verify they fail

Run:
```powershell
Invoke-Pester -Path tests/loop-detect.Tests.ps1 -Output Detailed
```
Expected: FAIL — functions not found (file does not exist yet).

- [ ] Step 3: Write the implementation

Create `.claude/hooks/loop-detect.ps1`:
```powershell
# Loop Detector Hook
# Trigger: PreToolUse, matcher: *
# Blocks tool calls when Claude is stuck in a loop.
# Gated by RALPH_ACTIVE environment variable.

function Get-InputHash {
    param([string]$Text)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $sha.ComputeHash($bytes)
    return [BitConverter]::ToString($hashBytes).Replace("-", "").Substring(0, 16)
}

function Test-LoopDetection {
    param(
        [string]$RawInput,
        [string]$RalphActive,
        [string]$TempDir,
        [int]$MaxCalls = 100,
        [int]$RepeatThreshold = 3,
        [int]$WindowSize = 10
    )

    # Gate: only active during auto-execute
    if ($RalphActive -ne "true") {
        return @{ ExitCode = 0; Message = $null }
    }

    # Parse hook input
    try {
        $hookData = $RawInput | ConvertFrom-Json
    } catch {
        return @{ ExitCode = 0; Message = $null }
    }

    $tool = $hookData.tool
    $toolInputStr = if ($hookData.tool_input) {
        $hookData.tool_input | ConvertTo-Json -Depth 10 -Compress
    } else {
        ""
    }
    $sessionId = $hookData.session_id

    if (-not $sessionId) {
        return @{ ExitCode = 0; Message = $null }
    }

    # Counter file per session
    $counterFile = Join-Path $TempDir "ralph-calls-$sessionId.jsonl"

    # Normalize and hash the tool call
    $normalized = ($tool + "|" + ($toolInputStr -replace '\s+', ' ')).ToLower()
    $hash = Get-InputHash -Text $normalized

    # Append entry
    $entry = @{ hash = $hash; tool = $tool; ts = (Get-Date -Format o) } | ConvertTo-Json -Compress
    Add-Content -Path $counterFile -Value $entry

    # Count total calls
    $lines = @(Get-Content -Path $counterFile)
    $totalCalls = $lines.Count

    if ($totalCalls -gt $MaxCalls) {
        $msg = "TOO MANY TOOL CALLS (>$MaxCalls). DO NOT RETRY. Output '[AUTO-EXECUTE] Task N FAILED. Reason: stuck/loop detected' and stop immediately."
        return @{ ExitCode = 2; Message = $msg }
    }

    # Check repetition in last N calls
    $recent = $lines | Select-Object -Last $WindowSize | ForEach-Object {
        try { ($_ | ConvertFrom-Json).hash } catch { "" }
    }
    $groups = $recent | Group-Object
    foreach ($g in $groups) {
        if ($g.Name -and $g.Count -ge $RepeatThreshold) {
            $msg = "REPEATED IDENTICAL TOOL CALLS DETECTED. DO NOT RETRY. Output '[AUTO-EXECUTE] Task N FAILED. Reason: loop detected' and stop immediately."
            return @{ ExitCode = 2; Message = $msg }
        }
    }

    return @{ ExitCode = 0; Message = $null }
}

# Main execution — only when invoked directly (not dot-sourced)
if ($MyInvocation.InvocationName -ne '.') {
    $rawInput = [Console]::In.ReadToEnd()
    $tempDir = if ($env:TEMP) { $env:TEMP } else { [System.IO.Path]::GetTempPath() }
    $result = Test-LoopDetection -RawInput $rawInput -RalphActive $env:RALPH_ACTIVE -TempDir $tempDir
    if ($result.Message) {
        [Console]::Error.WriteLine($result.Message)
    }
    exit $result.ExitCode
}
```

- [ ] Step 4: Run tests to verify they pass

Run:
```powershell
Invoke-Pester -Path tests/loop-detect.Tests.ps1 -Output Detailed
```
Expected: PASS — all 10 tests pass.

- [ ] Step 5: Commit

```bash
git add -A && git commit -m "feat: add loop-detect hook with tests"
```

---

### Task 5: Hook Registration

**Files:**
- Create: `.claude/settings.json`

- [ ] Step 1: Create the hook registration config

Create `.claude/settings.json`:
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "powershell.exe -ExecutionPolicy Bypass -File .claude/hooks/context-check.ps1"
          },
          {
            "type": "command",
            "command": "powershell.exe -ExecutionPolicy Bypass -File .claude/hooks/loop-detect.ps1"
          }
        ]
      }
    ]
  }
}
```

- [ ] Step 2: Commit

```bash
git add -A && git commit -m "feat: add hook registration in .claude/settings.json"
```

---

### Task 6: Plan Parsing Helpers

**Files:**
- Create: `auto-execute-helpers.ps1`
- Create: `tests/auto-execute-helpers.Tests.ps1`

- [ ] Step 1: Write the failing tests

Create `tests/auto-execute-helpers.Tests.ps1`:
```powershell
BeforeAll {
    . "$PSScriptRoot/../auto-execute-helpers.ps1"
}

Describe "Find-FirstUncheckedTask" {
    It "returns the first task number that has unchecked steps" {
        $plan = @"
### Task 1: Setup

- [x] Step 1: Done
- [x] Step 2: Done

### Task 2: Implementation

- [ ] Step 1: Not done
- [ ] Step 2: Not done
"@
        Find-FirstUncheckedTask -PlanContent $plan | Should -Be 2
    }

    It "returns 0 when all tasks are complete" {
        $plan = @"
### Task 1: Setup

- [x] Step 1: Done

### Task 2: Implementation

- [x] Step 1: Done
"@
        Find-FirstUncheckedTask -PlanContent $plan | Should -Be 0
    }

    It "returns 1 when the very first task has unchecked steps" {
        $plan = @"
### Task 1: Setup

- [ ] Step 1: Not done
"@
        Find-FirstUncheckedTask -PlanContent $plan | Should -Be 1
    }

    It "handles mixed checked and unchecked steps within a task" {
        $plan = @"
### Task 1: Setup

- [x] Step 1: Done
- [ ] Step 2: Not done
"@
        Find-FirstUncheckedTask -PlanContent $plan | Should -Be 1
    }

    It "handles plans with no task headers" {
        $plan = "Just some text with no tasks"
        Find-FirstUncheckedTask -PlanContent $plan | Should -Be 0
    }
}

Describe "Get-TotalTaskCount" {
    It "counts all task headers and returns the highest number" {
        $plan = @"
### Task 1: Setup

### Task 2: Implementation

### Task 3: Testing
"@
        Get-TotalTaskCount -PlanContent $plan | Should -Be 3
    }

    It "returns 0 for a plan with no task headers" {
        Get-TotalTaskCount -PlanContent "No tasks here" | Should -Be 0
    }

    It "returns the highest task number even if non-sequential" {
        $plan = @"
### Task 1: First

### Task 5: Last
"@
        Get-TotalTaskCount -PlanContent $plan | Should -Be 5
    }

    It "handles single task" {
        $plan = "### Task 1: Only Task"
        Get-TotalTaskCount -PlanContent $plan | Should -Be 1
    }
}
```

- [ ] Step 2: Run tests to verify they fail

Run:
```powershell
Invoke-Pester -Path tests/auto-execute-helpers.Tests.ps1 -Output Detailed
```
Expected: FAIL — functions not found (file does not exist yet).

- [ ] Step 3: Write the implementation

Create `auto-execute-helpers.ps1`:
```powershell
# Auto-Execute Helper Functions
# Dot-sourced by auto-execute.ps1 and tests.
# Contains only pure/testable functions.

function Find-FirstUncheckedTask {
    param(
        [Parameter(Mandatory)]
        [string]$PlanContent
    )

    $lines = $PlanContent -split "`n"
    $currentTask = 0

    foreach ($line in $lines) {
        if ($line -match '^###\s+Task\s+(\d+)') {
            $currentTask = [int]$Matches[1]
        }
        if ($currentTask -gt 0 -and $line -match '^\s*-\s*\[\s\]') {
            return $currentTask
        }
    }

    return 0
}

function Get-TotalTaskCount {
    param(
        [Parameter(Mandatory)]
        [string]$PlanContent
    )

    $taskMatches = [regex]::Matches($PlanContent, '(?m)^###\s+Task\s+(\d+)')
    if ($taskMatches.Count -eq 0) { return 0 }

    $max = 0
    foreach ($m in $taskMatches) {
        $num = [int]$m.Groups[1].Value
        if ($num -gt $max) { $max = $num }
    }
    return $max
}
```

- [ ] Step 4: Run tests to verify they pass

Run:
```powershell
Invoke-Pester -Path tests/auto-execute-helpers.Tests.ps1 -Output Detailed
```
Expected: PASS — all 9 tests pass.

- [ ] Step 5: Commit

```bash
git add -A && git commit -m "feat: add plan parsing helpers with tests"
```

---

### Task 7: Verification and Pre-Flight Helpers

**Files:**
- Modify: `auto-execute-helpers.ps1`
- Modify: `tests/auto-execute-helpers.Tests.ps1`

- [ ] Step 1: Write the failing tests

Append to `tests/auto-execute-helpers.Tests.ps1`:
```powershell
Describe "Test-TaskSuccess" {
    It "returns AllPassed true when all 3 signals pass" {
        $result = Test-TaskSuccess -ExitCode 0 -BeforeHash "abc1234" -AfterHash "def5678" -GitStatus ""
        $result.AllPassed | Should -BeTrue
        $result.ExitOk | Should -BeTrue
        $result.NewCommit | Should -BeTrue
        $result.CleanTree | Should -BeTrue
    }

    It "fails when exit code is non-zero" {
        $result = Test-TaskSuccess -ExitCode 1 -BeforeHash "abc1234" -AfterHash "def5678" -GitStatus ""
        $result.AllPassed | Should -BeFalse
        $result.ExitOk | Should -BeFalse
    }

    It "fails when no new commit was made" {
        $result = Test-TaskSuccess -ExitCode 0 -BeforeHash "abc1234" -AfterHash "abc1234" -GitStatus ""
        $result.AllPassed | Should -BeFalse
        $result.NewCommit | Should -BeFalse
    }

    It "fails when working tree is dirty" {
        $result = Test-TaskSuccess -ExitCode 0 -BeforeHash "abc1234" -AfterHash "def5678" -GitStatus "M file.txt"
        $result.AllPassed | Should -BeFalse
        $result.CleanTree | Should -BeFalse
    }

    It "fails when all 3 signals fail" {
        $result = Test-TaskSuccess -ExitCode 1 -BeforeHash "abc1234" -AfterHash "abc1234" -GitStatus "M file.txt"
        $result.AllPassed | Should -BeFalse
        $result.ExitOk | Should -BeFalse
        $result.NewCommit | Should -BeFalse
        $result.CleanTree | Should -BeFalse
    }

    It "treats whitespace-only GitStatus as clean" {
        $result = Test-TaskSuccess -ExitCode 0 -BeforeHash "abc" -AfterHash "def" -GitStatus "   "
        $result.CleanTree | Should -BeTrue
    }
}

Describe "Test-PreFlightChecks" {
    BeforeEach {
        $script:tempPlan = New-TemporaryFile
        Set-Content $script:tempPlan.FullName "### Task 1: Test`n- [ ] Step 1: Do it"
        $script:tempLogDir = Join-Path ([System.IO.Path]::GetTempPath()) "pester-logs-$(Get-Random)"
    }

    AfterEach {
        Remove-Item $script:tempPlan.FullName -ErrorAction SilentlyContinue
        if (Test-Path $script:tempLogDir) {
            Remove-Item $script:tempLogDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "returns error when CLI binary does not exist" {
        $errors = Test-PreFlightChecks -ClaudeBin "definitely-not-a-real-command-xyz-123" `
            -PlanPath $script:tempPlan.FullName -LogDir $script:tempLogDir
        ($errors | Where-Object { $_ -match "not found in PATH" }) | Should -Not -BeNullOrEmpty
    }

    It "returns error when plan file does not exist" {
        $errors = Test-PreFlightChecks -ClaudeBin "cmd" `
            -PlanPath "/nonexistent/plan.md" -LogDir $script:tempLogDir
        $errors | Should -Contain "Plan file '/nonexistent/plan.md' not found."
    }

    It "returns error when plan has no unchecked tasks" {
        Set-Content $script:tempPlan.FullName "### Task 1: Done`n- [x] Step 1: Done"
        $errors = Test-PreFlightChecks -ClaudeBin "cmd" `
            -PlanPath $script:tempPlan.FullName -LogDir $script:tempLogDir
        ($errors | Where-Object { $_ -match "no unchecked tasks" }) | Should -Not -BeNullOrEmpty
    }

    It "creates log directory if it does not exist" {
        Test-PreFlightChecks -ClaudeBin "cmd" `
            -PlanPath $script:tempPlan.FullName -LogDir $script:tempLogDir | Out-Null
        Test-Path $script:tempLogDir | Should -BeTrue
    }
}
```

- [ ] Step 2: Run tests to verify the new tests fail

Run:
```powershell
Invoke-Pester -Path tests/auto-execute-helpers.Tests.ps1 -Output Detailed
```
Expected: FAIL — `Test-TaskSuccess` and `Test-PreFlightChecks` functions not found.

- [ ] Step 3: Write the implementation

Append to `auto-execute-helpers.ps1`:
```powershell
function Test-TaskSuccess {
    param(
        [int]$ExitCode,
        [string]$BeforeHash,
        [string]$AfterHash,
        [string]$GitStatus
    )

    $signals = @{
        ExitOk    = ($ExitCode -eq 0)
        NewCommit = ($AfterHash -ne $BeforeHash)
        CleanTree = ([string]::IsNullOrWhiteSpace($GitStatus))
    }

    $signals.AllPassed = $signals.ExitOk -and $signals.NewCommit -and $signals.CleanTree

    return $signals
}

function Test-PreFlightChecks {
    param(
        [string]$ClaudeBin,
        [string]$PlanPath,
        [string]$LogDir
    )

    $errors = @()

    # Check CLI is callable
    if (-not (Get-Command $ClaudeBin -ErrorAction SilentlyContinue)) {
        $errors += "CLI binary '$ClaudeBin' not found in PATH."
    }

    # Check plan file exists and has unchecked tasks
    if (-not (Test-Path $PlanPath)) {
        $errors += "Plan file '$PlanPath' not found."
    } else {
        $content = Get-Content $PlanPath -Raw
        if ($content -notmatch '\-\s*\[\s\]') {
            $errors += "Plan file has no unchecked tasks (no '- [ ]' found)."
        }
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

function Save-DirtyState {
    param(
        [int]$TaskNumber
    )

    $stashMsg = "auto-execute: partial task $TaskNumber"
    git stash --include-untracked -m $stashMsg 2>&1
    return $LASTEXITCODE -eq 0
}
```

- [ ] Step 4: Run tests to verify they pass

Run:
```powershell
Invoke-Pester -Path tests/auto-execute-helpers.Tests.ps1 -Output Detailed
```
Expected: PASS — all tests pass (previous + new).

- [ ] Step 5: Commit

```bash
git add -A && git commit -m "feat: add verification and pre-flight helper functions with tests"
```

---

### Task 8: Logging and Reporting Helpers

**Files:**
- Modify: `auto-execute-helpers.ps1`
- Modify: `tests/auto-execute-helpers.Tests.ps1`

- [ ] Step 1: Write the failing tests

Append to `tests/auto-execute-helpers.Tests.ps1`:
```powershell
Describe "Format-TaskLogEntry" {
    It "formats a passing task with commit hash and duration" {
        $duration = [TimeSpan]::FromSeconds(192)
        $result = Format-TaskLogEntry -TaskNumber 1 -Passed $true -CommitHash "abc1234def5678" -Duration $duration
        $result | Should -Match 'Task 1'
        $result | Should -Match 'PASS'
        $result | Should -Match 'abc1234'
        $result | Should -Match '3m 12s'
    }

    It "formats a failing task with reason" {
        $duration = [TimeSpan]::FromSeconds(45)
        $result = Format-TaskLogEntry -TaskNumber 2 -Passed $false -Duration $duration -FailReason "no new commit"
        $result | Should -Match 'Task 2'
        $result | Should -Match 'FAIL'
        $result | Should -Match 'no new commit'
    }

    It "truncates commit hash to 7 characters" {
        $duration = [TimeSpan]::FromSeconds(10)
        $result = Format-TaskLogEntry -TaskNumber 3 -Passed $true -CommitHash "abcdef1234567890" -Duration $duration
        $result | Should -Match 'abcdef1'
        $result | Should -Not -Match 'abcdef12345'
    }

    It "handles zero duration" {
        $duration = [TimeSpan]::Zero
        $result = Format-TaskLogEntry -TaskNumber 1 -Passed $true -CommitHash "abc1234" -Duration $duration
        $result | Should -Match '0m 00s'
    }
}

Describe "Format-FinalReport" {
    It "includes all summary fields" {
        $duration = [TimeSpan]::FromSeconds(1425)
        $result = Format-FinalReport -PlanPath "docs/plans/test.md" `
            -CompletedTasks 5 -TotalTasks 8 `
            -TotalDuration $duration `
            -StopReason "All tasks complete" `
            -LogFile "logs/auto-execute/run.log"
        $result | Should -Match 'Auto-Execute Summary'
        $result | Should -Match 'docs/plans/test.md'
        $result | Should -Match '5/8 completed'
        $result | Should -Match '23m 45s'
        $result | Should -Match 'All tasks complete'
        $result | Should -Match 'logs/auto-execute/run.log'
    }

    It "handles zero completed tasks" {
        $duration = [TimeSpan]::FromSeconds(30)
        $result = Format-FinalReport -PlanPath "plan.md" `
            -CompletedTasks 0 -TotalTasks 5 `
            -TotalDuration $duration `
            -StopReason "Max failures reached" `
            -LogFile "run.log"
        $result | Should -Match '0/5 completed'
        $result | Should -Match 'Max failures reached'
    }
}
```

- [ ] Step 2: Run tests to verify the new tests fail

Run:
```powershell
Invoke-Pester -Path tests/auto-execute-helpers.Tests.ps1 -Output Detailed
```
Expected: FAIL — `Format-TaskLogEntry` and `Format-FinalReport` functions not found.

- [ ] Step 3: Write the implementation

Append to `auto-execute-helpers.ps1`:
```powershell
function Format-TaskLogEntry {
    param(
        [int]$TaskNumber,
        [bool]$Passed,
        [string]$CommitHash,
        [TimeSpan]$Duration,
        [string]$FailReason
    )

    $timestamp = Get-Date -Format "HH:mm:ss"
    $durationStr = "{0}m {1:D2}s" -f [math]::Floor($Duration.TotalMinutes), $Duration.Seconds

    if ($Passed) {
        $shortHash = if ($CommitHash.Length -ge 7) { $CommitHash.Substring(0, 7) } else { $CommitHash }
        return "[$timestamp] Task ${TaskNumber}: PASS (commit $shortHash, $durationStr)"
    } else {
        return "[$timestamp] Task ${TaskNumber}: FAIL ($FailReason) — STOPPED"
    }
}

function Format-FinalReport {
    param(
        [string]$PlanPath,
        [int]$CompletedTasks,
        [int]$TotalTasks,
        [TimeSpan]$TotalDuration,
        [string]$StopReason,
        [string]$LogFile
    )

    $durationStr = "{0}m {1:D2}s" -f [math]::Floor($TotalDuration.TotalMinutes), $TotalDuration.Seconds

    return @"
=== Auto-Execute Summary ===
Plan:       $PlanPath
Tasks:      $CompletedTasks/$TotalTasks completed
Duration:   $durationStr
Stop reason: $StopReason
Logs:       $LogFile
"@
}
```

- [ ] Step 4: Run tests to verify they pass

Run:
```powershell
Invoke-Pester -Path tests/auto-execute-helpers.Tests.ps1 -Output Detailed
```
Expected: PASS — all tests pass.

- [ ] Step 5: Commit

```bash
git add -A && git commit -m "feat: add logging and reporting helper functions with tests"
```

---

### Task 9: Main Wrapper Script

**Files:**
- Create: `auto-execute.ps1`

- [ ] Step 1: Create the complete main script

Create `auto-execute.ps1`:
```powershell
# auto-execute.ps1 — Automated plan execution with safety circuit breakers
# Drives the outer loop: pre-flight checks, task execution, post-task verification.
# Each task runs in a fresh Claude process via the auto-execute skill.

param(
    [Parameter(Mandatory)] [string] $Plan,
    [string] $ClaudeBin    = "claude",
    [int]    $MaxTurns     = 40,
    [int]    $TaskTimeout  = 900,
    [int]    $ContextLimit = 70000,
    [int]    $MaxFailures  = 2,
    [int]    $StartTask    = 0,
    [string] $LogDir       = "logs/auto-execute"
)

# Dot-source helper functions
. "$PSScriptRoot/auto-execute-helpers.ps1"

# --- Phase 1: Pre-flight Checks ---
$errors = Test-PreFlightChecks -ClaudeBin $ClaudeBin -PlanPath $Plan -LogDir $LogDir
if ($errors.Count -gt 0) {
    Write-Host "Pre-flight checks failed:" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}

# Warn if LogDir is not in .gitignore
$gitRoot = git rev-parse --show-toplevel 2>$null
if ($gitRoot) {
    $gitignorePath = Join-Path $gitRoot ".gitignore"
    if (Test-Path $gitignorePath) {
        $gitignoreContent = Get-Content $gitignorePath -Raw
        $logDirBase = ($LogDir -split '[/\\]')[0]
        if ($gitignoreContent -notmatch [regex]::Escape($logDirBase)) {
            Write-Host "WARNING: '$logDirBase/' is not in .gitignore. Logs may be committed." -ForegroundColor Yellow
        }
    }
}

# Set environment for hooks
$env:RALPH_ACTIVE = "true"
$env:RALPH_CONTEXT_LIMIT = $ContextLimit

# --- Phase 2: Task Tracking ---
$planContent = Get-Content $Plan -Raw
$totalTasks = Get-TotalTaskCount -PlanContent $planContent

if ($StartTask -gt 0) {
    $currentTask = $StartTask
} else {
    $currentTask = Find-FirstUncheckedTask -PlanContent $planContent
    if ($currentTask -eq 0) {
        Write-Host "All tasks in the plan are already complete!" -ForegroundColor Green
        exit 0
    }
}

Write-Host "Starting auto-execute: tasks $currentTask to $totalTasks" -ForegroundColor Cyan
Write-Host "Plan: $Plan" -ForegroundColor Cyan
Write-Host "CLI: $ClaudeBin | MaxTurns: $MaxTurns | Timeout: ${TaskTimeout}s | MaxFailures: $MaxFailures" -ForegroundColor Cyan

# --- Phase 3: Main Loop ---
$running = $true
$consecutiveFailures = 0
$completedCount = 0
$overallStart = [System.Diagnostics.Stopwatch]::StartNew()
$runTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$summaryLogPath = Join-Path $LogDir "run-$runTimestamp.log"
$summaryEntries = @()
$stopReason = "Unknown"

try {
    while ($running -and $currentTask -le $totalTasks) {
        # Record baseline
        $beforeHash = (git rev-parse HEAD 2>&1).ToString().Trim()
        $taskStart = [System.Diagnostics.Stopwatch]::StartNew()
        $taskTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $taskLogPath = Join-Path $LogDir "task-$currentTask-$taskTimestamp.log"

        Write-Host "`n--- Task $currentTask/$totalTasks ---" -ForegroundColor Cyan

        # Build prompt and execute
        # Resolve full path to handle .cmd extensions (npm packages like claude)
        $claudeCmd = (Get-Command $ClaudeBin).Source
        $promptText = "/auto-execute @$Plan do task $currentTask"
        $argString = "-p `"$promptText`" --dangerously-skip-permissions --max-turns $MaxTurns --no-color"

        $process = Start-Process -FilePath $claudeCmd `
            -ArgumentList $argString `
            -PassThru -NoNewWindow `
            -RedirectStandardOutput $taskLogPath `
            -RedirectStandardError "$taskLogPath.err"

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

        if ($null -eq $taskExitCode) { $taskExitCode = $process.ExitCode }

        $taskStart.Stop()
        $taskDuration = $taskStart.Elapsed

        # Post-task verification (multi-signal)
        $afterHash = (git rev-parse HEAD 2>&1).ToString().Trim()
        $gitStatus = (git status --porcelain 2>&1) -join ""

        $signals = Test-TaskSuccess -ExitCode $taskExitCode `
            -BeforeHash $beforeHash -AfterHash $afterHash -GitStatus $gitStatus

        if ($signals.AllPassed) {
            $consecutiveFailures = 0
            $completedCount++
            $entry = Format-TaskLogEntry -TaskNumber $currentTask -Passed $true `
                -CommitHash $afterHash -Duration $taskDuration
            Write-Host $entry -ForegroundColor Green
            $summaryEntries += $entry
            $currentTask++
        } else {
            $consecutiveFailures++
            $failReasons = @()
            if (-not $signals.ExitOk)    { $failReasons += "exit code $taskExitCode" }
            if (-not $signals.NewCommit) { $failReasons += "no new commit" }
            if (-not $signals.CleanTree) { $failReasons += "dirty tree" }
            $failReason = $failReasons -join ", "

            $entry = Format-TaskLogEntry -TaskNumber $currentTask -Passed $false `
                -Duration $taskDuration -FailReason $failReason
            Write-Host $entry -ForegroundColor Red
            $summaryEntries += $entry

            # Dirty tree handling
            if (-not $signals.CleanTree) {
                $stashed = Save-DirtyState -TaskNumber $currentTask
                if ($stashed) {
                    Write-Host "Task $currentTask left uncommitted changes. Stashed." -ForegroundColor Yellow
                }
                $running = $false
                $stopReason = "Dirty tree (changes stashed)"
                continue
            }

            if ($consecutiveFailures -ge $MaxFailures) {
                $running = $false
                $stopReason = "Max failures reached ($MaxFailures consecutive)"
            }
        }

        # Clean up temp counter files between tasks (fresh session = fresh counter)
        Get-ChildItem -Path $env:TEMP -Filter "ralph-calls-*.jsonl" -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }

    if ($currentTask -gt $totalTasks -and $running) {
        $stopReason = "All tasks complete"
    }
} catch {
    $stopReason = "Error: $_"
} finally {
    # Clean up environment
    $env:RALPH_ACTIVE = $null
    $env:RALPH_CONTEXT_LIMIT = $null
    $overallStart.Stop()

    # Warn about possible background Claude process on Ctrl+C
    if ($stopReason -eq "Unknown" -or $stopReason -match "^Error:") {
        Write-Host "NOTE: A Claude process may still be running in the background." -ForegroundColor Yellow
        Write-Host "Check with: Get-Process -Name node -ErrorAction SilentlyContinue" -ForegroundColor Yellow
    }

    # Clean up temp counter files
    Get-ChildItem -Path $env:TEMP -Filter "ralph-calls-*.jsonl" -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue

    # Write summary log
    if ($summaryEntries.Count -gt 0) {
        $summaryEntries | Out-File -FilePath $summaryLogPath -Encoding UTF8
    }

    # Final report
    $report = Format-FinalReport -PlanPath $Plan -CompletedTasks $completedCount `
        -TotalTasks $totalTasks -TotalDuration $overallStart.Elapsed `
        -StopReason $stopReason -LogFile $summaryLogPath
    Write-Host "`n$report" -ForegroundColor Cyan
}
```

- [ ] Step 2: Verify the script loads without syntax errors

Run:
```powershell
powershell.exe -ExecutionPolicy Bypass -Command "& { . './auto-execute.ps1' }" 2>&1 | Select-Object -First 5
```
Expected: Error about missing mandatory parameter `$Plan` (not a syntax error). This confirms the script parses correctly.

- [ ] Step 3: Commit

```bash
git add -A && git commit -m "feat: add auto-execute.ps1 main wrapper script"
```

---

### Task 10: Gitignore and Final Integration

**Files:**
- Modify: `.gitignore`

- [ ] Step 1: Add logs/ to .gitignore

Append to `.gitignore`:
```
logs/
```

- [ ] Step 2: Run all tests to verify everything passes

Run:
```powershell
Invoke-Pester -Path tests/ -Output Detailed
```
Expected: PASS — all tests across all 3 test files pass.

- [ ] Step 3: Commit

```bash
git add -A && git commit -m "chore: add logs/ to .gitignore, verify all tests pass"
```
