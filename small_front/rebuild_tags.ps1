# Rebuild the tag index (run once after restoring the database, or after bulk imports).
# Usage: .\rebuild_tags.ps1

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
. "$PSScriptRoot\dev-env.ps1"

Import-DevEnvFile
$python = Get-DevPython

Write-Host "Rebuilding tag index..."
& $python rebuild_tag_index.py
