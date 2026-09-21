# tests/preflight.Tests.ps1
BeforeAll {
    . "$PSScriptRoot/../src/preflight.ps1"
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

Describe "Invoke-TreeCleanup" {
    It "Returns NONE when tree is clean" {
        $result = Invoke-TreeCleanup -NewCommit $true -CleanTree $true -GitStatus "" -TaskNumber 1
        $result.Action | Should -Be "NONE"
        $result.Message | Should -Be "Tree clean"
    }

    It "Cleans debris and restores tracked files after successful commit (NewCommit=true, CleanTree=false)" {
        Mock git {
            if ($args[0] -eq 'clean') {
                return "Removing backup.txt"
            }
            if ($args[0] -eq 'checkout') {
                return ""
            }
        }

        $result = Invoke-TreeCleanup -NewCommit $true -CleanTree $false -GitStatus "?? backup.txt" -TaskNumber 1

        $result.Action | Should -Be "CLEANED"
        $result.Message | Should -Be "Cleaned debris and restored tracked files after successful commit"
        $result.Details | Should -Match "clean: Removing backup.txt"
    }

    It "Resets after failed task with debris (NewCommit=false, CleanTree=false)" {
        Mock git {
            if ($args[0] -eq 'reset') {
                return "HEAD is now at abc1234"
            }
            if ($args[0] -eq 'clean') {
                return ""
            }
        }

        $result = Invoke-TreeCleanup -NewCommit $false -CleanTree $false -GitStatus "M file.txt" -TaskNumber 1

        $result.Action | Should -Be "RESET"
        $result.Message | Should -Be "Hard reset to HEAD after failed task"
    }

    It "Reports CLEAN_FAILED when git clean fails" {
        Mock git {
            if ($args[0] -eq 'clean') {
                $global:LASTEXITCODE = 1
                return "fatal: not a git repository"
            }
            if ($args[0] -eq 'checkout') {
                $global:LASTEXITCODE = 0
                return ""
            }
        }

        $result = Invoke-TreeCleanup -NewCommit $true -CleanTree $false -GitStatus "?? backup.txt" -TaskNumber 1

        $result.Action | Should -Be "CLEAN_FAILED"
        $result.Message | Should -Match "Cleanup failed"
    }

    It "Reports RESET_FAILED when git reset fails" {
        Mock git {
            if ($args[0] -eq 'reset') {
                $global:LASTEXITCODE = 1
                return "fatal: ambiguous argument 'HEAD'"
            }
            if ($args[0] -eq 'clean') {
                $global:LASTEXITCODE = 0
                return ""
            }
        }

        $result = Invoke-TreeCleanup -NewCommit $false -CleanTree $false -GitStatus "M file.txt" -TaskNumber 1

        $result.Action | Should -Be "RESET_FAILED"
        $result.Message | Should -Match "Reset failed"
    }

    Context "Decision Matrix" {
        It "ExitOk=true, NewCommit=true, CleanTree=false => CLEANED" {
            Mock git {
                if ($args[0] -eq 'clean') { return "Removing backup.txt" }
                if ($args[0] -eq 'checkout') { return "" }
            }

            $result = Invoke-TreeCleanup -NewCommit $true -CleanTree $false -GitStatus "?? backup.txt" -TaskNumber 1
            $result.Action | Should -Be "CLEANED"
        }

        It "ExitOk=false, NewCommit=true, CleanTree=false => CLEANED (exit code ignored if commit exists)" {
            Mock git {
                if ($args[0] -eq 'clean') { return "Removing backup.txt" }
                if ($args[0] -eq 'checkout') { return "" }
            }

            $result = Invoke-TreeCleanup -NewCommit $true -CleanTree $false -GitStatus "?? backup.txt" -TaskNumber 1
            $result.Action | Should -Be "CLEANED"
        }

        It "ExitOk=true, NewCommit=false, CleanTree=false => RESET (dirty tree, no commit)" {
            Mock git {
                if ($args[0] -eq 'reset') { return "HEAD is now at abc1234" }
                if ($args[0] -eq 'clean') { return "" }
            }

            $result = Invoke-TreeCleanup -NewCommit $false -CleanTree $false -GitStatus "M file.txt" -TaskNumber 1
            $result.Action | Should -Be "RESET"
        }

        It "ExitOk=false, NewCommit=false, CleanTree=false => RESET (total failure)" {
            Mock git {
                if ($args[0] -eq 'reset') { return "HEAD is now at abc1234" }
                if ($args[0] -eq 'clean') { return "" }
            }

            $result = Invoke-TreeCleanup -NewCommit $false -CleanTree $false -GitStatus "M file.txt" -TaskNumber 1
            $result.Action | Should -Be "RESET"
        }

        It "ExitOk=true, NewCommit=false, CleanTree=true => NONE (clean no-op)" {
            $result = Invoke-TreeCleanup -NewCommit $false -CleanTree $true -GitStatus "" -TaskNumber 1
            $result.Action | Should -Be "NONE"
        }
    }
}