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
}

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
