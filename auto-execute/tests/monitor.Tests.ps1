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