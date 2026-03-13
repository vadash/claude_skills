# CLI Convenience Implementation Plan

**Goal:** Make auto-execute callable as `auto-execute <partial-name> <claude-bin>` from any project directory.
**Architecture:** Add plan-name resolution logic to `auto-execute.ps1` (before pre-flight), create `install.ps1` for PATH setup. Resolution function lives in helpers for testability.
**Tech Stack:** PowerShell, Pester

---

### Task 1: Resolve-PlanPath helper function

**Files:**
- Modify: `auto-execute-helpers.ps1` (add function at the end)
- Test: `tests/auto-execute-helpers.Tests.ps1` (add describe block)

- [ ] Step 1: Write failing tests for Resolve-PlanPath

Add this Describe block at the end of `tests/auto-execute-helpers.Tests.ps1`:

```powershell
Describe "Resolve-PlanPath" {
    BeforeAll {
        # Create a temp directory structure mimicking a project
        $script:tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "axe-test-$(Get-Random)"
        $script:plansDir = Join-Path $script:tempRoot "docs/plans"
        New-Item -ItemType Directory -Path $script:plansDir -Force | Out-Null
        # Create sample plan files
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

- [ ] Step 2: Run tests to verify they fail

Run: `Invoke-Pester -Path tests/auto-execute-helpers.Tests.ps1 -Output Detailed`
Expected: 6 failures — `Resolve-PlanPath` is not defined.

- [ ] Step 3: Write Resolve-PlanPath implementation

Add this function at the end of `auto-execute-helpers.ps1`:

```powershell
function Resolve-PlanPath {
    param(
        [Parameter(Mandatory)]
        [string]$PlanInput,
        [string]$SearchDir = "docs/plans"
    )

    # If the input is an existing file, pass through unchanged
    if (Test-Path $PlanInput) {
        return $PlanInput
    }

    # Search for matching plan files
    if (Test-Path $SearchDir) {
        $candidates = Get-ChildItem -Path $SearchDir -Filter "*$PlanInput*.md" -File
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

- [ ] Step 4: Run tests to verify they pass

Run: `Invoke-Pester -Path tests/auto-execute-helpers.Tests.ps1 -Output Detailed`
Expected: All tests PASS.

- [ ] Step 5: Commit

```bash
git add -A && git commit -m "feat: add Resolve-PlanPath helper for partial plan name resolution"
```

---

### Task 2: Wire resolution into auto-execute.ps1

**Files:**
- Modify: `auto-execute.ps1` (param block + resolution block before Phase 1a)

- [ ] Step 1: Make Plan and ClaudeBin positional

In `auto-execute.ps1`, replace the param block (lines 5-13):

```powershell
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
```

with:

```powershell
param(
    [Parameter(Mandatory, Position=0)] [string] $Plan,
    [Parameter(Position=1)] [string] $ClaudeBin = "claude",
    [int]    $MaxTurns     = 40,
    [int]    $TaskTimeout  = 900,
    [int]    $ContextLimit = 70000,
    [int]    $MaxFailures  = 2,
    [int]    $StartTask    = 0,
    [string] $LogDir       = "logs/auto-execute"
)
```

- [ ] Step 2: Add resolution block between dot-source and Phase 1a

Insert this block right after the line `. "$PSScriptRoot/auto-execute-helpers.ps1"` and before `# --- Phase 1a: Pre-flight (before hooks) ---`:

```powershell
# --- Phase 0: Resolve plan path ---
$Plan = Resolve-PlanPath -PlanInput $Plan
```

That's it — one line. The helper function handles all the logic.

- [ ] Step 3: Run full test suite to verify nothing is broken

Run: `Invoke-Pester -Path tests/ -Output Detailed`
Expected: All existing tests still PASS. (The param changes don't affect helper tests since they test functions directly, not the script's param block.)

- [ ] Step 4: Commit

```bash
git add -A && git commit -m "feat: positional params and plan name resolution in auto-execute.ps1"
```

---

### Task 3: install.ps1

**Files:**
- Create: `install.ps1`
- Create: `tests/install.Tests.ps1`

- [ ] Step 1: Write failing tests for install logic

Create `tests/install.Tests.ps1`:

```powershell
BeforeAll {
    # We test the install functions by dot-sourcing install.ps1 with a guard
    # Since install.ps1 runs on source, we test its effects via helper functions.
    # For testability, we extract the core logic into functions.
}

Describe "install.ps1" {
    BeforeAll {
        $script:skillDir = (Resolve-Path "$PSScriptRoot/..").Path
        $script:cmdShim = Join-Path $script:skillDir "auto-execute.cmd"
    }

    AfterAll {
        # Clean up generated shim if test created it
        if (Test-Path $script:cmdShim) {
            Remove-Item $script:cmdShim -Force -ErrorAction SilentlyContinue
        }
    }

    It "creates auto-execute.cmd shim" {
        # Run install.ps1 in a child process so it doesn't modify our PATH
        $output = powershell -NoProfile -Command "& '$script:skillDir/install.ps1' 2>&1"
        Test-Path $script:cmdShim | Should -BeTrue
    }

    It "shim content calls auto-execute.ps1 with pass-through args" {
        $content = Get-Content $script:cmdShim -Raw
        $content | Should -BeLike "*auto-execute.ps1*%**"
    }

    It "is idempotent — running twice does not error" {
        $output1 = powershell -NoProfile -Command "& '$script:skillDir/install.ps1' 2>&1"
        $output2 = powershell -NoProfile -Command "& '$script:skillDir/install.ps1' 2>&1"
        $LASTEXITCODE | Should -Be 0
    }
}
```

- [ ] Step 2: Run tests to verify they fail

Run: `Invoke-Pester -Path tests/install.Tests.ps1 -Output Detailed`
Expected: Failures — `install.ps1` does not exist yet.

- [ ] Step 3: Write install.ps1

Create `install.ps1` in the skill root (`auto-execute/install.ps1`):

```powershell
# install.ps1 — One-time setup to make auto-execute callable from anywhere.
# Adds the skill directory to user PATH and creates a .cmd shim.

$skillDir = $PSScriptRoot

# --- Create .cmd shim for cmd.exe compatibility ---
$cmdShim = Join-Path $skillDir "auto-execute.cmd"
if (-not (Test-Path $cmdShim)) {
    @"
@echo off
powershell -NoProfile -File "%~dp0auto-execute.ps1" %*
"@ | Out-File -FilePath $cmdShim -Encoding ASCII
    Write-Host "Created $cmdShim" -ForegroundColor Green
} else {
    Write-Host "Shim already exists: $cmdShim" -ForegroundColor DarkGray
}

# --- Add to user PATH ---
$userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($userPath -split ";" | Where-Object { $_ -eq $skillDir }) {
    Write-Host "Already in PATH: $skillDir" -ForegroundColor DarkGray
} else {
    $newPath = "$userPath;$skillDir"
    [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
    Write-Host "Added to user PATH: $skillDir" -ForegroundColor Green
    Write-Host "Restart your terminal for PATH changes to take effect." -ForegroundColor Yellow
}
```

- [ ] Step 4: Run tests to verify they pass

Run: `Invoke-Pester -Path tests/install.Tests.ps1 -Output Detailed`
Expected: All 3 tests PASS.

- [ ] Step 5: Run full test suite

Run: `Invoke-Pester -Path tests/ -Output Detailed`
Expected: All tests PASS.

- [ ] Step 6: Commit

```bash
git add -A && git commit -m "feat: add install.ps1 for PATH setup and cmd shim"
```

---

### Task 4: Update documentation

**Files:**
- Modify: `CLAUDE.md` (add install/usage info)
- Modify: `README.md` (if it exists and has usage info)

- [ ] Step 1: Update CLAUDE.md running section

In `CLAUDE.md`, update the `## Running` section to include the new calling conventions:

```markdown
## Running

```powershell
# One-time install (adds to PATH, creates .cmd shim)
.\install.ps1

# Execute from any project directory (partial name match)
auto-execute 2026-03-13-markdown-link-checker claude_stable_ali

# With default claude binary
auto-execute markdown-link

# Old explicit form still works
& "path/to/auto-execute.ps1" -Plan "docs/plans/my-plan.md"

# Run tests
Invoke-Pester -Path tests/ -Output Detailed
```
```

- [ ] Step 2: Commit

```bash
git add -A && git commit -m "docs: update CLAUDE.md with CLI convenience usage"
```
