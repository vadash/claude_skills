# tests/args.Tests.ps1
BeforeAll {
    . "$PSScriptRoot/../src/args.ps1"
}

Describe "Split-AxeArguments" {
    It "parses single claude binary and plan" {
        $result = Split-AxeArguments -Arguments @("claude_stable_ali", "mask-endpoint")
        $result.MainClaude | Should -Be "claude_stable_ali"
        $result.BackupClaude | Should -BeNull
        $result.PlanInput | Should -Be "mask-endpoint"
        $result.StartTask | Should -Be 0
    }

    It "parses two claude binaries and plan" {
        $result = Split-AxeArguments -Arguments @("claude_stable_ali", "claude_stable_any", "mask-endpoint")
        $result.MainClaude | Should -Be "claude_stable_ali"
        $result.BackupClaude | Should -Be "claude_stable_any"
        $result.PlanInput | Should -Be "mask-endpoint"
        $result.StartTask | Should -Be 0
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

    It "parses bare numeric argument as StartTask" {
        $result = Split-AxeArguments -Arguments @("claude_stable_kimi", "claude_stable_glm", "latest", "12")
        $result.MainClaude | Should -Be "claude_stable_kimi"
        $result.BackupClaude | Should -Be "claude_stable_glm"
        $result.PlanInput | Should -Be "latest"
        $result.StartTask | Should -Be 12
    }

    It "parses --Start-task flag as StartTask" {
        $result = Split-AxeArguments -Arguments @("claude_stable_kimi", "claude_stable_glm", "latest", "--Start-task", "12")
        $result.MainClaude | Should -Be "claude_stable_kimi"
        $result.BackupClaude | Should -Be "claude_stable_glm"
        $result.PlanInput | Should -Be "latest"
        $result.StartTask | Should -Be 12
    }

    It "parses -StartTask flag as StartTask" {
        $result = Split-AxeArguments -Arguments @("claude_a", "my-plan", "-StartTask", "5")
        $result.MainClaude | Should -Be "claude_a"
        $result.PlanInput | Should -Be "my-plan"
        $result.StartTask | Should -Be 5
    }
}