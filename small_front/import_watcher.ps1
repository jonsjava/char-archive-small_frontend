# Poll the import/ folder for new character cards (local dev, without Docker importer service).
# Usage: .\import_watcher.ps1

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
. "$PSScriptRoot\dev-env.ps1"

Import-DevEnvFile
$python = Get-DevPython

Write-Host "Starting import watcher (IMPORT_DIR=$($env:IMPORT_DIR), interval=$($env:IMPORT_SCAN_INTERVAL)s)..."
& $python import_watcher.py
