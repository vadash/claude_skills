# install.ps1 — One-time setup to make auto-execute callable from anywhere.
# Adds the skill directory to user PATH and creates a .cmd shim.

$skillDir = $PSScriptRoot

# --- Create .cmd shim for cmd.exe compatibility ---
$cmdShim = Join-Path $skillDir "auto-execute.cmd"
if (-not (Test-Path $cmdShim)) {
    @"
@echo off
powershell -NoProfile -File "%~dp0auto-execute.ps1" %*
"@ | Out-File -FilePath $cmdShim -Encoding ASCII
    Write-Host "Created $cmdShim" -ForegroundColor Green
} else {
    Write-Host "Shim already exists: $cmdShim" -ForegroundColor DarkGray
}

# --- Add to user PATH ---
$userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($userPath -split ";" | Where-Object { $_ -eq $skillDir }) {
    Write-Host "Already in PATH: $skillDir" -ForegroundColor DarkGray
} else {
    $newPath = "$userPath;$skillDir"
    [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
    Write-Host "Added to user PATH: $skillDir" -ForegroundColor Green
    Write-Host "Restart your terminal for PATH changes to take effect." -ForegroundColor Yellow
}