# Robustness Improvements Implementation Plan

**Goal:** Fix bugs, remove the false-positive-prone loop detector, add task splitting with per-task temp files, and replace wall-clock timeout with activity-based timeout.
**Architecture:** Changes span the helpers file (new parser + temp file functions), the wrapper script (new main loop, gap detection, idle timeout), the SKILL.md prompt, and the hook system (removal). All new helper functions get TDD coverage via Pester.
**Tech Stack:** PowerShell 5.1+, Pester 5.x, Git

---

### Task 1: Update SKILL.md with empty commit rule and TodoWrite ban

**Files:**
- Modify: `SKILL.md`

- [ ] Step 1: In `SKILL.md`, add a TodoWrite ban to the Headless Operation Rules section. Add the line `- Do NOT use Todo/task-tracking tools (TodoWrite, TaskCreate, etc.). A single task is small enough to track in your reasoning. Keep your context footprint minimal.` after the existing `- IF BLOCKED...` rule.

- [ ] Step 2: In `SKILL.md`, update the Execution section item 3 from:

```
3. Commit after the completed task
```

to:

```
3. Commit after the completed task. If no code changes were needed, use: `git commit --allow-empty -m "task N: no changes needed"`
```

- [ ] Step 3: Commit

```bash
git add -A && git commit -m "feat: update SKILL.md with empty commit rule and TodoWrite ban"
```

### Task 2: Delete loop detector hook and clean settings

**Files:**
- Delete: `.claude/hooks/axe-loop-detect.ps1`
- Delete: `tests/loop-detect.Tests.ps1`
- Modify: `.claude/settings.json`

- [ ] Step 1: Delete the loop detector hook file `.claude/hooks/axe-loop-detect.ps1` and its test file `tests/loop-detect.Tests.ps1`.

- [ ] Step 2: Replace the contents of `.claude/settings.json` with an empty JSON object:

```json
{}
```

- [ ] Step 3: Run remaining tests to verify nothing breaks

Run: `Invoke-Pester -Path "C:\Users\vadash\.claude\skills\auto-execute\tests\auto-execute-helpers.Tests.ps1" -Output Detailed 2>&1`
Expected: All tests pass. No references to deleted files.

- [ ] Step 4: Commit

```bash
git add -A && git commit -m "feat: remove loop detector hook and clean settings"
```

### Task 3: Remove hook helper functions and their tests

**Files:**
- Modify: `auto-execute-helpers.ps1`
- Modify: `tests/auto-execute-helpers.Tests.ps1`

- [ ] Step 1: Remove these three functions from `auto-execute-helpers.ps1`:
  - `Compare-NormalizedFileContent` (the entire function)
  - `Get-ProjectHooksStatus` (the entire function)
  - `Install-ProjectHooks` (the entire function)

- [ ] Step 2: Remove these three Describe blocks from `tests/auto-execute-helpers.Tests.ps1`:
  - `Describe "Compare-NormalizedFileContent" { ... }`
  - `Describe "Get-ProjectHooksStatus" { ... }`
  - `Describe "Install-ProjectHooks" { ... }`

- [ ] Step 3: Run tests to verify

Run: `Invoke-Pester -Path "C:\Users\vadash\.claude\skills\auto-execute\tests\auto-execute-helpers.Tests.ps1" -Output Detailed 2>&1`
Expected: All remaining tests pass. No errors about missing functions.

- [ ] Step 4: Commit

```bash
git add -A && git commit -m "feat: remove hook helper functions and tests"
```

### Task 4: Remove Phase 1.5 and environment variables from wrapper

**Files:**
- Modify: `auto-execute.ps1`

- [ ] Step 1: Remove the entire Phase 1.5 block from `auto-execute.ps1`. This is the section starting with `# --- Phase 1.5: Hook Auto-Installer ---` and ending just before `# --- Phase 1b: Pre-flight (after hooks) ---`. It includes the `$hookStatus = Get-ProjectHooksStatus` call, the `switch ($hookStatus)` block, and the `$gitRoot` variable assignment.

Note: `$gitRoot` is also used later (for gitignore enforcement, transcript path, context tracking). Move the `$gitRoot` assignment line to just before its next usage — the gitignore enforcement block that starts with `# Ensure LogDir is in .gitignore`.

- [ ] Step 2: Remove the two `$env:AXE_ACTIVE` lines:
  - `$env:AXE_ACTIVE = "true"` (after the gitignore block)
  - `$env:AXE_ACTIVE = $null` (in the `finally` block)

- [ ] Step 3: Remove the two `$env:AXE_CONTEXT_LIMIT` lines:
  - `$env:AXE_CONTEXT_LIMIT = $ContextLimit` (right after the `AXE_ACTIVE` set)
  - `$env:AXE_CONTEXT_LIMIT = $null` (in the `finally` block)

- [ ] Step 4: Remove the `axe-calls-*.jsonl` temp file cleanup in both locations:
  - The block at the end of the main `while` loop: `Get-ChildItem -Path $env:TEMP -Filter "axe-calls-*.jsonl" ...`
  - The block in the `finally` section: `Get-ChildItem -Path $env:TEMP -Filter "axe-calls-*.jsonl" ...`

- [ ] Step 5: Verify the script parses without syntax errors

Run: `pwsh -Command "try { . 'C:\Users\vadash\.claude\skills\auto-execute\auto-execute.ps1' } catch { Write-Host 'Parse OK (param block requires args)' }" 2>&1`
Expected: Errors about missing mandatory arguments (not syntax errors). This confirms the file parses correctly.

- [ ] Step 6: Commit

```bash
git add -A && git commit -m "feat: remove Phase 1.5, AXE env vars, and axe temp cleanup"
```

### Task 5: Add Get-PlanTasks function with TDD

**Files:**
- Modify: `auto-execute-helpers.ps1`
- Modify: `tests/auto-execute-helpers.Tests.ps1`

- [ ] Step 1: Write the failing tests. Replace the entire `Describe "Get-TotalTaskCount"` block in `tests/auto-execute-helpers.Tests.ps1` with:

```powershell
Describe "Get-PlanTasks" {
    It "extracts preamble and task blocks" {
        $plan = @"
# My Plan

**Goal:** Do something

---

### Task 1: Setup

Step 1: Create files

### Task 2: Implementation

Step 1: Write code
"@
        $result = Get-PlanTasks -PlanContent $plan
        $result.Preamble | Should -Match "My Plan"
        $result.Preamble | Should -Match "Goal"
        $result.Tasks.Count | Should -Be 2
        $result.Tasks[0].Number | Should -Be 1
        $result.Tasks[0].Content | Should -Match "Setup"
        $result.Tasks[0].Content | Should -Match "Create files"
        $result.Tasks[1].Number | Should -Be 2
        $result.Tasks[1].Content | Should -Match "Implementation"
        $result.Tasks[1].Content | Should -Match "Write code"
    }

    It "returns empty tasks for a plan with no task headers" {
        $result = Get-PlanTasks -PlanContent "No tasks here"
        $result.Preamble | Should -Be "No tasks here"
        $result.Tasks.Count | Should -Be 0
    }

    It "handles plan with no preamble" {
        $plan = "### Task 1: Only Task`n`nDo something"
        $result = Get-PlanTasks -PlanContent $plan
        $result.Preamble | Should -BeNullOrEmpty
        $result.Tasks.Count | Should -Be 1
        $result.Tasks[0].Number | Should -Be 1
        $result.Tasks[0].Content | Should -Match "Do something"
    }

    It "matches both ## and ### headers" {
        $plan = @"
Preamble

## Task 1: Setup

Content 1

### Task 2: Build

Content 2
"@
        $result = Get-PlanTasks -PlanContent $plan
        $result.Tasks.Count | Should -Be 2
        $result.Tasks[0].Number | Should -Be 1
        $result.Tasks[1].Number | Should -Be 2
    }

    It "handles non-sequential task numbers" {
        $plan = @"
### Task 1: First

Content 1

### Task 5: Last

Content 5
"@
        $result = Get-PlanTasks -PlanContent $plan
        $result.Tasks.Count | Should -Be 2
        $result.Tasks[0].Number | Should -Be 1
        $result.Tasks[1].Number | Should -Be 5
    }

    It "handles single task" {
        $plan = "### Task 1: Only`n`nDo it"
        $result = Get-PlanTasks -PlanContent $plan
        $result.Tasks.Count | Should -Be 1
        $result.Tasks[0].Number | Should -Be 1
        $result.Tasks[0].Content | Should -Match "Do it"
    }

    It "trims trailing whitespace from preamble and task content" {
        $plan = "Preamble text`n`n`n### Task 1: Setup`n`nContent`n`n`n"
        $result = Get-PlanTasks -PlanContent $plan
        $result.Preamble | Should -Not -Match "`n$"
        $result.Tasks[0].Content | Should -Not -Match "`n$"
    }

    It "includes task header in content" {
        $plan = "### Task 1: Setup`n`nDo it"
        $result = Get-PlanTasks -PlanContent $plan
        $result.Tasks[0].Content | Should -Match "^### Task 1: Setup"
    }
}
```

- [ ] Step 2: Run tests to verify they fail

Run: `Invoke-Pester -Path "C:\Users\vadash\.claude\skills\auto-execute\tests\auto-execute-helpers.Tests.ps1" -Tag '' -TestName "Get-PlanTasks" -Output Detailed 2>&1`
Expected: FAIL — `Get-PlanTasks` is not defined.

- [ ] Step 3: Remove the `Get-TotalTaskCount` function from `auto-execute-helpers.ps1` and add the `Get-PlanTasks` function in its place:

```powershell
function Get-PlanTasks {
    param(
        [Parameter(Mandatory)]
        [string]$PlanContent
    )

    $taskPattern = '(?mi)^#{2,3}\s*Task\s+(\d+)'
    $taskMatches = [regex]::Matches($PlanContent, $taskPattern)

    if ($taskMatches.Count -eq 0) {
        return @{ Preamble = $PlanContent; Tasks = @() }
    }

    # Preamble: everything before the first task header
    $firstIndex = $taskMatches[0].Index
    $preamble = if ($firstIndex -gt 0) {
        $PlanContent.Substring(0, $firstIndex).TrimEnd()
    } else { "" }

    # Extract each task block
    $tasks = @()
    for ($i = 0; $i -lt $taskMatches.Count; $i++) {
        $number = [int]$taskMatches[$i].Groups[1].Value
        $startIndex = $taskMatches[$i].Index
        $endIndex = if ($i + 1 -lt $taskMatches.Count) {
            $taskMatches[$i + 1].Index
        } else {
            $PlanContent.Length
        }
        $content = $PlanContent.Substring($startIndex, $endIndex - $startIndex).TrimEnd()
        $tasks += @{ Number = $number; Content = $content }
    }

    return @{ Preamble = $preamble; Tasks = $tasks }
}
```

- [ ] Step 4: Run tests to verify they pass

Run: `Invoke-Pester -Path "C:\Users\vadash\.claude\skills\auto-execute\tests\auto-execute-helpers.Tests.ps1" -Output Detailed 2>&1`
Expected: All tests pass, including all new `Get-PlanTasks` tests.

- [ ] Step 5: Commit

```bash
git add -A && git commit -m "feat: replace Get-TotalTaskCount with Get-PlanTasks parser"
```

### Task 6: Add Get-TaskNumberGaps function with TDD

**Files:**
- Modify: `auto-execute-helpers.ps1`
- Modify: `tests/auto-execute-helpers.Tests.ps1`

- [ ] Step 1: Add the following test block to `tests/auto-execute-helpers.Tests.ps1` (after the `Get-PlanTasks` Describe block):

```powershell
Describe "Get-TaskNumberGaps" {
    It "returns empty array for sequential tasks" {
        $result = @(Get-TaskNumberGaps -TaskNumbers @(1, 2, 3, 4))
        $result.Count | Should -Be 0
    }

    It "detects single gap" {
        $result = @(Get-TaskNumberGaps -TaskNumbers @(1, 2, 4, 5))
        $result.Count | Should -Be 1
        $result | Should -Contain 3
    }

    It "detects multiple gaps" {
        $result = @(Get-TaskNumberGaps -TaskNumbers @(1, 4, 7))
        $result | Should -Contain 2
        $result | Should -Contain 3
        $result | Should -Contain 5
        $result | Should -Contain 6
        $result.Count | Should -Be 4
    }

    It "returns empty for single task" {
        $result = @(Get-TaskNumberGaps -TaskNumbers @(1))
        $result.Count | Should -Be 0
    }

    It "returns empty for empty input" {
        $result = @(Get-TaskNumberGaps -TaskNumbers @())
        $result.Count | Should -Be 0
    }

    It "handles unsorted input" {
        $result = @(Get-TaskNumberGaps -TaskNumbers @(3, 1, 5))
        $result | Should -Contain 2
        $result | Should -Contain 4
        $result.Count | Should -Be 2
    }
}
```

- [ ] Step 2: Run the new tests to verify they fail

Run: `Invoke-Pester -Path "C:\Users\vadash\.claude\skills\auto-execute\tests\auto-execute-helpers.Tests.ps1" -Tag '' -TestName "Get-TaskNumberGaps" -Output Detailed 2>&1`
Expected: FAIL — `Get-TaskNumberGaps` is not defined.

- [ ] Step 3: Add the function to `auto-execute-helpers.ps1` (after `Get-PlanTasks`):

```powershell
function Get-TaskNumberGaps {
    param(
        [Parameter(Mandatory)]
        [int[]]$TaskNumbers
    )

    if ($TaskNumbers.Count -eq 0) { return @() }

    $sorted = $TaskNumbers | Sort-Object
    $max = $sorted[-1]
    $expected = 1..$max
    $missing = @($expected | Where-Object { $_ -notin $sorted })
    return $missing
}
```

- [ ] Step 4: Run tests to verify they pass

Run: `Invoke-Pester -Path "C:\Users\vadash\.claude\skills\auto-execute\tests\auto-execute-helpers.Tests.ps1" -Output Detailed 2>&1`
Expected: All tests pass.

- [ ] Step 5: Commit

```bash
git add -A && git commit -m "feat: add Get-TaskNumberGaps helper"
```

### Task 7: Add Write-TaskTempFile function with TDD

**Files:**
- Modify: `auto-execute-helpers.ps1`
- Modify: `tests/auto-execute-helpers.Tests.ps1`

- [ ] Step 1: Add the following test block to `tests/auto-execute-helpers.Tests.ps1` (after the `Get-TaskNumberGaps` Describe block):

```powershell
Describe "Write-TaskTempFile" {
    BeforeEach {
        $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "pester-tempfile-$(Get-Random)"
        New-Item -ItemType Directory -Path $script:tempDir -Force | Out-Null
    }

    AfterEach {
        Remove-Item -Path $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "creates temp file with preamble, task content, and footer" {
        $result = Write-TaskTempFile -LogDir $script:tempDir -TaskNumber 3 `
            -TaskContent "### Task 3: Build`n`nStep 1: Do it" `
            -Preamble "# My Plan`n`n**Goal:** Something" `
            -PlanPath "docs/plans/my-plan.md"

        $result | Should -Be (Join-Path $script:tempDir "task-3.md")
        Test-Path $result | Should -BeTrue
        $content = Get-Content $result -Raw
        $content | Should -Match "My Plan"
        $content | Should -Match "Goal"
        $content | Should -Match "Task 3: Build"
        $content | Should -Match "Step 1: Do it"
        $content | Should -Match "Full plan: docs/plans/my-plan.md"
    }

    It "skips preamble section when preamble is empty" {
        $result = Write-TaskTempFile -LogDir $script:tempDir -TaskNumber 1 `
            -TaskContent "### Task 1: Setup`n`nDo it" `
            -Preamble "" `
            -PlanPath "plan.md"

        $content = Get-Content $result -Raw
        $content | Should -Match "^### Task 1: Setup"
        $content | Should -Match "Full plan: plan.md"
    }

    It "returns correct file path with task number" {
        $result = Write-TaskTempFile -LogDir $script:tempDir -TaskNumber 7 `
            -TaskContent "### Task 7: Final" -PlanPath "plan.md"
        $result | Should -BeLike "*task-7.md"
    }

    It "includes full plan link in footer" {
        $result = Write-TaskTempFile -LogDir $script:tempDir -TaskNumber 1 `
            -TaskContent "content" -Preamble "preamble" `
            -PlanPath "docs/plans/2026-03-14-example.md"

        $content = Get-Content $result -Raw
        $content | Should -Match "Full plan: docs/plans/2026-03-14-example.md"
        $content | Should -Match "broader context"
    }
}
```

- [ ] Step 2: Run the new tests to verify they fail

Run: `Invoke-Pester -Path "C:\Users\vadash\.claude\skills\auto-execute\tests\auto-execute-helpers.Tests.ps1" -Tag '' -TestName "Write-TaskTempFile" -Output Detailed 2>&1`
Expected: FAIL — `Write-TaskTempFile` is not defined.

- [ ] Step 3: Add the function to `auto-execute-helpers.ps1` (after `Get-TaskNumberGaps`):

```powershell
function Write-TaskTempFile {
    param(
        [Parameter(Mandatory)]
        [string]$LogDir,
        [Parameter(Mandatory)]
        [int]$TaskNumber,
        [Parameter(Mandatory)]
        [string]$TaskContent,
        [string]$Preamble = "",
        [Parameter(Mandatory)]
        [string]$PlanPath
    )

    $parts = @()
    if ($Preamble) {
        $parts += $Preamble
        $parts += ""
        $parts += "---"
        $parts += ""
    }
    $parts += $TaskContent
    $parts += ""
    $parts += "---"
    $parts += "Full plan: $PlanPath"
    $parts += "If this task references other tasks or you need broader context, read the full plan above."

    $tempPath = Join-Path $LogDir "task-$TaskNumber.md"
    $parts -join "`n" | Set-Content -Path $tempPath -Encoding UTF8 -NoNewline
    return $tempPath
}
```

- [ ] Step 4: Run tests to verify they pass

Run: `Invoke-Pester -Path "C:\Users\vadash\.claude\skills\auto-execute\tests\auto-execute-helpers.Tests.ps1" -Output Detailed 2>&1`
Expected: All tests pass.

- [ ] Step 5: Commit

```bash
git add -A && git commit -m "feat: add Write-TaskTempFile helper"
```

### Task 8: Update Clear-LogDirectory to clean task temp files

**Files:**
- Modify: `auto-execute-helpers.ps1`
- Modify: `tests/auto-execute-helpers.Tests.ps1`

- [ ] Step 1: Add the following test to the existing `Describe "Clear-LogDirectory"` block in `tests/auto-execute-helpers.Tests.ps1`, after the existing tests:

```powershell
    It "removes task-*.md temp files alongside logs" {
        "task content" | Out-File (Join-Path $script:tempLogDir "task-1.md")
        "task content" | Out-File (Join-Path $script:tempLogDir "task-2.md")
        "log content" | Out-File (Join-Path $script:tempLogDir "task-1.log")
        "keep me" | Out-File (Join-Path $script:tempLogDir "notes.txt")

        Clear-LogDirectory -LogDir $script:tempLogDir

        Test-Path (Join-Path $script:tempLogDir "task-1.md") | Should -BeFalse
        Test-Path (Join-Path $script:tempLogDir "task-2.md") | Should -BeFalse
        Test-Path (Join-Path $script:tempLogDir "task-1.log") | Should -BeFalse
        Test-Path (Join-Path $script:tempLogDir "notes.txt") | Should -BeTrue
    }
```

- [ ] Step 2: Run the new test to verify it fails

Run: `Invoke-Pester -Path "C:\Users\vadash\.claude\skills\auto-execute\tests\auto-execute-helpers.Tests.ps1" -Tag '' -TestName "Clear-LogDirectory" -Output Detailed 2>&1`
Expected: FAIL — the `task-*.md` files are not removed by the current implementation.

- [ ] Step 3: Add a line to the `Clear-LogDirectory` function in `auto-execute-helpers.ps1`. After the existing `.log.err` cleanup line, add:

```powershell
    Get-ChildItem -Path "$LogDir/task-*.md" -File -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
```

- [ ] Step 4: Run tests to verify they pass

Run: `Invoke-Pester -Path "C:\Users\vadash\.claude\skills\auto-execute\tests\auto-execute-helpers.Tests.ps1" -Tag '' -TestName "Clear-LogDirectory" -Output Detailed 2>&1`
Expected: All `Clear-LogDirectory` tests pass.

- [ ] Step 5: Commit

```bash
git add -A && git commit -m "feat: clear task temp files in Clear-LogDirectory"
```

### Task 9: Change stash pop to stash drop on backup success

**Files:**
- Modify: `auto-execute.ps1`

- [ ] Step 1: In `auto-execute.ps1`, find the success branch inside the main loop where stash is popped. Change `git stash pop` to `git stash drop`. The current code is:

```powershell
            if ($stashedThisTask) {
                git stash pop 2>&1 | Out-Null
                Write-Host "Task ${currentTask}: Popped stash from earlier attempt." -ForegroundColor DarkGray
            }
```

Replace with:

```powershell
            if ($stashedThisTask) {
                git stash drop 2>&1 | Out-Null
                Write-Host "Task ${currentTask}: Dropped stash from failed attempt." -ForegroundColor DarkGray
            }
```

- [ ] Step 2: Commit

```bash
git add -A && git commit -m "fix: stash drop instead of pop on backup success"
```

### Task 10: Wire task splitting into auto-execute.ps1 and update SKILL.md input

**Files:**
- Modify: `auto-execute.ps1`
- Modify: `SKILL.md`

This task replaces the Phase 2 (Task Tracking) and the main loop prompt/iteration logic in `auto-execute.ps1`, then updates `SKILL.md` to match the new input format.

- [ ] Step 1: In `auto-execute.ps1`, replace the Phase 2 section. Find the block starting with `# --- Phase 2: Task Tracking ---` and ending just before `# Clean old log files`. Replace it with:

```powershell
# --- Phase 2: Task Tracking ---
$planContent = Get-Content $Plan -Raw
$planData = Get-PlanTasks -PlanContent $planContent
$totalTasks = $planData.Tasks.Count

if ($totalTasks -eq 0) {
    Write-Host "Error: No tasks found in plan file." -ForegroundColor Red
    exit 1
}

# Gap detection
$taskNumbers = $planData.Tasks | ForEach-Object { $_.Number }
$gaps = Get-TaskNumberGaps -TaskNumbers $taskNumbers
if ($gaps.Count -gt 0) {
    $foundStr = ($taskNumbers | Sort-Object) -join ", "
    $missingStr = $gaps -join ", "
    Write-Host "WARNING: Gap in task numbering. Found: $foundStr (missing: $missingStr)." -ForegroundColor Yellow
    $response = Read-Host "Continue anyway? [Y/n]"
    if ($response -match '^[Nn]') {
        Write-Host "Aborted." -ForegroundColor Red
        exit 1
    }
}

# Determine starting index
$taskIndex = 0
if ($StartTask -gt 0) {
    $found = $false
    for ($i = 0; $i -lt $planData.Tasks.Count; $i++) {
        if ($planData.Tasks[$i].Number -ge $StartTask) {
            $taskIndex = $i
            $found = $true
            break
        }
    }
    if (-not $found) {
        Write-Host "All tasks in the plan are already complete!" -ForegroundColor Green
        exit 0
    }
    Write-Host "Resuming from task $($planData.Tasks[$taskIndex].Number) (user specified)" -ForegroundColor Cyan
} else {
    Write-Host "Starting from task $($planData.Tasks[0].Number)" -ForegroundColor Cyan
}

Write-Host "Starting auto-execute: $totalTasks tasks" -ForegroundColor Cyan
Write-Host "Plan: $Plan" -ForegroundColor Cyan
$ctxLimitStr = Format-ContextSize $ContextLimit
$backupStr = if ($BackupClaudeBin) { " (backup: $BackupClaudeBin)" } else { "" }
Write-Host "CLI: $ClaudeBin$backupStr | MaxTurns: $MaxTurns | Timeout: ${TaskTimeout}s | MaxFailures: $MaxFailures | ContextLimit: $ctxLimitStr" -ForegroundColor Cyan
```

- [ ] Step 2: In the main loop, replace the loop condition. Change:

```powershell
    while ($running -and $currentTask -le $totalTasks) {
```

to:

```powershell
    while ($running -and $taskIndex -lt $planData.Tasks.Count) {
        $currentTask = $planData.Tasks[$taskIndex].Number
```

- [ ] Step 3: In the main loop, add temp file generation right after the `Write-Host "--- Task ..."` line. Before the `# Build prompt and execute` comment, add:

```powershell
        # Write per-task temp file
        $tempTaskPath = Write-TaskTempFile -LogDir $LogDir -TaskNumber $currentTask `
            -TaskContent $planData.Tasks[$taskIndex].Content `
            -Preamble $planData.Preamble -PlanPath $Plan
```

- [ ] Step 4: Change the prompt text. Replace:

```powershell
        $promptText = "/auto-execute @$Plan do task $currentTask"
```

with:

```powershell
        $promptText = "/auto-execute $tempTaskPath"
```

- [ ] Step 5: In the success branch, replace `$currentTask++` with `$taskIndex++`. Find:

```powershell
            $currentTask++
```

Replace with:

```powershell
            $taskIndex++
```

- [ ] Step 6: Update the `isLastTask` check. Replace:

```powershell
        $isLastTask = ($currentTask -eq $totalTasks)
```

with:

```powershell
        $isLastTask = ($taskIndex -eq $planData.Tasks.Count - 1)
```

- [ ] Step 7: Update the loop completion check after the while loop. Replace:

```powershell
    if ($currentTask -gt $totalTasks -and $running) {
```

with:

```powershell
    if ($taskIndex -ge $planData.Tasks.Count -and $running) {
```

- [ ] Step 8: In the `finally` block, update the NextTask calculation for `Format-FinalReport`. Replace `$currentTask` in the `-NextTask` parameter with a value that is 0 when all tasks are done:

Find the line calling `Format-FinalReport` and change the `-NextTask $currentTask` to:

```powershell
        -NextTask $(if ($taskIndex -lt $planData.Tasks.Count) { $planData.Tasks[$taskIndex].Number } else { 0 })
```

- [ ] Step 9: In `Format-FinalReport` in `auto-execute-helpers.ps1`, simplify the resume hint condition. Replace:

```powershell
    if ($StopReason -ne "All tasks complete" -and $NextTask -gt 0 -and $NextTask -le $TotalTasks) {
```

with:

```powershell
    if ($StopReason -ne "All tasks complete" -and $NextTask -gt 0) {
```

- [ ] Step 10: Update the `SKILL.md` Input section. Replace the entire `## Input` section with:

```markdown
## Input

Parse `$ARGUMENTS` to get the path to the task temp file, then read it.

The temp file contains:
1. **Preamble** — project goal, architecture, and constraints from the plan
2. **Task content** — the specific task to execute (including the task header)
3. **Footer** — link to the full plan file if you need broader context

Example: `/auto-execute logs/auto-execute/task-3.md`
```

- [ ] Step 11: Run all tests to verify nothing is broken

Run: `Invoke-Pester -Path "C:\Users\vadash\.claude\skills\auto-execute\tests\auto-execute-helpers.Tests.ps1" -Output Detailed 2>&1`
Expected: All tests pass.

- [ ] Step 12: Commit

```bash
git add -A && git commit -m "feat: wire task splitting into main loop and update SKILL input format"
```

### Task 11: Replace wall-clock timeout with activity-based timeout

**Files:**
- Modify: `auto-execute.ps1`

- [ ] Step 1: Change the default `$TaskTimeout` value from `900` to `600` in the param block. Replace:

```powershell
    [int]    $TaskTimeout  = 900,
```

with:

```powershell
    [int]    $TaskTimeout  = 600,
```

- [ ] Step 2: Inside the main loop, add an activity timer. Right after the existing line `$taskStart = [System.Diagnostics.Stopwatch]::StartNew()`, add:

```powershell
        $lastActivity = [System.Diagnostics.Stopwatch]::StartNew()
```

- [ ] Step 3: Reset the activity timer when stream-json events are received. Find the block that processes parsed events (after `$parsed = Read-StreamJsonChunk`). After the line:

```powershell
                    $buffer = $parsed.Buffer
```

Add:

```powershell
                    if ($parsed.Events.Count -gt 0) {
                        $lastActivity.Restart()
                    }
```

- [ ] Step 4: Replace the timeout check. Find:

```powershell
            # Timeout check
            if (-not $exited -and $taskStart.Elapsed.TotalSeconds -gt $TaskTimeout) {
                Write-Host "`n[TIMEOUT] Task $currentTask exceeded $TaskTimeout seconds." -ForegroundColor Red
```

Replace with:

```powershell
            # Timeout check (activity-based: resets on stream-json events)
            if (-not $exited -and $lastActivity.Elapsed.TotalSeconds -gt $TaskTimeout) {
                Write-Host "`n[TIMEOUT] Task $currentTask idle for $TaskTimeout seconds." -ForegroundColor Red
```

- [ ] Step 5: Commit

```bash
git add -A && git commit -m "feat: replace wall-clock timeout with activity-based idle timeout (600s default)"
```

### Task 12: Update CLAUDE.md and README.md

**Files:**
- Modify: `CLAUDE.md`
- Modify: `README.md`

- [ ] Step 1: In `CLAUDE.md`, update the architecture table. Remove the row for **Hooks** (`.claude/hooks/` | Real-time safety: context limit, loop detection). The table should only have **Wrapper** and **Skill** rows.

- [ ] Step 2: In `CLAUDE.md`, remove `AXE_ACTIVE` from the description. Update the sentence "Three components, all gated by `AXE_ACTIVE` environment variable:" to "Two components:".

- [ ] Step 3: In `CLAUDE.md` Safety Guards section, remove the bullet about **Hooks** (loop detection). Also remove any mention of `AXE_ACTIVE`. Update the **Per-task timeout** description to reflect activity-based semantics and the 600s default. Add a bullet for **Task splitting**: pre-flight parsing, gap detection, per-task temp files.

- [ ] Step 4: In `CLAUDE.md` Key Files section, remove `.claude/hooks/` entry. Add a note that `Get-PlanTasks`, `Get-TaskNumberGaps`, and `Write-TaskTempFile` are in `auto-execute-helpers.ps1`.

- [ ] Step 5: In `README.md`, update the Architecture table to remove the **Hooks** row.

- [ ] Step 6: In `README.md`, update the Prerequisites section — remove any mention of hooks or `AXE_ACTIVE`.

- [ ] Step 7: In `README.md`, remove the entire "Installation > Hooks (per-repo, required for safety guards)" subsection and the "Gitignore" subsection note about hooks.

- [ ] Step 8: In `README.md`, update the Parameters table:
  - Change `-TaskTimeout` default from `900` to `600` and description to mention idle time (e.g., "Seconds of idle time before killing a stuck task")

- [ ] Step 9: In `README.md`, update the "What it does" section to mention task splitting (pre-flight parsing + temp file generation) and remove references to hooks.

- [ ] Step 10: In `README.md`, remove the "Safety hooks" section entirely (the one describing `axe-loop-detect.ps1`).

- [ ] Step 11: In `README.md`, update the file map: remove `.claude/hooks/axe-loop-detect.ps1` and `tests/loop-detect.Tests.ps1` entries.

- [ ] Step 12: Run all tests to confirm nothing references deleted content

Run: `Invoke-Pester -Path "C:\Users\vadash\.claude\skills\auto-execute\tests" -Output Detailed 2>&1`
Expected: All tests pass.

- [ ] Step 13: Commit

```bash
git add -A && git commit -m "docs: update CLAUDE.md and README.md for robustness improvements"
```
