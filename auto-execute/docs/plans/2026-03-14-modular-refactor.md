# Modular Refactor Implementation Plan

**Goal:** Move functions from `auto-execute-helpers.ps1` into `src/` modules, extract the monitoring loop into `Invoke-TaskMonitor`, update tests to mirror the new layout, then delete the old files.
**Architecture:** Six `src/*.ps1` modules (args, plan, preflight, stream, format, monitor) replace a single helpers file. Each module has a mirrored `tests/*.Tests.ps1`. The main script `auto-execute.ps1` dot-sources the modules and calls `Invoke-TaskMonitor` instead of inlining the monitoring loop.
**Tech Stack:** PowerShell 5.1+, Pester 5.x, Git

---

### Task 1: Create src/args.ps1 and tests/args.Tests.ps1

**Files:**
- Create: `src/args.ps1`
- Create: `tests/args.Tests.ps1`

- [ ] Step 1: Create `src/` directory and write the failing test file

Create directory `src/` (it does not exist yet). Then create `tests/args.Tests.ps1` that sources `src/args.ps1`:

```powershell
# tests/args.Tests.ps1
BeforeAll {
    . "$PSScriptRoot/../src/args.ps1"
}

Describe "Split-AxeArguments" {
    It "parses single claude binary and plan" {
        $result = Split-AxeArguments -Arguments @("claude_stable_ali", "mask-endpoint")
        $result.MainClaude | Should -Be "claude_stable_ali"
        $result.BackupClaude | Should -BeNull
        $result.PlanInput | Should -Be "mask-endpoint"
    }

    It "parses two claude binaries and plan" {
        $result = Split-AxeArguments -Arguments @("claude_stable_ali", "claude_stable_any", "mask-endpoint")
        $result.MainClaude | Should -Be "claude_stable_ali"
        $result.BackupClaude | Should -Be "claude_stable_any"
        $result.PlanInput | Should -Be "mask-endpoint"
    }

    It "handles plan argument between claude binaries" {
        $result = Split-AxeArguments -Arguments @("claude_stable_ali", "mask-endpoint", "claude_stable_any")
        $result.MainClaude | Should -Be "claude_stable_ali"
        $result.BackupClaude | Should -Be "claude_stable_any"
        $result.PlanInput | Should -Be "mask-endpoint"
    }

    It "matches claude prefix case-insensitively" {
        $result = Split-AxeArguments -Arguments @("Claude_Stable", "my-plan")
        $result.MainClaude | Should -Be "Claude_Stable"
        $result.PlanInput | Should -Be "my-plan"
    }

    It "handles bare claude binary name" {
        $result = Split-AxeArguments -Arguments @("claude", "my-plan")
        $result.MainClaude | Should -Be "claude"
        $result.BackupClaude | Should -BeNull
        $result.PlanInput | Should -Be "my-plan"
    }

    It "throws when no claude binary is provided" {
        { Split-AxeArguments -Arguments @("mask-endpoint") } |
            Should -Throw "*No claude binary*"
    }

    It "throws when no plan argument is provided" {
        { Split-AxeArguments -Arguments @("claude_stable_ali") } |
            Should -Throw "*No plan argument*"
    }

    It "throws when more than 2 claude binaries are provided" {
        { Split-AxeArguments -Arguments @("claude_a", "claude_b", "claude_c", "my-plan") } |
            Should -Throw "*Too many claude binaries*"
    }

    It "throws when more than 1 non-claude argument is provided" {
        { Split-AxeArguments -Arguments @("claude_a", "plan1", "plan2") } |
            Should -Throw "*Too many non-claude arguments*"
    }
}
```

- [ ] Step 2: Run test to verify it fails

Run: `Invoke-Pester -Path "C:\Users\vadash\.claude\skills\auto-execute\tests\args.Tests.ps1" -Output Detailed 2>&1`
Expected: FAIL — `src/args.ps1` does not exist, BeforeAll fails

- [ ] Step 3: Create `src/args.ps1` with the `Split-AxeArguments` function

Copy the function verbatim from `auto-execute-helpers.ps1`:

```powershell
# src/args.ps1 — CLI argument parsing

function Split-AxeArguments {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $claudeBinaries = @()
    $otherArgs = @()

    foreach ($arg in $Arguments) {
        if ($arg -match '^claude') {
            $claudeBinaries += $arg
        } else {
            $otherArgs += $arg
        }
    }

    if ($claudeBinaries.Count -eq 0) {
        throw "No claude binary specified. At least one argument must start with 'claude'."
    }
    if ($claudeBinaries.Count -gt 2) {
        throw "Too many claude binaries specified (max 2). Got: $($claudeBinaries -join ', ')"
    }
    if ($otherArgs.Count -eq 0) {
        throw "No plan argument found. One non-claude argument is required."
    }
    if ($otherArgs.Count -gt 1) {
        throw "Too many non-claude arguments (max 1). Got: $($otherArgs -join ', ')"
    }

    return @{
        MainClaude   = $claudeBinaries[0]
        BackupClaude = if ($claudeBinaries.Count -gt 1) { $claudeBinaries[1] } else { $null }
        PlanInput    = $otherArgs[0]
    }
}
```

- [ ] Step 4: Run test to verify it passes

Run: `Invoke-Pester -Path "C:\Users\vadash\.claude\skills\auto-execute\tests\args.Tests.ps1" -Output Detailed 2>&1`
Expected: PASS — all 9 tests green

- [ ] Step 5: Commit

```bash
git add -A && git commit -m "feat: create src/args.ps1 and tests/args.Tests.ps1"
```

---

### Task 2: Create src/plan.ps1 and tests/plan.Tests.ps1

**Files:**
- Create: `src/plan.ps1`
- Create: `tests/plan.Tests.ps1`

- [ ] Step 1: Write the failing test file

Create `tests/plan.Tests.ps1`:

```powershell
# tests/plan.Tests.ps1
BeforeAll {
    . "$PSScriptRoot/../src/plan.ps1"
}

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

Describe "Resolve-PlanPath" {
    BeforeAll {
        $script:tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "axe-test-$(Get-Random)"
        $script:plansDir = Join-Path $script:tempRoot "docs/plans"
        New-Item -ItemType Directory -Path $script:plansDir -Force | Out-Null
        "plan1" | Out-File (Join-Path $script:plansDir "2026-03-10-auth-login.md")
        "plan2" | Out-File (Join-Path $script:plansDir "2026-03-11-auth-signup.md")
        "plan3" | Out-File (Join-Path $script:plansDir "2026-03-12-markdown-link-checker.md")
    }

    AfterAll {
        Remove-Item -Recurse -Force $script:tempRoot -ErrorAction SilentlyContinue
    }

    It "passes through an existing file path unchanged" {
        $existingFile = Join-Path $script:plansDir "2026-03-10-auth-login.md"
        $result = Resolve-PlanPath -PlanInput $existingFile
        $result | Should -Be $existingFile
    }

    It "resolves a partial name to a single match" {
        $result = Resolve-PlanPath -PlanInput "markdown-link" -SearchDir $script:plansDir
        $result | Should -BeLike "*2026-03-12-markdown-link-checker.md"
    }

    It "resolves a full plan filename without extension" {
        $result = Resolve-PlanPath -PlanInput "2026-03-12-markdown-link-checker" -SearchDir $script:plansDir
        $result | Should -BeLike "*2026-03-12-markdown-link-checker.md"
    }

    It "throws on ambiguous match with list of candidates" {
        { Resolve-PlanPath -PlanInput "auth" -SearchDir $script:plansDir } |
            Should -Throw "*Ambiguous*auth-login*auth-signup*"
    }

    It "throws when no plan matches" {
        { Resolve-PlanPath -PlanInput "nonexistent" -SearchDir $script:plansDir } |
            Should -Throw "*No plan matching*"
    }

    It "throws when search directory does not exist" {
        { Resolve-PlanPath -PlanInput "anything" -SearchDir "/no/such/dir" } |
            Should -Throw "*No plan matching*"
    }
}
```

- [ ] Step 2: Run test to verify it fails

Run: `Invoke-Pester -Path "C:\Users\vadash\.claude\skills\auto-execute\tests\plan.Tests.ps1" -Output Detailed 2>&1`
Expected: FAIL — `src/plan.ps1` does not exist

- [ ] Step 3: Create `src/plan.ps1` with the four plan functions

Copy verbatim from `auto-execute-helpers.ps1`:

```powershell
# src/plan.ps1 — Plan parsing and resolution

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

    $firstIndex = $taskMatches[0].Index
    $preamble = if ($firstIndex -gt 0) {
        $PlanContent.Substring(0, $firstIndex).TrimEnd()
    } else { "" }

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

function Get-TaskNumberGaps {
    param(
        [Parameter()]
        [int[]]$TaskNumbers
    )

    if (-not $TaskNumbers -or $TaskNumbers.Count -eq 0) { return @() }

    $sorted = $TaskNumbers | Sort-Object
    $max = $sorted[-1]
    $expected = 1..$max
    $missing = @($expected | Where-Object { $_ -notin $sorted })
    return $missing
}

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

function Resolve-PlanPath {
    param(
        [Parameter(Mandatory)]
        [string]$PlanInput,
        [string]$SearchDir = "docs/plans"
    )

    if (Test-Path $PlanInput) {
        return $PlanInput
    }

    if (Test-Path $SearchDir) {
        $fileName = Split-Path -Leaf $PlanInput

        if ($fileName -like "*.md") {
            $candidates = Get-ChildItem -Path $SearchDir -Filter "*$fileName" -File
        } else {
            $candidates = Get-ChildItem -Path $SearchDir -Filter "*$fileName*.md" -File
        }
    } else {
        $candidates = @()
    }

    if ($candidates.Count -eq 1) {
        return $candidates[0].FullName
    }

    if ($candidates.Count -gt 1) {
        $names = ($candidates | ForEach-Object { $_.Name }) -join ", "
        throw "Ambiguous plan name '$PlanInput'. Matches: $names"
    }

    throw "No plan matching '$PlanInput' in $SearchDir"
}
```

- [ ] Step 4: Run test to verify it passes

Run: `Invoke-Pester -Path "C:\Users\vadash\.claude\skills\auto-execute\tests\plan.Tests.ps1" -Output Detailed 2>&1`
Expected: PASS — all 20 tests green

- [ ] Step 5: Commit

```bash
git add -A && git commit -m "feat: create src/plan.ps1 and tests/plan.Tests.ps1"
```

---

### Task 3: Create src/preflight.ps1 and tests/preflight.Tests.ps1

**Files:**
- Create: `src/preflight.ps1`
- Create: `tests/preflight.Tests.ps1`

- [ ] Step 1: Write the failing test file

Create `tests/preflight.Tests.ps1`:

```powershell
# tests/preflight.Tests.ps1
BeforeAll {
    . "$PSScriptRoot/../src/preflight.ps1"
}

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

    It "creates log directory if it does not exist" {
        $tempPlan = [System.IO.FileInfo]([System.IO.Path]::GetTempFileName())
        try {
            Set-Content $tempPlan.FullName "### Task 1: Test`nStep 1: Do it"
            Test-PreFlightLate -PlanPath $tempPlan.FullName -LogDir $script:tempLogDir | Out-Null
            Test-Path $script:tempLogDir | Should -BeTrue
        } finally {
            Remove-Item $tempPlan.FullName -ErrorAction SilentlyContinue
        }
    }
}

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
```

- [ ] Step 2: Run test to verify it fails

Run: `Invoke-Pester -Path "C:\Users\vadash\.claude\skills\auto-execute\tests\preflight.Tests.ps1" -Output Detailed 2>&1`
Expected: FAIL — `src/preflight.ps1` does not exist

- [ ] Step 3: Create `src/preflight.ps1` with the four preflight functions

Copy verbatim from `auto-execute-helpers.ps1`:

```powershell
# src/preflight.ps1 — Pre-flight checks and verification

function Test-PreFlightEarly {
    param(
        [string]$ClaudeBin,
        [string]$PlanPath
    )

    $errors = @()

    if (-not (Get-Command $ClaudeBin -ErrorAction SilentlyContinue)) {
        $errors += "CLI binary '$ClaudeBin' not found in PATH."
    }

    if (-not (Test-Path $PlanPath)) {
        $errors += "Plan file '$PlanPath' not found."
    }

    $null = git rev-parse --git-dir 2>&1
    if ($LASTEXITCODE -ne 0) {
        $errors += "Not inside a git repository."
    }

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

    if (-not (Test-Path $LogDir)) {
        try {
            New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
        } catch {
            $errors += "Cannot create log directory '$LogDir': $_"
        }
    }

    return $errors
}

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

function Save-DirtyState {
    param(
        [int]$TaskNumber
    )

    $stashMsg = "auto-execute: partial task $TaskNumber"
    git stash --include-untracked -m $stashMsg 2>&1
    return $LASTEXITCODE -eq 0
}
```

- [ ] Step 4: Run test to verify it passes

Run: `Invoke-Pester -Path "C:\Users\vadash\.claude\skills\auto-execute\tests\preflight.Tests.ps1" -Output Detailed 2>&1`
Expected: PASS — all 9 tests green

- [ ] Step 5: Commit

```bash
git add -A && git commit -m "feat: create src/preflight.ps1 and tests/preflight.Tests.ps1"
```

---

### Task 4: Create src/stream.ps1 and tests/stream.Tests.ps1

**Files:**
- Create: `src/stream.ps1`
- Create: `tests/stream.Tests.ps1`

- [ ] Step 1: Write the failing test file

Create `tests/stream.Tests.ps1`:

```powershell
# tests/stream.Tests.ps1
BeforeAll {
    . "$PSScriptRoot/../src/stream.ps1"
}

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

Describe "Get-ContextSizeFromEvent" {
    It "returns input_tokens + cache_read from assistant event" {
        $json = '{"type":"assistant","message":{"usage":{"input_tokens":2943,"output_tokens":27,"cache_read_input_tokens":5305,"cache_creation_input_tokens":1000}}}'
        $event = $json | ConvertFrom-Json
        $result = Get-ContextSizeFromEvent -Event $event
        $result | Should -Be 8248
    }

    It "returns input_tokens alone when no cache reads" {
        $json = '{"type":"assistant","message":{"usage":{"input_tokens":3000,"output_tokens":50,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}'
        $event = $json | ConvertFrom-Json
        $result = Get-ContextSizeFromEvent -Event $event
        $result | Should -Be 3000
    }

    It "returns 0 for result events (cumulative totals)" {
        $json = '{"type":"result","usage":{"input_tokens":5980,"output_tokens":92,"cache_read_input_tokens":2000}}'
        $event = $json | ConvertFrom-Json
        $result = Get-ContextSizeFromEvent -Event $event
        $result | Should -Be 0
    }

    It "returns 0 from result without cache_read" {
        $json = '{"type":"result","usage":{"input_tokens":5980,"output_tokens":92}}'
        $event = $json | ConvertFrom-Json
        $result = Get-ContextSizeFromEvent -Event $event
        $result | Should -Be 0
    }

    It "returns 0 for system events" {
        $json = '{"type":"system","subtype":"init"}'
        $event = $json | ConvertFrom-Json
        $result = Get-ContextSizeFromEvent -Event $event
        $result | Should -Be 0
    }

    It "returns 0 for user events" {
        $json = '{"type":"user","message":{"content":[{"type":"tool_result","content":"ok"}]}}'
        $event = $json | ConvertFrom-Json
        $result = Get-ContextSizeFromEvent -Event $event
        $result | Should -Be 0
    }

    It "returns tokens from root-level usage (non-assistant event)" {
        $json = '{"type":"content_block_delta","usage":{"input_tokens":4000,"output_tokens":10,"cache_read_input_tokens":1000}}'
        $event = $json | ConvertFrom-Json
        $result = Get-ContextSizeFromEvent -Event $event
        $result | Should -Be 5000
    }

    It "handles missing cache_read_input_tokens in usage" {
        $json = '{"type":"assistant","message":{"usage":{"input_tokens":3000,"output_tokens":50}}}'
        $event = $json | ConvertFrom-Json
        $result = Get-ContextSizeFromEvent -Event $event
        $result | Should -Be 3000
    }

    It "handles missing input_tokens in usage" {
        $json = '{"type":"assistant","message":{"usage":{"output_tokens":50,"cache_read_input_tokens":2000}}}'
        $event = $json | ConvertFrom-Json
        $result = Get-ContextSizeFromEvent -Event $event
        $result | Should -Be 2000
    }
}

Describe "Get-ClaudeProjectHash" {
    It "converts a Windows path to Claude project hash" {
        Get-ClaudeProjectHash -DirPath 'C:\projects\test_project' | Should -Be 'C--projects-test-project'
    }

    It "converts path with dots" {
        Get-ClaudeProjectHash -DirPath 'C:\Users\vadash\.claude\skills' | Should -Be 'C--Users-vadash--claude-skills'
    }

    It "converts a simple path" {
        Get-ClaudeProjectHash -DirPath 'C:\temp' | Should -Be 'C--temp'
    }

    It "converts forward-slash paths" {
        Get-ClaudeProjectHash -DirPath 'C:/projects/myapp' | Should -Be 'C--projects-myapp'
    }

    It "handles path with underscores" {
        Get-ClaudeProjectHash -DirPath 'C:\my_project' | Should -Be 'C--my-project'
    }
}

Describe "Get-TranscriptContextPeak" {
    BeforeEach {
        $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "pester-transcript-$(Get-Random)"
        New-Item -ItemType Directory -Path $script:tempDir -Force | Out-Null
    }

    AfterEach {
        Remove-Item -Path $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "returns peak context from transcript with real usage data" {
        $transcriptPath = Join-Path $script:tempDir "test.jsonl"
        $lines = @(
            '{"type":"user","message":{"usage":{"input_tokens":0,"output_tokens":0}}}'
            '{"type":"assistant","message":{"usage":{"input_tokens":274,"cache_creation_input_tokens":0,"cache_read_input_tokens":16387,"output_tokens":436}}}'
            '{"type":"user","message":{"usage":{"input_tokens":0,"output_tokens":0}}}'
            '{"type":"assistant","message":{"usage":{"input_tokens":458,"cache_creation_input_tokens":0,"cache_read_input_tokens":16660,"output_tokens":68}}}'
            '{"type":"assistant","message":{"usage":{"input_tokens":538,"cache_creation_input_tokens":0,"cache_read_input_tokens":17117,"output_tokens":231}}}'
        )
        $lines -join "`n" | Set-Content $transcriptPath -NoNewline

        $result = Get-TranscriptContextPeak -TranscriptPath $transcriptPath
        $result.PeakContext | Should -Be 17655
        $result.BytesRead | Should -BeGreaterThan 0
    }

    It "returns 0 for non-existent file" {
        $result = Get-TranscriptContextPeak -TranscriptPath (Join-Path $script:tempDir "nope.jsonl")
        $result.PeakContext | Should -Be 0
        $result.BytesRead | Should -Be 0
    }

    It "returns 0 for entries with zero tokens" {
        $transcriptPath = Join-Path $script:tempDir "zeros.jsonl"
        $lines = @(
            '{"type":"assistant","message":{"usage":{"input_tokens":0,"output_tokens":0}}}'
            '{"type":"assistant","message":{"usage":{"input_tokens":0,"output_tokens":0}}}'
        )
        $lines -join "`n" | Set-Content $transcriptPath -NoNewline

        $result = Get-TranscriptContextPeak -TranscriptPath $transcriptPath
        $result.PeakContext | Should -Be 0
    }

    It "supports incremental reads via StartOffset" {
        $transcriptPath = Join-Path $script:tempDir "incremental.jsonl"
        $line1 = '{"type":"assistant","message":{"usage":{"input_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":5000,"output_tokens":50}}}'
        $line2 = '{"type":"assistant","message":{"usage":{"input_tokens":200,"cache_creation_input_tokens":0,"cache_read_input_tokens":10000,"output_tokens":50}}}'

        "$line1`n" | Set-Content $transcriptPath -NoNewline
        $result1 = Get-TranscriptContextPeak -TranscriptPath $transcriptPath
        $result1.PeakContext | Should -Be 5100
        $offset = $result1.BytesRead

        [System.IO.File]::AppendAllText($transcriptPath, "$line2`n")
        $result2 = Get-TranscriptContextPeak -TranscriptPath $transcriptPath -StartOffset $offset
        $result2.PeakContext | Should -Be 10200

        $result2.BytesRead | Should -BeGreaterThan $offset
    }

    It "includes cache_creation_input_tokens in context size" {
        $transcriptPath = Join-Path $script:tempDir "cache-create.jsonl"
        $line = '{"type":"assistant","message":{"usage":{"input_tokens":300,"cache_creation_input_tokens":5000,"cache_read_input_tokens":2000,"output_tokens":50}}}'
        $line | Set-Content $transcriptPath -NoNewline

        $result = Get-TranscriptContextPeak -TranscriptPath $transcriptPath
        $result.PeakContext | Should -Be 7300
    }

    It "skips entries without message.usage" {
        $transcriptPath = Join-Path $script:tempDir "mixed.jsonl"
        $lines = @(
            '{"type":"queue-operation","operation":"enqueue"}'
            '{"type":"assistant","message":{"usage":{"input_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":8000,"output_tokens":50}}}'
            '{"type":"system","subtype":"init","session_id":"abc"}'
        )
        $lines -join "`n" | Set-Content $transcriptPath -NoNewline

        $result = Get-TranscriptContextPeak -TranscriptPath $transcriptPath
        $result.PeakContext | Should -Be 8100
    }

    It "handles invalid JSON lines gracefully" {
        $transcriptPath = Join-Path $script:tempDir "bad.jsonl"
        $lines = @(
            'not valid json at all'
            '{"type":"assistant","message":{"usage":{"input_tokens":500,"cache_creation_input_tokens":0,"cache_read_input_tokens":3000,"output_tokens":50}}}'
            '{"truncated json'
        )
        $lines -join "`n" | Set-Content $transcriptPath -NoNewline

        $result = Get-TranscriptContextPeak -TranscriptPath $transcriptPath
        $result.PeakContext | Should -Be 3500
    }
}
```

- [ ] Step 2: Run test to verify it fails

Run: `Invoke-Pester -Path "C:\Users\vadash\.claude\skills\auto-execute\tests\stream.Tests.ps1" -Output Detailed 2>&1`
Expected: FAIL — `src/stream.ps1` does not exist

- [ ] Step 3: Create `src/stream.ps1` with the six stream functions

Copy verbatim from `auto-execute-helpers.ps1`:

```powershell
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
```

- [ ] Step 4: Run test to verify it passes

Run: `Invoke-Pester -Path "C:\Users\vadash\.claude\skills\auto-execute\tests\stream.Tests.ps1" -Output Detailed 2>&1`
Expected: PASS — all 26 tests green

- [ ] Step 5: Commit

```bash
git add -A && git commit -m "feat: create src/stream.ps1 and tests/stream.Tests.ps1"
```

---

### Task 5: Create src/format.ps1 and tests/format.Tests.ps1

**Files:**
- Create: `src/format.ps1`
- Create: `tests/format.Tests.ps1`

- [ ] Step 1: Write the failing test file

Create `tests/format.Tests.ps1`:

```powershell
# tests/format.Tests.ps1
BeforeAll {
    . "$PSScriptRoot/../src/format.ps1"
}

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

    It "includes peak context when PeakContext and ContextLimit are provided" {
        $duration = [TimeSpan]::FromSeconds(120)
        $result = Format-TaskLogEntry -TaskNumber 1 -Passed $true -CommitHash "abc1234def" `
            -Duration $duration -PeakContext 45200 -ContextLimit 70000
        $result | Should -Match 'Peak ctx: 45\.2k/70\.0k'
    }

    It "omits peak context when PeakContext is 0" {
        $duration = [TimeSpan]::FromSeconds(120)
        $result = Format-TaskLogEntry -TaskNumber 1 -Passed $true -CommitHash "abc1234def" `
            -Duration $duration -PeakContext 0 -ContextLimit 70000
        $result | Should -Not -Match 'Peak ctx'
    }

    It "shows peak context before token string" {
        $duration = [TimeSpan]::FromSeconds(120)
        $tokenStr = " | Tokens: 10.0k In"
        $result = Format-TaskLogEntry -TaskNumber 1 -Passed $true -CommitHash "abc1234def" `
            -Duration $duration -PeakContext 52000 -ContextLimit 70000 -TokenString $tokenStr
        $result | Should -Match 'Peak ctx.*Tokens:'
    }

    It "includes claude binary name when ClaudeBin is provided" {
        $duration = [TimeSpan]::FromSeconds(120)
        $result = Format-TaskLogEntry -TaskNumber 1 -Passed $true -CommitHash "abc1234def" `
            -Duration $duration -ClaudeBin "claude_stable_ali"
        $result | Should -Match 'PASS \[claude_stable_ali\]'
    }

    It "includes claude binary name in failing entries" {
        $duration = [TimeSpan]::FromSeconds(45)
        $result = Format-TaskLogEntry -TaskNumber 2 -Passed $false -Duration $duration `
            -FailReason "no new commit" -ClaudeBin "claude_stable_any"
        $result | Should -Match 'FAIL \[claude_stable_any\]'
    }

    It "uses custom FailSuffix instead of STOPPED" {
        $duration = [TimeSpan]::FromSeconds(60)
        $result = Format-TaskLogEntry -TaskNumber 3 -Passed $false -Duration $duration `
            -FailReason "no new commit" -FailSuffix "retrying with backup"
        $result | Should -Match 'retrying with backup'
        $result | Should -Not -Match 'STOPPED'
    }

    It "omits binary tag when ClaudeBin is empty" {
        $duration = [TimeSpan]::FromSeconds(120)
        $result = Format-TaskLogEntry -TaskNumber 1 -Passed $true -CommitHash "abc1234def" `
            -Duration $duration
        $result | Should -Match 'PASS \(commit'
        $result | Should -Not -Match '\[.*\] \(commit'
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

    It "includes max peak context when provided" {
        $duration = [TimeSpan]::FromSeconds(600)
        $result = Format-FinalReport -PlanPath "plan.md" `
            -CompletedTasks 3 -TotalTasks 4 `
            -TotalDuration $duration `
            -StopReason "All tasks complete" `
            -LogFile "run.log" `
            -MaxPeakContext 52100 -ContextLimit 70000
        $result | Should -Match 'Max peak ctx: 52\.1k/70\.0k'
    }

    It "omits max peak context when MaxPeakContext is 0" {
        $duration = [TimeSpan]::FromSeconds(600)
        $result = Format-FinalReport -PlanPath "plan.md" `
            -CompletedTasks 3 -TotalTasks 4 `
            -TotalDuration $duration `
            -StopReason "All tasks complete" `
            -LogFile "run.log" `
            -MaxPeakContext 0 -ContextLimit 70000
        $result | Should -Not -Match 'Max peak ctx'
    }

    It "shows resume hint on failure with NextTask" {
        $duration = [TimeSpan]::FromSeconds(120)
        $result = Format-FinalReport -PlanPath "docs/plans/2026-03-13-my-plan.md" `
            -CompletedTasks 2 -TotalTasks 5 `
            -TotalDuration $duration `
            -StopReason "Max failures reached (2 consecutive)" `
            -LogFile "run.log" `
            -NextTask 3
        $result | Should -Match 'To resume manually:'
        $result | Should -Match '/executing-plans @docs/plans/2026-03-13-my-plan\.md do task 3'
    }

    It "omits resume hint when all tasks complete" {
        $duration = [TimeSpan]::FromSeconds(600)
        $result = Format-FinalReport -PlanPath "docs/plans/test.md" `
            -CompletedTasks 4 -TotalTasks 4 `
            -TotalDuration $duration `
            -StopReason "All tasks complete" `
            -LogFile "run.log" `
            -NextTask 5
        $result | Should -Not -Match 'To resume manually'
    }

    It "omits resume hint when NextTask is 0" {
        $duration = [TimeSpan]::FromSeconds(60)
        $result = Format-FinalReport -PlanPath "plan.md" `
            -CompletedTasks 3 -TotalTasks 3 `
            -TotalDuration $duration `
            -StopReason "Dirty tree (changes stashed)" `
            -LogFile "run.log" `
            -NextTask 0
        $result | Should -Not -Match 'To resume manually'
    }
}

Describe "Format-ContextSize" {
    It "formats thousands with k suffix" {
        Format-ContextSize -Tokens 45200 | Should -Be "45.2k"
    }

    It "formats millions with M suffix" {
        Format-ContextSize -Tokens 1500000 | Should -Be "1.5M"
    }

    It "formats small numbers as plain integers" {
        Format-ContextSize -Tokens 500 | Should -Be "500"
    }

    It "formats exactly 1000 as 1.0k" {
        Format-ContextSize -Tokens 1000 | Should -Be "1.0k"
    }

    It "formats 70000 as 70.0k" {
        Format-ContextSize -Tokens 70000 | Should -Be "70.0k"
    }
}

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
        $inputPart = $result.Substring(14)
        $inputPart.Length | Should -Be 150
    }
}

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
}
```

- [ ] Step 2: Run test to verify it fails

Run: `Invoke-Pester -Path "C:\Users\vadash\.claude\skills\auto-execute\tests\format.Tests.ps1" -Output Detailed 2>&1`
Expected: FAIL — `src/format.ps1` does not exist

- [ ] Step 3: Create `src/format.ps1` with the six formatting functions

Copy verbatim from `auto-execute-helpers.ps1`:

```powershell
# src/format.ps1 — Formatting and display

function Format-TaskLogEntry {
    param(
        [int]$TaskNumber,
        [bool]$Passed,
        [string]$CommitHash,
        [TimeSpan]$Duration,
        [string]$FailReason,
        [string]$TokenString = "",
        [int]$PeakContext = 0,
        [int]$ContextLimit = 0,
        [string]$ClaudeBin = "",
        [string]$FailSuffix = "STOPPED"
    )

    $timestamp = Get-Date -Format "HH:mm:ss"
    $durationStr = "{0}m {1:D2}s" -f [math]::Floor($Duration.TotalMinutes), $Duration.Seconds
    $ctxStr = ""
    if ($PeakContext -gt 0 -and $ContextLimit -gt 0) {
        $ctxStr = " | Peak ctx: $(Format-ContextSize $PeakContext)/$(Format-ContextSize $ContextLimit)"
    }

    $binTag = if ($ClaudeBin) { " [$ClaudeBin]" } else { "" }

    if ($Passed) {
        $shortHash = if ($CommitHash.Length -ge 7) { $CommitHash.Substring(0, 7) } else { $CommitHash }
        return "[$timestamp] Task ${TaskNumber}: PASS$binTag (commit $shortHash, $durationStr)$ctxStr$TokenString"
    } else {
        return "[$timestamp] Task ${TaskNumber}: FAIL$binTag ($FailReason) — $FailSuffix$ctxStr$TokenString"
    }
}

function Format-FinalReport {
    param(
        [string]$PlanPath,
        [int]$CompletedTasks,
        [int]$TotalTasks,
        [TimeSpan]$TotalDuration,
        [string]$StopReason,
        [string]$LogFile,
        [string]$TokenString = "",
        [int]$MaxPeakContext = 0,
        [int]$ContextLimit = 0,
        [int]$NextTask = 0
    )

    $durationStr = "{0}m {1:D2}s" -f [math]::Floor($TotalDuration.TotalMinutes), $TotalDuration.Seconds
    $ctxLine = ""
    if ($MaxPeakContext -gt 0 -and $ContextLimit -gt 0) {
        $ctxLine = "`nMax peak ctx: $(Format-ContextSize $MaxPeakContext)/$(Format-ContextSize $ContextLimit)"
    }

    $resumeHint = ""
    if ($StopReason -ne "All tasks complete" -and $NextTask -gt 0) {
        $resumeHint = "`n`nTo resume manually:`n  /executing-plans @$PlanPath do task $NextTask"
    }

    return @"
=== Auto-Execute Summary ===
Plan:       $PlanPath
Tasks:      $CompletedTasks/$TotalTasks completed
Duration:   $durationStr$TokenString$ctxLine
Stop reason: $StopReason
Logs:       $LogFile$resumeHint
"@
}

function Format-ContextSize {
    param(
        [int]$Tokens
    )

    if ($Tokens -ge 1000000) { return "{0:0.0}M" -f ($Tokens / 1000000) }
    if ($Tokens -ge 1000)    { return "{0:0.0}k" -f ($Tokens / 1000) }
    return [string]$Tokens
}

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

function Clear-LogDirectory {
    param(
        [string]$LogDir
    )

    if (-not (Test-Path $LogDir)) { return }

    Get-ChildItem -Path "$LogDir/*.log" -File -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path "$LogDir/*.log.err" -File -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path "$LogDir/task-*.md" -File -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
}
```

- [ ] Step 4: Run test to verify it passes

Run: `Invoke-Pester -Path "C:\Users\vadash\.claude\skills\auto-execute\tests\format.Tests.ps1" -Output Detailed 2>&1`
Expected: PASS — all 32 tests green

- [ ] Step 5: Commit

```bash
git add -A && git commit -m "feat: create src/format.ps1 and tests/format.Tests.ps1"
```

---

### Task 6: Create src/monitor.ps1 and tests/monitor.Tests.ps1

**Files:**
- Create: `src/monitor.ps1`
- Create: `tests/monitor.Tests.ps1`

This is an extraction — the `while (-not $exited)` monitoring loop from `auto-execute.ps1` becomes the `Invoke-TaskMonitor` function.

- [ ] Step 1: Write the failing test file

Create `tests/monitor.Tests.ps1`. Tests use a real short-lived process (`cmd /c exit 0`) with a pre-written stream-json log file. The function reads the log file during its monitoring loop and returns parsed results.

```powershell
# tests/monitor.Tests.ps1
BeforeAll {
    . "$PSScriptRoot/../src/stream.ps1"
    . "$PSScriptRoot/../src/format.ps1"
    . "$PSScriptRoot/../src/monitor.ps1"
}

Describe "Invoke-TaskMonitor" {
    BeforeEach {
        $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "pester-monitor-$(Get-Random)"
        New-Item -ItemType Directory -Path $script:tempDir -Force | Out-Null
    }

    AfterEach {
        Remove-Item -Path $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "returns correct hashtable keys" {
        $logPath = Join-Path $script:tempDir "task.log"
        "" | Set-Content $logPath -NoNewline

        $emptyStdin = Join-Path $script:tempDir "empty.txt"
        "" | Set-Content $emptyStdin -NoNewline

        $proc = Start-Process -FilePath "cmd" -ArgumentList "/c exit 0" -PassThru -NoNewWindow `
            -RedirectStandardInput $emptyStdin `
            -RedirectStandardOutput (Join-Path $script:tempDir "proc.out") `
            -RedirectStandardError (Join-Path $script:tempDir "proc.err")
        $proc.WaitForExit(5000) | Out-Null

        $result = Invoke-TaskMonitor -Process $proc -TaskLogPath $logPath `
            -TaskTimeout 10 -ContextLimit 100000 -MaxTurns 80 `
            -GitRoot "C:\fake" -TaskNumber 1

        $result.Keys | Should -Contain "ExitCode"
        $result.Keys | Should -Contain "Tokens"
        $result.Keys | Should -Contain "PeakContext"
        $result.Keys | Should -Contain "SessionId"
        $result.Keys | Should -Contain "Cancelled"
        $result.Keys | Should -Contain "StopReason"
        $result.Keys | Should -Contain "ErrorDetails"
    }

    It "captures exit code from completed process" {
        $logPath = Join-Path $script:tempDir "task.log"
        "" | Set-Content $logPath -NoNewline

        $emptyStdin = Join-Path $script:tempDir "empty.txt"
        "" | Set-Content $emptyStdin -NoNewline

        $proc = Start-Process -FilePath "cmd" -ArgumentList "/c exit 42" -PassThru -NoNewWindow `
            -RedirectStandardInput $emptyStdin `
            -RedirectStandardOutput (Join-Path $script:tempDir "proc.out") `
            -RedirectStandardError (Join-Path $script:tempDir "proc.err")
        $proc.WaitForExit(5000) | Out-Null

        $result = Invoke-TaskMonitor -Process $proc -TaskLogPath $logPath `
            -TaskTimeout 10 -ContextLimit 100000 -MaxTurns 80 `
            -GitRoot "C:\fake" -TaskNumber 1

        $result.ExitCode | Should -Be 42
        $result.Cancelled | Should -BeFalse
    }

    It "parses tokens from stream-json log file" {
        $logPath = Join-Path $script:tempDir "task.log"
        # Write stream-json with an assistant event and a result event
        $lines = @(
            '{"type":"system","subtype":"init","session_id":"test-session-123"}'
            '{"type":"assistant","message":{"usage":{"input_tokens":1000,"output_tokens":50,"cache_read_input_tokens":500,"cache_creation_input_tokens":200},"content":[{"type":"text","text":"working"}]}}'
            '{"type":"result","usage":{"input_tokens":2000,"output_tokens":100,"cache_read_input_tokens":1000,"cache_creation_input_tokens":400},"total_cost_usd":0.05}'
        )
        ($lines -join "`n") + "`n" | Set-Content $logPath -NoNewline

        $emptyStdin = Join-Path $script:tempDir "empty.txt"
        "" | Set-Content $emptyStdin -NoNewline

        $proc = Start-Process -FilePath "cmd" -ArgumentList "/c exit 0" -PassThru -NoNewWindow `
            -RedirectStandardInput $emptyStdin `
            -RedirectStandardOutput (Join-Path $script:tempDir "proc.out") `
            -RedirectStandardError (Join-Path $script:tempDir "proc.err")
        $proc.WaitForExit(5000) | Out-Null

        $result = Invoke-TaskMonitor -Process $proc -TaskLogPath $logPath `
            -TaskTimeout 10 -ContextLimit 100000 -MaxTurns 80 `
            -GitRoot "C:\fake" -TaskNumber 1

        # Result event overwrites accumulated tokens
        $result.Tokens.Input | Should -Be 2000
        $result.Tokens.Output | Should -Be 100
        $result.Tokens.CacheRead | Should -Be 1000
        $result.Tokens.CostUSD | Should -Be 0.05
        $result.Tokens.Total | Should -Be 3100
        $result.SessionId | Should -Be "test-session-123"
    }

    It "captures error_max_turns from result event" {
        $logPath = Join-Path $script:tempDir "task.log"
        $lines = @(
            '{"type":"system","subtype":"init","session_id":"s1"}'
            '{"type":"result","subtype":"error_max_turns","num_turns":75,"usage":{"input_tokens":500,"output_tokens":50,"cache_read_input_tokens":0,"cache_creation_input_tokens":0},"total_cost_usd":0.02}'
        )
        ($lines -join "`n") + "`n" | Set-Content $logPath -NoNewline

        $emptyStdin = Join-Path $script:tempDir "empty.txt"
        "" | Set-Content $emptyStdin -NoNewline

        $proc = Start-Process -FilePath "cmd" -ArgumentList "/c exit 1" -PassThru -NoNewWindow `
            -RedirectStandardInput $emptyStdin `
            -RedirectStandardOutput (Join-Path $script:tempDir "proc.out") `
            -RedirectStandardError (Join-Path $script:tempDir "proc.err")
        $proc.WaitForExit(5000) | Out-Null

        $result = Invoke-TaskMonitor -Process $proc -TaskLogPath $logPath `
            -TaskTimeout 10 -ContextLimit 100000 -MaxTurns 80 `
            -GitRoot "C:\fake" -TaskNumber 1

        $result.ErrorDetails | Should -Be "max turns exceeded (75/80)"
    }

    It "returns zero PeakContext when no transcript exists" {
        $logPath = Join-Path $script:tempDir "task.log"
        "" | Set-Content $logPath -NoNewline

        $emptyStdin = Join-Path $script:tempDir "empty.txt"
        "" | Set-Content $emptyStdin -NoNewline

        $proc = Start-Process -FilePath "cmd" -ArgumentList "/c exit 0" -PassThru -NoNewWindow `
            -RedirectStandardInput $emptyStdin `
            -RedirectStandardOutput (Join-Path $script:tempDir "proc.out") `
            -RedirectStandardError (Join-Path $script:tempDir "proc.err")
        $proc.WaitForExit(5000) | Out-Null

        $result = Invoke-TaskMonitor -Process $proc -TaskLogPath $logPath `
            -TaskTimeout 10 -ContextLimit 100000 -MaxTurns 80 `
            -GitRoot "C:\fake" -TaskNumber 1

        $result.PeakContext | Should -Be 0
    }

    It "finalizes token metrics with Total and HitRate" {
        $logPath = Join-Path $script:tempDir "task.log"
        $lines = @(
            '{"type":"assistant","message":{"usage":{"input_tokens":1000,"output_tokens":50,"cache_read_input_tokens":4000,"cache_creation_input_tokens":0},"content":[{"type":"text","text":"done"}]}}'
        )
        ($lines -join "`n") + "`n" | Set-Content $logPath -NoNewline

        $emptyStdin = Join-Path $script:tempDir "empty.txt"
        "" | Set-Content $emptyStdin -NoNewline

        $proc = Start-Process -FilePath "cmd" -ArgumentList "/c exit 0" -PassThru -NoNewWindow `
            -RedirectStandardInput $emptyStdin `
            -RedirectStandardOutput (Join-Path $script:tempDir "proc.out") `
            -RedirectStandardError (Join-Path $script:tempDir "proc.err")
        $proc.WaitForExit(5000) | Out-Null

        $result = Invoke-TaskMonitor -Process $proc -TaskLogPath $logPath `
            -TaskTimeout 10 -ContextLimit 100000 -MaxTurns 80 `
            -GitRoot "C:\fake" -TaskNumber 1

        # Total = Input + Output + CacheRead = 1000 + 50 + 4000 = 5050
        $result.Tokens.Total | Should -Be 5050
        # HitRate = CacheRead / (Input + CacheRead) * 100 = 4000/5000 * 100 = 80.0
        $result.Tokens.HitRate | Should -Be 80.0
    }
}
```

- [ ] Step 2: Run test to verify it fails

Run: `Invoke-Pester -Path "C:\Users\vadash\.claude\skills\auto-execute\tests\monitor.Tests.ps1" -Output Detailed 2>&1`
Expected: FAIL — `src/monitor.ps1` does not exist, BeforeAll fails

- [ ] Step 3: Create `src/monitor.ps1` with the `Invoke-TaskMonitor` function

This is extracted from the `while (-not $exited)` loop in `auto-execute.ps1` (lines inside the per-task block). The loop logic is identical; it is wrapped in a function with explicit parameters and a return hashtable.

```powershell
# src/monitor.ps1 — Task monitoring loop
# Depends on: src/stream.ps1 (Read-StreamJsonChunk, Get-TokensFromEvent, Get-CostFromEvent,
#             Get-ClaudeProjectHash, Get-TranscriptContextPeak)
#             src/format.ps1 (Format-ToolEvent, Format-ContextSize)

function Invoke-TaskMonitor {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$TaskLogPath,
        [int]$TaskTimeout,
        [int]$ContextLimit,
        [int]$MaxTurns,
        [string]$GitRoot,
        [int]$TaskNumber
    )

    $exited = $false
    $lastSize = 0
    $errLastSize = 0
    $buffer = ""
    $taskTokens = @{ Input=0; Output=0; CacheRead=0; CacheWrite=0; Total=0; HitRate=0; CostUSD=0 }
    $taskPeakContext = 0
    $taskSessionId = $null
    $transcriptOffset = 0
    $transcriptCheckCounter = 0
    $taskErrorDetails = $null
    $lastActivity = [System.Diagnostics.Stopwatch]::StartNew()
    $cancelled = $false
    $stopReason = $null
    $taskExitCode = $null

    while (-not $exited) {
        $exited = $Process.WaitForExit(200)

        # Check for user interrupt keys (Ctrl+C, Escape, Q)
        try {
            while ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                if (($key.Key -eq 'C' -and ($key.Modifiers -band [ConsoleModifiers]::Control)) -or
                    $key.Key -eq 'Escape' -or
                    ($key.Key -eq 'Q' -and $key.Modifiers -eq 0)) {
                    if (-not $Process.HasExited) {
                        & taskkill /F /T /PID $Process.Id 2>$null | Out-Null
                    }
                    $taskExitCode = 130
                    $exited = $true
                    $cancelled = $true
                    $stopReason = "Cancelled by user"
                    break
                }
            }
        } catch { }
        if ($exited -and $cancelled) { break }

        # Read new bytes from stdout (stream-json)
        if (Test-Path $TaskLogPath) {
            $stream = [System.IO.File]::Open($TaskLogPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            $reader = New-Object System.IO.StreamReader($stream)
            $null = $reader.BaseStream.Seek($lastSize, [System.IO.SeekOrigin]::Begin)
            $newContent = $reader.ReadToEnd()
            $lastSize = $reader.BaseStream.Position
            $reader.Close()

            if ($newContent) {
                $parsed = Read-StreamJsonChunk -Chunk $newContent -Buffer $buffer
                $buffer = $parsed.Buffer

                if ($parsed.Events.Count -gt 0) {
                    $lastActivity.Restart()
                }

                foreach ($event in $parsed.Events) {
                    # Capture session_id from init event for transcript reading
                    if ($event.type -eq "system" -and $event.subtype -eq "init" -and $event.session_id) {
                        $taskSessionId = $event.session_id
                    }

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

                    # Capture error details from result event (e.g., max turns exceeded)
                    if ($event.type -eq "result" -and $event.subtype -eq "error_max_turns") {
                        $turns = if ($event.num_turns) { $event.num_turns } else { "?" }
                        $taskErrorDetails = "max turns exceeded ($turns/$MaxTurns)"
                    }
                }
            }
        }

        # Transcript-based context tracking (every ~1s = 5 poll iterations)
        $transcriptCheckCounter++
        if ($taskSessionId -and $transcriptCheckCounter % 5 -eq 0) {
            $projectHash = Get-ClaudeProjectHash -DirPath $GitRoot
            $transcriptPath = Join-Path $env:USERPROFILE ".claude/projects/$projectHash/$taskSessionId.jsonl"
            $tResult = Get-TranscriptContextPeak -TranscriptPath $transcriptPath -StartOffset $transcriptOffset
            $transcriptOffset = $tResult.BytesRead
            if ($tResult.PeakContext -gt $taskPeakContext) {
                $taskPeakContext = $tResult.PeakContext
            }

            # Active Context Limit Enforcement
            if ($ContextLimit -gt 0 -and $taskPeakContext -gt $ContextLimit) {
                Write-Host "`n[CONTEXT LIMIT] Task $TaskNumber exceeded context limit: $(Format-ContextSize $taskPeakContext) > $(Format-ContextSize $ContextLimit)." -ForegroundColor Red
                & taskkill /F /T /PID $Process.Id 2>$null | Out-Null
                $taskExitCode = 2
                $exited = $true
                $stopReason = "Context limit exceeded ($taskPeakContext > $ContextLimit)"
                break
            }
        }

        # Tail stderr for fatal CLI errors
        $errPath = "$TaskLogPath.err"
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

        # Timeout check (activity-based: resets on stream-json events)
        if (-not $exited -and $lastActivity.Elapsed.TotalSeconds -gt $TaskTimeout) {
            Write-Host "`n[TIMEOUT] Task $TaskNumber idle for $TaskTimeout seconds." -ForegroundColor Red
            & taskkill /F /T /PID $Process.Id 2>$null | Out-Null
            $taskExitCode = 1
            $exited = $true
        }
    }

    # Final transcript read for most accurate peak context
    if ($taskSessionId) {
        $projectHash = Get-ClaudeProjectHash -DirPath $GitRoot
        $transcriptPath = Join-Path $env:USERPROFILE ".claude/projects/$projectHash/$taskSessionId.jsonl"
        $tResult = Get-TranscriptContextPeak -TranscriptPath $transcriptPath -StartOffset $transcriptOffset
        if ($tResult.PeakContext -gt $taskPeakContext) {
            $taskPeakContext = $tResult.PeakContext
        }
    }

    # Finalize token metrics
    $taskTokens.Total = $taskTokens.Input + $taskTokens.Output + $taskTokens.CacheRead
    $totalInput = $taskTokens.Input + $taskTokens.CacheRead
    if ($totalInput -gt 0) {
        $taskTokens.HitRate = [math]::Round(($taskTokens.CacheRead / $totalInput) * 100, 1)
    }

    if ($null -eq $taskExitCode) { $taskExitCode = $Process.ExitCode }

    return @{
        ExitCode     = $taskExitCode
        Tokens       = $taskTokens
        PeakContext  = $taskPeakContext
        SessionId    = $taskSessionId
        Cancelled    = $cancelled
        StopReason   = $stopReason
        ErrorDetails = $taskErrorDetails
    }
}
```

- [ ] Step 4: Run test to verify it passes

Run: `Invoke-Pester -Path "C:\Users\vadash\.claude\skills\auto-execute\tests\monitor.Tests.ps1" -Output Detailed 2>&1`
Expected: PASS — all 6 tests green

- [ ] Step 5: Commit

```bash
git add -A && git commit -m "feat: create src/monitor.ps1 and tests/monitor.Tests.ps1"
```

---

### Task 7: Update auto-execute.ps1 to use src/ modules

**Files:**
- Modify: `auto-execute.ps1`

Replace the dot-source of `auto-execute-helpers.ps1` with explicit dot-sources of `src/` modules. Replace the ~100-line monitoring `while` loop with a single `Invoke-TaskMonitor` call.

- [ ] Step 1: Run the existing new test suite to confirm baseline

Run: `Invoke-Pester -Path "C:\Users\vadash\.claude\skills\auto-execute\tests" -ExcludeTagFilter "skip" -Output Detailed 2>&1`
Expected: All tests pass (new module tests + old helpers tests + install + scaffolding)

- [ ] Step 2: Replace the dot-source line

In `auto-execute.ps1`, replace:

```powershell
# Dot-source helper functions
. "$PSScriptRoot/auto-execute-helpers.ps1"
```

With:

```powershell
# Dot-source modules
. "$PSScriptRoot/src/args.ps1"
. "$PSScriptRoot/src/plan.ps1"
. "$PSScriptRoot/src/preflight.ps1"
. "$PSScriptRoot/src/stream.ps1"
. "$PSScriptRoot/src/format.ps1"
. "$PSScriptRoot/src/monitor.ps1"
```

- [ ] Step 3: Replace the monitoring loop with `Invoke-TaskMonitor`

In `auto-execute.ps1`, find the block that starts with these variable declarations (after `$process = Start-Process ...`):

```powershell
        # Tail the log file with stream-json parsing
        $taskExitCode = $null
        $lastSize = 0
        $errLastSize = 0
        $exited = $false
        $buffer = ""
        $taskTokens = @{ Input=0; Output=0; CacheRead=0; CacheWrite=0; Total=0; HitRate=0; CostUSD=0 }
        $taskPeakContext = 0
        $taskSessionId = $null
        $transcriptOffset = 0
        $transcriptCheckCounter = 0
        $taskErrorDetails = $null  # Captures error info from result event (e.g., max turns)
```

…and continues through the `while (-not $exited)` loop…

…and continues through:

```powershell
        # Final transcript read for most accurate peak context
        ...
        # Finalize task token metrics
        ...
        if ($null -eq $taskExitCode) { $taskExitCode = $process.ExitCode }
```

Replace that entire block (from `# Tail the log file` through `$taskExitCode = $process.ExitCode`) with:

```powershell
        # Monitor the task process (stream-json parsing, keyboard, context, timeout)
        $monitorResult = Invoke-TaskMonitor -Process $process -TaskLogPath $taskLogPath `
            -TaskTimeout $TaskTimeout -ContextLimit $ContextLimit `
            -MaxTurns $MaxTurns -GitRoot $gitRoot -TaskNumber $currentTask

        $taskExitCode = $monitorResult.ExitCode
        $taskTokens = $monitorResult.Tokens
        $taskPeakContext = $monitorResult.PeakContext
        $taskSessionId = $monitorResult.SessionId
        $taskErrorDetails = $monitorResult.ErrorDetails
        $tokenStr = Format-TokenMetrics -Metrics $taskTokens
```

- [ ] Step 4: Update the cancellation check

Find the block:

```powershell
        # Check if run was cancelled (ReadKey handler or child SIGINT exit codes)
        if ($stopReason -match "^Cancelled" -or $taskExitCode -eq 130 -or $taskExitCode -eq 3221225786) {
```

Replace with:

```powershell
        # Check if run was cancelled
        if ($monitorResult.Cancelled -or $taskExitCode -eq 130 -or $taskExitCode -eq 3221225786) {
```

- [ ] Step 5: Update the context-limit stop reason check

Find the block inside the failure branch:

```powershell
            if ($stopReason -match "^Context limit") {
                $failReason = $stopReason
                $running = $false
```

Replace with:

```powershell
            if ($monitorResult.StopReason -match "^Context limit") {
                $failReason = $monitorResult.StopReason
                $running = $false
```

- [ ] Step 6: Update the retry guard

Find the line:

```powershell
            $canRetry = $BackupClaudeBin -and (-not $useBackup) -and
                        ($stopReason -notmatch "^Context limit")
```

Replace with:

```powershell
            $canRetry = $BackupClaudeBin -and (-not $useBackup) -and
                        ($monitorResult.StopReason -notmatch "^Context limit")
```

- [ ] Step 7: Remove now-unused `$lastActivity` initialization

Find and delete this line from the per-task setup block (it was only used inside the monitoring loop, now handled by `Invoke-TaskMonitor`):

```powershell
        $lastActivity = [System.Diagnostics.Stopwatch]::StartNew()
```

- [ ] Step 8: Run all new module tests

Run: `Invoke-Pester -Path "C:\Users\vadash\.claude\skills\auto-execute\tests\args.Tests.ps1","C:\Users\vadash\.claude\skills\auto-execute\tests\plan.Tests.ps1","C:\Users\vadash\.claude\skills\auto-execute\tests\preflight.Tests.ps1","C:\Users\vadash\.claude\skills\auto-execute\tests\stream.Tests.ps1","C:\Users\vadash\.claude\skills\auto-execute\tests\format.Tests.ps1","C:\Users\vadash\.claude\skills\auto-execute\tests\monitor.Tests.ps1","C:\Users\vadash\.claude\skills\auto-execute\tests\install.Tests.ps1","C:\Users\vadash\.claude\skills\auto-execute\tests\scaffolding.Tests.ps1" -Output Detailed 2>&1`
Expected: All tests PASS

- [ ] Step 9: Commit

```bash
git add -A && git commit -m "refactor: update auto-execute.ps1 to use src/ modules and Invoke-TaskMonitor"
```

---

### Task 8: Delete old files and update documentation

**Files:**
- Delete: `auto-execute-helpers.ps1`
- Delete: `tests/auto-execute-helpers.Tests.ps1`
- Modify: `CLAUDE.md`
- Modify: `README.md`

- [ ] Step 1: Delete the old helper files

```bash
git rm auto-execute-helpers.ps1 tests/auto-execute-helpers.Tests.ps1
```

- [ ] Step 2: Run tests to confirm nothing depends on deleted files

Run: `Invoke-Pester -Path "C:\Users\vadash\.claude\skills\auto-execute\tests" -Output Detailed 2>&1`
Expected: All tests PASS — no test file sources the deleted helpers file

- [ ] Step 3: Update CLAUDE.md Key Files section

Replace the existing Key Files section in `CLAUDE.md`:

```markdown
## Key Files

- `auto-execute.ps1` — main wrapper (parameters, process management, verification loop)
- `auto-execute-helpers.ps1` — pure functions (plan parsing via `Get-PlanTasks`, gap detection via `Get-TaskNumberGaps`, temp file creation via `Write-TaskTempFile`, token metrics, formatting)
- `SKILL.md` — Claude Code skill definition (headless task execution rules)
```

With:

```markdown
## Key Files

- `auto-execute.ps1` — main wrapper (parameters, dot-sources modules, process management, verification loop)
- `src/args.ps1` — CLI argument splitting (`Split-AxeArguments`)
- `src/plan.ps1` — plan parsing (`Get-PlanTasks`, `Get-TaskNumberGaps`, `Write-TaskTempFile`, `Resolve-PlanPath`)
- `src/preflight.ps1` — pre-flight checks (`Test-PreFlightEarly`, `Test-PreFlightLate`, `Test-TaskSuccess`, `Save-DirtyState`)
- `src/stream.ps1` — stream JSON parsing and transcript reading (6 functions)
- `src/format.ps1` — formatting and display (6 functions)
- `src/monitor.ps1` — task monitoring loop (`Invoke-TaskMonitor`; depends on stream + format)
- `SKILL.md` — Claude Code skill definition (headless task execution rules)
```

- [ ] Step 4: Update README.md file map and test commands

Replace the file map section in `README.md`:

```
## File map

```
~/.claude/skills/auto-execute/
  README.md                              # this file
  SKILL.md                               # Claude Code skill definition
  auto-execute.ps1                       # main wrapper script
  auto-execute.cmd                       # .cmd shim for PATH usage
  auto-execute-helpers.ps1               # pure helper functions
  install.ps1                            # one-time installer (adds to PATH)
  tests/
    scaffolding.Tests.ps1                # test infrastructure verification
    auto-execute-helpers.Tests.ps1       # helper function tests
    install.Tests.ps1                    # installer tests
  docs/
    designs/2026-03-13-auto-execute.md   # design document
    plans/2026-03-13-auto-execute.md     # implementation plan
```
```

With:

```
## File map

```
~/.claude/skills/auto-execute/
  README.md                              # this file
  SKILL.md                               # Claude Code skill definition
  auto-execute.ps1                       # thin orchestrator — dot-sources src/ modules
  auto-execute.cmd                       # .cmd shim for PATH usage
  install.ps1                            # one-time installer (adds to PATH)
  src/
    args.ps1                             # CLI argument splitting
    plan.ps1                             # plan parsing and resolution
    preflight.ps1                        # pre-flight checks and verification
    stream.ps1                           # stream JSON parsing and transcript reading
    format.ps1                           # formatting and display
    monitor.ps1                          # task monitoring loop (depends on stream + format)
  tests/
    args.Tests.ps1                       # mirrors src/args.ps1
    plan.Tests.ps1                       # mirrors src/plan.ps1
    preflight.Tests.ps1                  # mirrors src/preflight.ps1
    stream.Tests.ps1                     # mirrors src/stream.ps1
    format.Tests.ps1                     # mirrors src/format.ps1
    monitor.Tests.ps1                    # tests for Invoke-TaskMonitor
    scaffolding.Tests.ps1                # test infrastructure verification
    install.Tests.ps1                    # installer tests
  docs/
    designs/                             # design documents
    plans/                               # implementation plans
```
```

Also replace the test commands section:

```markdown
## Running tests

```powershell
# All tests
Invoke-Pester -Path "C:\Users\vadash\.claude\skills\auto-execute\tests" -Output Detailed

# Individual test files
Invoke-Pester -Path "C:\Users\vadash\.claude\skills\auto-execute\tests\auto-execute-helpers.Tests.ps1" -Output Detailed
```
```

With:

```markdown
## Running tests

```powershell
# All tests
Invoke-Pester -Path "C:\Users\vadash\.claude\skills\auto-execute\tests" -Output Detailed

# Individual module tests
Invoke-Pester -Path "C:\Users\vadash\.claude\skills\auto-execute\tests\plan.Tests.ps1" -Output Detailed
Invoke-Pester -Path "C:\Users\vadash\.claude\skills\auto-execute\tests\monitor.Tests.ps1" -Output Detailed
```
```

- [ ] Step 5: Commit

```bash
git add -A && git commit -m "refactor: delete old helpers, update CLAUDE.md and README.md"
```

---

### Task 9: Final verification

**Files:** None (verification only)

- [ ] Step 1: Run the full test suite

Run: `Invoke-Pester -Path "C:\Users\vadash\.claude\skills\auto-execute\tests" -Output Detailed 2>&1`
Expected: All tests PASS across all test files (args, plan, preflight, stream, format, monitor, scaffolding, install)

- [ ] Step 2: Verify old files are gone

Run: `test -f auto-execute-helpers.ps1 && echo "ERROR: old file still exists" || echo "OK: deleted"; test -f tests/auto-execute-helpers.Tests.ps1 && echo "ERROR: old test still exists" || echo "OK: deleted"`
Expected: Both files report "OK: deleted"

- [ ] Step 3: Verify all src/ modules exist

Run: `ls src/*.ps1`
Expected: `args.ps1  format.ps1  monitor.ps1  plan.ps1  preflight.ps1  stream.ps1`

- [ ] Step 4: Verify auto-execute.ps1 sources from src/

Run: `grep 'auto-execute-helpers' auto-execute.ps1; echo "exit: $?"`
Expected: No output, exit code 1 (no references to old file)

- [ ] Step 5: Commit (if any fixups were needed)

```bash
# Only if prior steps required changes:
git add -A && git commit -m "fix: address issues found in final verification"
```
