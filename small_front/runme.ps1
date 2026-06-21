# Local dev launcher for Windows (PowerShell).
# Usage: .\runme.ps1

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

if (-not (Test-Path ".env")) {
    Write-Host "Missing .env — copy .env.example to .env and edit it." -ForegroundColor Red
    exit 1
}

foreach ($line in Get-Content ".env") {
    if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }
    if ($line -match '^([^=]+)=(.*)$') {
        $name = $Matches[1].Trim()
        $value = $Matches[2].Trim()
        Set-Item -Path "env:$name" -Value $value
    }
}

$venvPath = $env:VENV_PATH
if (-not $venvPath) {
    $venvPath = Join-Path $env:USERPROFILE "venv"
} elseif ($venvPath.StartsWith("~/") -or $venvPath -eq "~") {
    $venvPath = Join-Path $env:USERPROFILE $venvPath.TrimStart("~/")
}

$python = Join-Path $venvPath "Scripts\python.exe"
$pip = Join-Path $venvPath "Scripts\pip.exe"

if (-not (Test-Path $python)) {
    Write-Host "Creating virtualenv at $venvPath"
    python -m venv $venvPath
    & $pip install -r requirements.txt
}

$port = if ($env:PORT) { $env:PORT } else { "5000" }
Write-Host "Starting Flask app (http://localhost:$port)..."
& $python app.py
