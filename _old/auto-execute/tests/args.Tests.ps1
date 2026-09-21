# tests/args.Tests.ps1
BeforeAll {
    . "$PSScriptRoot/../src/args.ps1"
}

Describe "Split-AxeArguments" {
    It "parses single claude binary and plan" {
        $result = Split-AxeArguments -Arguments @("claude_stable_ali", "mask-endpoint")
        $result.ClaudeBinaries.Count | Should -Be 1
        $result.ClaudeBinaries[0] | Should -Be "claude_stable_ali"
        $result.PlanInput | Should -Be "mask-endpoint"
        $result.StartTask | Should -Be 0
    }

    It "parses two claude binaries and plan" {
        $result = Split-AxeArguments -Arguments @("claude_stable_ali", "claude_stable_any", "mask-endpoint")
        $result.ClaudeBinaries.Count | Should -Be 2
        $result.ClaudeBinaries[0] | Should -Be "claude_stable_ali"
        $result.ClaudeBinaries[1] | Should -Be "claude_stable_any"
        $result.PlanInput | Should -Be "mask-endpoint"
        $result.StartTask | Should -Be 0
    }

    It "handles plan argument between claude binaries" {
        $result = Split-AxeArguments -Arguments @("claude_stable_ali", "mask-endpoint", "claude_stable_any")
        $result.ClaudeBinaries.Count | Should -Be 2
        $result.ClaudeBinaries[0] | Should -Be "claude_stable_ali"
        $result.ClaudeBinaries[1] | Should -Be "claude_stable_any"
        $result.PlanInput | Should -Be "mask-endpoint"
    }

    It "matches claude prefix case-insensitively" {
        $result = Split-AxeArguments -Arguments @("Claude_Stable", "my-plan")
        $result.ClaudeBinaries.Count | Should -Be 1
        $result.ClaudeBinaries[0] | Should -Be "Claude_Stable"
        $result.PlanInput | Should -Be "my-plan"
    }

    It "handles bare claude binary name" {
        $result = Split-AxeArguments -Arguments @("claude", "my-plan")
        $result.ClaudeBinaries.Count | Should -Be 1
        $result.ClaudeBinaries[0] | Should -Be "claude"
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

    It "throws when more than 1 non-claude argument is provided" {
        { Split-AxeArguments -Arguments @("claude_a", "plan1", "plan2") } |
            Should -Throw "*Too many non-claude arguments*"
    }

    It "parses bare numeric argument as StartTask" {
        $result = Split-AxeArguments -Arguments @("claude_stable_kimi", "claude_stable_glm", "latest", "12")
        $result.ClaudeBinaries.Count | Should -Be 2
        $result.ClaudeBinaries[0] | Should -Be "claude_stable_kimi"
        $result.ClaudeBinaries[1] | Should -Be "claude_stable_glm"
        $result.PlanInput | Should -Be "latest"
        $result.StartTask | Should -Be 12
    }

    It "parses --Start-task flag as StartTask" {
        $result = Split-AxeArguments -Arguments @("claude_stable_kimi", "claude_stable_glm", "latest", "--Start-task", "12")
        $result.ClaudeBinaries.Count | Should -Be 2
        $result.ClaudeBinaries[0] | Should -Be "claude_stable_kimi"
        $result.ClaudeBinaries[1] | Should -Be "claude_stable_glm"
        $result.PlanInput | Should -Be "latest"
        $result.StartTask | Should -Be 12
    }

    It "parses -StartTask flag as StartTask" {
        $result = Split-AxeArguments -Arguments @("claude_a", "my-plan", "-StartTask", "5")
        $result.ClaudeBinaries.Count | Should -Be 1
        $result.ClaudeBinaries[0] | Should -Be "claude_a"
        $result.PlanInput | Should -Be "my-plan"
        $result.StartTask | Should -Be 5
    }

    It "parses three claude binaries and plan" {
        $result = Split-AxeArguments -Arguments @("claude_a", "claude_b", "claude_c", "my-plan")
        $result.ClaudeBinaries.Count | Should -Be 3
        $result.ClaudeBinaries[0] | Should -Be "claude_a"
        $result.ClaudeBinaries[1] | Should -Be "claude_b"
        $result.ClaudeBinaries[2] | Should -Be "claude_c"
        $result.PlanInput | Should -Be "my-plan"
        $result.StartTask | Should -Be 0
    }

    It "parses five claude binaries and plan" {
        $result = Split-AxeArguments -Arguments @("claude_a", "claude_b", "claude_c", "claude_d", "claude_e", "my-plan")
        $result.ClaudeBinaries.Count | Should -Be 5
        $result.ClaudeBinaries[4] | Should -Be "claude_e"
        $result.PlanInput | Should -Be "my-plan"
    }

    It "throws when more than 5 claude binaries are provided" {
        { Split-AxeArguments -Arguments @("claude_a", "claude_b", "claude_c", "claude_d", "claude_e", "claude_f", "my-plan") } |
            Should -Throw "*max 5*"
    }
}