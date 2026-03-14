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