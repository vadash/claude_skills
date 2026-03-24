# src/plan.ps1 — Plan parsing and resolution

function Get-PlanTasks {
    param(
        [Parameter(Mandatory)]
        [string]$PlanContent
    )

    $taskPattern = '(?mi)^#{2,3}\s*Task\s+(\d+)'
    $taskMatches = [regex]::Matches($PlanContent, $taskPattern)

    if ($taskMatches.Count -eq 0) {
        return @{ Preamble = $PlanContent; Tasks = @() }
    }

    $firstIndex = $taskMatches[0].Index
    $preamble = if ($firstIndex -gt 0) {
        $PlanContent.Substring(0, $firstIndex).TrimEnd()
    } else { "" }

    $tasks = @()
    for ($i = 0; $i -lt $taskMatches.Count; $i++) {
        $number = [int]$taskMatches[$i].Groups[1].Value
        $startIndex = $taskMatches[$i].Index
        $endIndex = if ($i + 1 -lt $taskMatches.Count) {
            $taskMatches[$i + 1].Index
        } else {
            $PlanContent.Length
        }
        $content = $PlanContent.Substring($startIndex, $endIndex - $startIndex).TrimEnd()
        $tasks += @{ Number = $number; Content = $content }
    }

    return @{ Preamble = $preamble; Tasks = $tasks }
}

function Get-TaskNumberGaps {
    param(
        [Parameter()]
        [int[]]$TaskNumbers
    )

    if (-not $TaskNumbers -or $TaskNumbers.Count -eq 0) { return @() }

    $sorted = $TaskNumbers | Sort-Object
    $max = $sorted[-1]
    $expected = 1..$max
    $missing = @($expected | Where-Object { $_ -notin $sorted })
    return $missing
}

function Write-TaskTempFile {
    param(
        [Parameter(Mandatory)]
        [string]$LogDir,
        [Parameter(Mandatory)]
        [int]$TaskNumber,
        [Parameter(Mandatory)]
        [string]$TaskContent,
        [string]$Preamble = "",
        [Parameter(Mandatory)]
        [string]$PlanPath,
        [switch]$UseFullPlan,
        [string]$FullPlanContent = ""
    )

    $tempPath = Join-Path $LogDir "task-$TaskNumber.md"

    if ($UseFullPlan -and $FullPlanContent) {
        # On retry (2nd+ attempt), feed the full plan for broader context
        $parts = @()
        $parts += "# Full Plan (retry mode)"
        $parts += ""
        $parts += "This is attempt 2+ for task $TaskNumber. The full plan is provided for broader context."
        $parts += ""
        $parts += "---"
        $parts += ""
        $parts += $FullPlanContent
        ($parts -join "`n") | Set-Content -Path $tempPath -Encoding UTF8 -NoNewline
    } else {
        # Default: single task with preamble reference
        $parts = @()
        if ($Preamble) {
            $parts += $Preamble
            $parts += ""
            $parts += "---"
            $parts += ""
        }
        $parts += $TaskContent
        $parts += ""
        $parts += "---"
        $parts += "Full plan: $PlanPath"
        $parts += "If this task references other tasks or you need broader context, read the full plan above."
        ($parts -join "`n") | Set-Content -Path $tempPath -Encoding UTF8 -NoNewline
    }

    return $tempPath
}

function Resolve-PlanPath {
    param(
        [Parameter(Mandatory)]
        [string]$PlanInput,
        [string]$SearchDir = "docs/plans"
    )

    # "latest" keyword — find most recently committed plan in git history
    if ($PlanInput -eq 'latest') {
        if (-not (Test-Path $SearchDir)) {
            throw "Plan directory '$SearchDir' does not exist."
        }
        $planFiles = @(Get-ChildItem -Path $SearchDir -Filter "*.md" -File)
        if ($planFiles.Count -eq 0) {
            throw "No plan files found in '$SearchDir'."
        }
        $gitOutput = git log -1 --pretty=format:'' --name-only --diff-filter=ACMR -- "$SearchDir/*.md" 2>&1
        $relativePath = ($gitOutput | Where-Object { $_ -match '\.md$' } | Select-Object -First 1)
        if (-not $relativePath) {
            throw "No plan files found in git history under '$SearchDir'."
        }
        $gitRoot = (git rev-parse --show-toplevel 2>&1).ToString().Trim()
        $fullPath = Join-Path $gitRoot $relativePath
        if (-not (Test-Path $fullPath)) {
            throw "Latest plan '$relativePath' found in git history but file no longer exists."
        }
        return $fullPath
    }

    if (Test-Path $PlanInput) {
        return $PlanInput
    }

    if (Test-Path $SearchDir) {
        $fileName = Split-Path -Leaf $PlanInput

        if ($fileName -like "*.md") {
            $candidates = Get-ChildItem -Path $SearchDir -Filter "*$fileName" -File
        } else {
            $candidates = Get-ChildItem -Path $SearchDir -Filter "*$fileName*.md" -File
        }
    } else {
        $candidates = @()
    }

    if ($candidates.Count -eq 1) {
        return $candidates[0].FullName
    }

    if ($candidates.Count -gt 1) {
        $names = ($candidates | ForEach-Object { $_.Name }) -join ", "
        throw "Ambiguous plan name '$PlanInput'. Matches: $names"
    }

    throw "No plan matching '$PlanInput' in $SearchDir"
}