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
            -StopReason "Dirty tree (changes reset)" `
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