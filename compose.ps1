# Docker Compose wrapper for Windows — ensures .env exists before running compose.
#
# Usage (same as docker compose):
#   .\compose.ps1 up -d              # rebuilds images on up (picks up UI changes)
#   .\compose.ps1 -Dev up -d         # bind-mount source for live reload
#   .\compose.ps1 build --no-cache frontend
#   .\compose.ps1 logs -f frontend
#
# For first-time setup (torrent paths, DB import), use .\setup.ps1 instead.

param(
    [switch]$Dev,
    [switch]$NoBuild,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ComposeArgs
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

if (-not (Test-Path ".env")) {
    Write-Host "No .env found — creating from .env.example (default password: changeme)."
    Write-Host "For full setup with your torrent folder and DB import, run: .\setup.ps1"
    Copy-Item ".env.example" ".env"
}

$composeFiles = @("-f", "docker-compose.yml")
if ($Dev) {
    $composeFiles += @("-f", "docker-compose.dev.yml")
    Write-Host "Dev mode: mounting ./small_front into containers (live reload)."
}
if (Test-Path "docker-compose.override.yml") {
    $composeFiles += @("-f", "docker-compose.override.yml")
}

# Rebuild on `up` so UI/template changes in git are not served from a stale image.
if (-not $NoBuild -and $ComposeArgs.Count -ge 1 -and $ComposeArgs[0] -eq "up") {
    if ($ComposeArgs -notcontains "--build" -and $ComposeArgs -notcontains "--no-build") {
        $ComposeArgs += "--build"
        Write-Host "Rebuilding images (--build). Pass -NoBuild to skip."
    }
}

if ($ComposeArgs.Count -eq 0) {
    docker compose @composeFiles
} else {
    docker compose @composeFiles @ComposeArgs
}
