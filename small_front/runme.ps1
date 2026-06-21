# Local dev launcher for Windows (PowerShell).
# Usage: .\runme.ps1

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
. "$PSScriptRoot\dev-env.ps1"

Import-DevEnvFile
if (-not $env:ENABLE_IMPORT_SCANNER) { $env:ENABLE_IMPORT_SCANNER = "true" }
$python = Get-DevPython

$port = if ($env:PORT) { $env:PORT } else { "5000" }
Write-Host "Starting Flask app (http://localhost:$port)..."
& $python app.py
