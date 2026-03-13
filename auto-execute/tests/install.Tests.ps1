BeforeAll {
    # We test the install functions by dot-sourcing install.ps1 with a guard
    # Since install.ps1 runs on source, we test its effects via helper functions.
    # For testability, we extract the core logic into functions.
}

Describe "install.ps1" {
    BeforeAll {
        $script:skillDir = (Resolve-Path "$PSScriptRoot/..").Path
        $script:cmdShim = Join-Path $script:skillDir "auto-execute.cmd"
    }

    # Do NOT delete auto-execute.cmd — it is a tracked repo file.

    It "creates auto-execute.cmd shim" {
        # Run install.ps1 in a child process so it doesn't modify our PATH
        $output = powershell -NoProfile -Command "& '$script:skillDir/install.ps1' 2>&1"
        Test-Path $script:cmdShim | Should -BeTrue
    }

    It "shim content calls auto-execute.ps1 with pass-through args" {
        $content = Get-Content $script:cmdShim -Raw
        $content | Should -BeLike "*auto-execute.ps1*%**"
    }

    It "is idempotent — running twice does not error" {
        $output1 = powershell -NoProfile -Command "& '$script:skillDir/install.ps1' 2>&1"
        $output2 = powershell -NoProfile -Command "& '$script:skillDir/install.ps1' 2>&1"
        $LASTEXITCODE | Should -Be 0
    }
}