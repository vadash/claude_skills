# src/preflight.ps1 — Pre-flight checks and verification

function Test-PreFlightEarly {
    param(
        [string]$ClaudeBin,
        [string]$PlanPath
    )

    $errors = @()

    if (-not (Get-Command $ClaudeBin -ErrorAction SilentlyContinue)) {
        $errors += "CLI binary '$ClaudeBin' not found in PATH."
    }

    if (-not (Test-Path $PlanPath)) {
        $errors += "Plan file '$PlanPath' not found."
    }

    $null = git rev-parse --git-dir 2>&1
    if ($LASTEXITCODE -ne 0) {
        $errors += "Not inside a git repository."
    }

    $status = git status --porcelain 2>&1
    if ($status) {
        $errors += "Git working tree is not clean."
    }

    return $errors
}

function Test-PreFlightLate {
    param(
        [string]$PlanPath,
        [string]$LogDir
    )

    $errors = @()

    if (-not (Test-Path $LogDir)) {
        try {
            New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
        } catch {
            $errors += "Cannot create log directory '$LogDir': $_"
        }
    }

    return $errors
}

function Test-TaskSuccess {
    param(
        [int]$ExitCode,
        [string]$BeforeHash,
        [string]$AfterHash,
        [string]$GitStatus
    )

    $signals = @{
        ExitOk    = ($ExitCode -eq 0)
        NewCommit = ($AfterHash -ne $BeforeHash)
        CleanTree = ([string]::IsNullOrWhiteSpace($GitStatus))
    }

    $signals.AllPassed = $signals.ExitOk -and $signals.NewCommit -and $signals.CleanTree

    return $signals
}

function Save-DirtyState {
    param(
        [int]$TaskNumber
    )

    git reset --hard HEAD 2>&1
    git clean -fd 2>&1
    return $LASTEXITCODE -eq 0
}

function Invoke-TreeCleanup {
    param(
        [bool]$NewCommit,
        [bool]$CleanTree,
        [string]$GitStatus,
        [int]$TaskNumber
    )

    # Nothing to clean
    if ($CleanTree) {
        return @{ Action = "NONE"; Message = "Tree clean" }
    }

    # Success with debris: Task committed but left temp files
    # Safe to clean - the real work is in git history
    if ($NewCommit) {
        # git clean -fd only removes untracked files (safe)
        # -f = force, -d = include directories
        $output = git clean -fd 2>&1
        if ($LASTEXITCODE -eq 0) {
            return @{
                Action = "CLEANED"
                Message = "Removed untracked debris after successful commit"
                Details = $output
            }
        }
        return @{
            Action = "CLEAN_FAILED"
            Message = "git clean failed: $output"
        }
    }

    # Failure with debris: Task failed, messy working tree
    # Need hard reset to get back to known good state
    # Reset to HEAD (discards tracked changes)
    $resetOutput = git reset --hard HEAD 2>&1
    $resetOk = $LASTEXITCODE -eq 0

    # Also clean untracked (in case reset left any)
    $cleanOutput = git clean -fd 2>&1
    $cleanOk = $LASTEXITCODE -eq 0

    if ($resetOk -and $cleanOk) {
        return @{
            Action = "RESET"
            Message = "Hard reset to HEAD after failed task"
            Details = "$resetOutput; $cleanOutput"
        }
    }
    return @{
        Action = "RESET_FAILED"
        Message = "Reset failed. Reset: $resetOutput; Clean: $cleanOutput"
    }
}