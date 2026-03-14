BeforeAll {
    . "$PSScriptRoot/../auto-execute-helpers.ps1"
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
        # [TOOL] Bash | = 14 chars, then 147 + ... = 150
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
        # Peak = 538 + 17117 = 17655
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

        # Write first line
        "$line1`n" | Set-Content $transcriptPath -NoNewline
        $result1 = Get-TranscriptContextPeak -TranscriptPath $transcriptPath
        $result1.PeakContext | Should -Be 5100   # 100 + 5000
        $offset = $result1.BytesRead

        # Append second line
        [System.IO.File]::AppendAllText($transcriptPath, "$line2`n")
        $result2 = Get-TranscriptContextPeak -TranscriptPath $transcriptPath -StartOffset $offset
        $result2.PeakContext | Should -Be 10200  # 200 + 10000

        # First read's peak is not seen again
        $result2.BytesRead | Should -BeGreaterThan $offset
    }

    It "includes cache_creation_input_tokens in context size" {
        $transcriptPath = Join-Path $script:tempDir "cache-create.jsonl"
        $line = '{"type":"assistant","message":{"usage":{"input_tokens":300,"cache_creation_input_tokens":5000,"cache_read_input_tokens":2000,"output_tokens":50}}}'
        $line | Set-Content $transcriptPath -NoNewline

        $result = Get-TranscriptContextPeak -TranscriptPath $transcriptPath
        # 300 + 5000 + 2000 = 7300
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
        $result.PeakContext | Should -Be 8100  # 100 + 8000
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
        $result.PeakContext | Should -Be 3500  # 500 + 3000
    }
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
