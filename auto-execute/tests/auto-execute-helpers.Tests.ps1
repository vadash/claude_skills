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
        $script:tempPlan = [System.IO.FileInfo]([System.IO.Path]::GetTempFileName())
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
