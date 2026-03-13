BeforeAll {
    . "$PSScriptRoot/../.claude/hooks/axe-context-check.ps1"
}

Describe "Test-ContextLimit" {
    It "returns ExitCode 0 when AXE_ACTIVE is not 'true'" {
        $result = Test-ContextLimit -RawInput '{}' -AxeActive '' -ContextLimitValue ''
        $result.ExitCode | Should -Be 0
    }

    It "returns ExitCode 0 when AXE_ACTIVE is unset (null)" {
        $result = Test-ContextLimit -RawInput '{}' -AxeActive $null -ContextLimitValue ''
        $result.ExitCode | Should -Be 0
    }

    It "returns ExitCode 0 when transcript_path is missing from input" {
        $result = Test-ContextLimit -RawInput '{"tool": "Bash"}' -AxeActive 'true' -ContextLimitValue '70000'
        $result.ExitCode | Should -Be 0
    }

    It "returns ExitCode 0 when transcript file does not exist" {
        $json = @{ transcript_path = "C:/nonexistent/path/transcript.jsonl" } | ConvertTo-Json
        $result = Test-ContextLimit -RawInput $json -AxeActive 'true' -ContextLimitValue '70000'
        $result.ExitCode | Should -Be 0
    }

    It "returns ExitCode 0 when transcript file is small (under limit)" {
        $tempFile = [System.IO.FileInfo]([System.IO.Path]::GetTempFileName())
        try {
            # 100 bytes -> ~25 tokens, well under 70000
            Set-Content -Path $tempFile.FullName -Value ("x" * 100) -NoNewline
            $json = @{ transcript_path = $tempFile.FullName } | ConvertTo-Json

            $result = Test-ContextLimit -RawInput $json -AxeActive 'true' -ContextLimitValue '70000'
            $result.ExitCode | Should -Be 0
        } finally {
            Remove-Item $tempFile.FullName -ErrorAction SilentlyContinue
        }
    }

    It "returns ExitCode 2 with message when transcript exceeds limit" {
        $tempFile = [System.IO.FileInfo]([System.IO.Path]::GetTempFileName())
        try {
            # 400000 bytes -> ~100000 tokens, over 70000
            [System.IO.File]::WriteAllText($tempFile.FullName, ("x" * 400000))
            $json = @{ transcript_path = $tempFile.FullName } | ConvertTo-Json

            $result = Test-ContextLimit -RawInput $json -AxeActive 'true' -ContextLimitValue '70000'
            $result.ExitCode | Should -Be 2
            $result.Message | Should -Match 'CONTEXT LIMIT EXCEEDED'
            $result.Message | Should -Match 'DO NOT RETRY'
        } finally {
            Remove-Item $tempFile.FullName -ErrorAction SilentlyContinue
        }
    }

    It "uses custom limit from ContextLimitValue parameter" {
        $tempFile = [System.IO.FileInfo]([System.IO.Path]::GetTempFileName())
        try {
            # 100 bytes -> ~25 tokens, over a limit of 10
            Set-Content -Path $tempFile.FullName -Value ("x" * 100) -NoNewline
            $json = @{ transcript_path = $tempFile.FullName } | ConvertTo-Json

            $result = Test-ContextLimit -RawInput $json -AxeActive 'true' -ContextLimitValue '10'
            $result.ExitCode | Should -Be 2
        } finally {
            Remove-Item $tempFile.FullName -ErrorAction SilentlyContinue
        }
    }

    It "defaults to 70000 when ContextLimitValue is empty" {
        $tempFile = [System.IO.FileInfo]([System.IO.Path]::GetTempFileName())
        try {
            Set-Content -Path $tempFile.FullName -Value ("x" * 100) -NoNewline
            $json = @{ transcript_path = $tempFile.FullName } | ConvertTo-Json

            $result = Test-ContextLimit -RawInput $json -AxeActive 'true' -ContextLimitValue ''
            $result.ExitCode | Should -Be 0
        } finally {
            Remove-Item $tempFile.FullName -ErrorAction SilentlyContinue
        }
    }

    It "returns ExitCode 0 when input JSON is invalid" {
        $result = Test-ContextLimit -RawInput 'not valid json {{' -AxeActive 'true' -ContextLimitValue '70000'
        $result.ExitCode | Should -Be 0
    }
}
