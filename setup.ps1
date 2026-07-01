# Character Archive Frontend — one-shot setup for Windows (PowerShell + Docker Desktop).
#
# Usage:
#   .\setup.ps1
#   .\setup.ps1 -Debug
#   .\setup.ps1 -TorrentDir "C:\Downloads\character-archive-final-torrent"
#   .\setup.ps1 -TorrentDir "C:\Downloads\torrent" -NoWait -SkipTags

param(
    [string]$TorrentDir = "",
    [switch]$NoWait,
    [switch]$SkipTags,
    [switch]$Debug
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

function Write-Info($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Err($msg) { Write-Host "Error: $msg" -ForegroundColor Red; exit 1 }
function Write-DebugLog($msg) {
    if ($Debug) { Write-Host "[debug] $msg" -ForegroundColor DarkGray }
}

function Test-PathStatus([string]$Path, [string]$Type = "Any") {
    if (-not $Path) { return "empty" }
    if ($Type -eq "Leaf") {
        if (Test-Path -LiteralPath $Path -PathType Leaf) { return "found (file)" }
    } elseif ($Type -eq "Container") {
        if (Test-Path -LiteralPath $Path -PathType Container) { return "found (directory)" }
    } else {
        if (Test-Path -LiteralPath $Path -PathType Leaf) { return "found (file)" }
        if (Test-Path -LiteralPath $Path -PathType Container) { return "found (directory)" }
    }
    return "missing"
}

function Test-Docker {
    Write-DebugLog "Test-Docker: checking docker info"
    try {
        docker info | Out-Null
        Write-DebugLog "Test-Docker: docker info OK"
    } catch {
        Write-Err "Docker is not running. Start Docker Desktop and try again."
    }
    Write-DebugLog "Test-Docker: checking docker compose version"
    try {
        $composeVersion = docker compose version 2>&1
        Write-DebugLog "Test-Docker: $composeVersion"
        docker compose version | Out-Null
    } catch {
        Write-Err "docker compose (v2) is required."
    }
}

function Resolve-AbsPath([string]$Path) {
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    Write-DebugLog "Resolve-AbsPath: '$Path' -> '$resolved'"
    return $resolved
}

function Test-TorrentDir([string]$Root) {
    Write-DebugLog "Test-TorrentDir: validating '$Root'"
    $dirStatus = Test-PathStatus $Root "Container"
    Write-DebugLog "  directory -> $dirStatus"
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        Write-Err "Torrent directory not found: $Root"
    }
    $dumpPath = Join-Path $Root "database.dump"
    $dumpStatus = Test-PathStatus $dumpPath "Leaf"
    Write-DebugLog "  $dumpPath -> $dumpStatus"
    if (-not (Test-Path -LiteralPath $dumpPath -PathType Leaf)) {
        Write-Err "Missing $Root\database.dump (should be at torrent root)."
    }
    $hashedPath = Join-Path $Root "archive\hashed-data"
    $hashedStatus = Test-PathStatus $hashedPath "Container"
    Write-DebugLog "  $hashedPath -> $hashedStatus"
    if (-not (Test-Path -LiteralPath $hashedPath -PathType Container)) {
        Write-Err "Missing $Root\archive\hashed-data - extract archive.7z.* first."
    }
}

function Find-TorrentDir {
    $candidates = @(
        $PWD.Path,
        (Split-Path $PWD.Path -Parent),
        (Join-Path $env:USERPROFILE "Downloads\character-archive-final-torrent"),
        (Join-Path $env:USERPROFILE "Downloads\char-achrive-final\character-archive-final-torrent")
    )
    Write-DebugLog "Find-TorrentDir: scanning $($candidates.Count) locations"
    foreach ($c in $candidates) {
        $dumpPath = Join-Path $c "database.dump"
        $hashedPath = Join-Path $c "archive\hashed-data"
        $dumpStatus = Test-PathStatus $dumpPath "Leaf"
        $hashedStatus = Test-PathStatus $hashedPath "Container"
        Write-DebugLog "  $c"
        Write-DebugLog "    database.dump -> $dumpStatus"
        Write-DebugLog "    archive\hashed-data -> $hashedStatus"
        if ((Test-Path (Join-Path $c "database.dump")) -and (Test-Path (Join-Path $c "archive\hashed-data"))) {
            Write-DebugLog "Find-TorrentDir: matched '$c'"
            return $c
        }
    }
    Write-DebugLog "Find-TorrentDir: no match"
    return $null
}

function New-RandomPassword {
    # 24 bytes -> ~32 base64 chars; stripping [+/=] can shorten, so keep a safe margin.
    $bytes = New-Object byte[] 24
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $token = [Convert]::ToBase64String($bytes) -replace '[+/=]', ''
    return $token.Substring(0, 20)
}

function Write-EnvFile([string]$Root, [string]$ArchivePath, [string]$DumpPath) {
    Write-DebugLog "Write-EnvFile: TORRENT_DIR=$Root"
    Write-DebugLog "Write-EnvFile: ARCHIVE_HOST_PATH=$ArchivePath"
    Write-DebugLog "Write-EnvFile: DATABASE_DUMP_PATH=$DumpPath"
    $pgPass = New-RandomPassword
    $pgAdminPass = New-RandomPassword
    if (Test-Path ".env") {
        Write-Info "Updating .env (keeping existing passwords if set)"
        $existing = Get-Content ".env" -Raw
        if ($existing -match '(?m)^POSTGRES_PASSWORD=(.+)$') { $pgPass = $Matches[1].Trim() }
        if ($existing -match '(?m)^PGADMIN_DEFAULT_PASSWORD=(.+)$') { $pgAdminPass = $Matches[1].Trim() }
        Write-DebugLog "Write-EnvFile: reusing existing passwords from .env"
    }
    $lines = Get-Content ".env.example"
    $out = foreach ($line in $lines) {
        if ($line -match '^TORRENT_DIR=') { "TORRENT_DIR=$Root" }
        elseif ($line -match '^ARCHIVE_HOST_PATH=') { "ARCHIVE_HOST_PATH=$ArchivePath" }
        elseif ($line -match '^DATABASE_DUMP_PATH=') { "DATABASE_DUMP_PATH=$DumpPath" }
        elseif ($line -match '^POSTGRES_PASSWORD=') { "POSTGRES_PASSWORD=$pgPass" }
        elseif ($line -match '^PGADMIN_DEFAULT_PASSWORD=') { "PGADMIN_DEFAULT_PASSWORD=$pgAdminPass" }
        else { $line }
    }
    $out | Set-Content -Encoding utf8 ".env"
    Write-DebugLog "Write-EnvFile: wrote .env, line count: $($out.Count)"
}

function Write-OverrideFile([string]$ArchivePath, [string]$DumpPath) {
    # Docker Compose on Windows expects forward slashes in bind-mount paths.
    $ArchivePath = $ArchivePath -replace '\\', '/'
    $DumpPath = $DumpPath -replace '\\', '/'
    Write-DebugLog "Write-OverrideFile: archive mount=$ArchivePath"
    Write-DebugLog "Write-OverrideFile: dump mount=$DumpPath"
    # Avoid here-strings (Windows PowerShell 5.1 is picky about closing "@).
    $yaml = (
        "# Auto-generated by setup.ps1 - do not commit.",
        "services:",
        "  frontend:",
        "    volumes:",
        "      - ${ArchivePath}:/archive:ro",
        "  postgres:",
        "    volumes:",
        "      - ${DumpPath}:/docker-entrypoint-initdb.d/database.dump:ro",
        "      - ./init-db.sh:/docker-entrypoint-initdb.d/zz-init-db.sh:ro"
    ) -join "`n"
    $yaml | Set-Content -Encoding utf8 "docker-compose.override.yml"
    Write-DebugLog "Write-OverrideFile: wrote docker-compose.override.yml"
    if ($Debug) {
        Write-DebugLog "docker-compose.override.yml contents:"
        Get-Content "docker-compose.override.yml" | ForEach-Object { Write-DebugLog "  $_" }
    }
}

function Wait-ForDatabase {
    . "$PSScriptRoot\scripts\db_import_progress.ps1"
    try {
        Wait-ForDockerDbImport -DumpPath $script:DumpPathForImport
    } catch {
        Write-Err $_.Exception.Message
    }
}

function Invoke-TagRebuild {
    Write-Info "Rebuilding tag index (needed for tag search)..."
    docker compose exec -T frontend python rebuild_tag_index.py
}

function Show-Success {
    $port = "8080"
    $pgPort = "5050"
    if (Test-Path ".env") {
        foreach ($line in Get-Content ".env") {
            if ($line -match '^FRONTEND_PORT=(.+)$') { $port = $Matches[1].Trim() }
            if ($line -match '^PGADMIN_PORT=(.+)$') { $pgPort = $Matches[1].Trim() }
        }
    }
    Write-Host ""
    Write-Host "Setup complete."
    Write-Host "  Frontend:  http://localhost:$port"
    Write-Host "  pgAdmin:   http://localhost:$pgPort"
    Write-Host ""
    Write-Host "Credentials are in .env (POSTGRES_PASSWORD, PGADMIN_DEFAULT_PASSWORD)."
    Write-Host "If the UI looks outdated after a git pull, run: docker compose up -d --build frontend"
}

# --- main ---
Write-DebugLog "setup.ps1 starting"
Write-DebugLog "  PSScriptRoot: $PSScriptRoot"
Write-DebugLog "  PWD:          $PWD"
Write-DebugLog "  TorrentDir arg: $(if ($TorrentDir) { $TorrentDir } else { '(not set)' })"
Write-DebugLog "  NoWait: $NoWait  SkipTags: $SkipTags"

Test-Docker
New-Item -ItemType Directory -Force -Path "db_data/postgres", "db_data/pgadmin", "import/processed", "import/failed" | Out-Null
Write-DebugLog "Ensured data directories exist under $PWD"

if (-not $TorrentDir) {
    $detected = Find-TorrentDir
    if ($detected) {
        Write-Host "Detected torrent folder: $detected"
        $input = Read-Host "Torrent download directory [$detected]"
        $TorrentDir = if ($input) { $input } else { $detected }
        Write-DebugLog "TorrentDir from prompt: '$TorrentDir' (detected was '$detected', input was '$input')"
    } else {
        $TorrentDir = Read-Host "Torrent download directory (required)"
        Write-DebugLog "TorrentDir from prompt (no auto-detect): '$TorrentDir'"
    }
}

if (-not $TorrentDir) { Write-Err "Torrent directory is required." }

$TorrentDir = Resolve-AbsPath $TorrentDir
Test-TorrentDir $TorrentDir

$ArchivePath = Join-Path $TorrentDir "archive"
$DumpPath = Join-Path $TorrentDir "database.dump"
$script:DumpPathForImport = $DumpPath

Write-Info "Torrent dir:  $TorrentDir"
Write-Info "Archive:      $ArchivePath"
Write-Info "Database:     $DumpPath"

Write-EnvFile $TorrentDir $ArchivePath $DumpPath
Write-OverrideFile $ArchivePath $DumpPath

Write-Info "Starting Docker Compose..."
Write-DebugLog "Running: docker compose up -d --build"
docker compose up -d --build
Write-DebugLog "docker compose up exit code: $LASTEXITCODE"

if ($NoWait) {
    Write-Host "Skipped wait (-NoWait). When import finishes, run:"
    Write-Host "  docker compose exec frontend python rebuild_tag_index.py"
    Show-Success
    exit 0
}

Wait-ForDatabase

if (-not $SkipTags) {
    try { Invoke-TagRebuild } catch {
        Write-Host "Warning: tag index rebuild failed - run later: docker compose exec frontend python rebuild_tag_index.py"
    }
}

Show-Success
