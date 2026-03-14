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