# src/args.ps1 — CLI argument parsing

function Split-AxeArguments {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $claudeBinaries = @()
    $otherArgs = @()

    foreach ($arg in $Arguments) {
        if ($arg -match '^claude') {
            $claudeBinaries += $arg
        } else {
            $otherArgs += $arg
        }
    }

    if ($claudeBinaries.Count -eq 0) {
        throw "No claude binary specified. At least one argument must start with 'claude'."
    }
    if ($claudeBinaries.Count -gt 2) {
        throw "Too many claude binaries specified (max 2). Got: $($claudeBinaries -join ', ')"
    }
    if ($otherArgs.Count -eq 0) {
        throw "No plan argument found. One non-claude argument is required."
    }
    if ($otherArgs.Count -gt 1) {
        throw "Too many non-claude arguments (max 1). Got: $($otherArgs -join ', ')"
    }

    return @{
        MainClaude   = $claudeBinaries[0]
        BackupClaude = if ($claudeBinaries.Count -gt 1) { $claudeBinaries[1] } else { $null }
        PlanInput    = $otherArgs[0]
    }
}