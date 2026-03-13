BeforeAll {
    . "$PSScriptRoot/../.claude/hooks/axe-loop-detect.ps1"
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
