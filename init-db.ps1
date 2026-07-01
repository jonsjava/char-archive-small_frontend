# Restore database.dump to a local PostgreSQL instance if the database is empty.
# For Docker-based setup, use setup.ps1 instead (init runs inside the postgres container).
#
# Usage:
#   .\init-db.ps1
#   .\init-db.ps1 -Debug
#   .\init-db.ps1 -DumpPath "C:\Downloads\character-archive-final-torrent\database.dump"
#   .\init-db.ps1 -DumpPath "...\database.dump" -EnvFile "small_front\.env"

param(
    [string]$DumpPath = "",
    [string]$EnvFile = "small_front\.env",
    [switch]$Debug
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

function Write-DebugLog($msg) {
    if ($Debug) { Write-Host "[debug] $msg" -ForegroundColor DarkGray }
}

function Test-PathStatus([string]$Path) {
    if (-not $Path) { return "empty" }
    if (Test-Path -LiteralPath $Path -PathType Leaf) { return "found (file)" }
    if (Test-Path -LiteralPath $Path -PathType Container) { return "found (directory)" }
    return "missing"
}

function Normalize-PathValue([string]$Path) {
    $original = $Path
    $Path = $Path.Trim()
    if ($Path -match '^"(.*)"$' -or $Path -match "^'(.*)'$") {
        Write-DebugLog "Normalize-PathValue: stripped quotes from '$original' -> '$($Matches[1].Trim())'"
        return $Matches[1].Trim()
    }
    if ($original -ne $Path) {
        Write-DebugLog "Normalize-PathValue: trimmed whitespace from '$original' -> '$Path'"
    }
    return $Path
}

function Read-EnvFile([string]$Path) {
    $vars = @{}
    if (-not (Test-Path $Path)) {
        Write-DebugLog "Read-EnvFile: $Path not found"
        return $vars
    }
    Write-DebugLog "Read-EnvFile: reading $Path"
    foreach ($line in Get-Content $Path) {
        if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }
        if ($line -match '^([^=]+)=(.*)$') {
            $key = $Matches[1].Trim()
            $value = Normalize-PathValue $Matches[2]
            $vars[$key] = $value
            if ($key -match 'PASSWORD') {
                Write-DebugLog "  $key=(set, length $($value.Length))"
            } else {
                Write-DebugLog "  $key=$value"
            }
        }
    }
    return $vars
}

function Get-DbSettings {
    # Defaults match small_front/.env.example and the README local Postgres setup.
    $settings = @{
        Host     = "localhost"
        Port     = "5432"
        Name     = "char_archive"
        User     = "char_archive"
        Password = "changeme"
    }
    $sources = @("defaults")

    $rootEnv = Read-EnvFile ".env"
    if ($rootEnv.Count -gt 0) {
        $sources += "repo .env"
        if ($rootEnv.POSTGRES_USER) { $settings.User = $rootEnv.POSTGRES_USER }
        if ($rootEnv.POSTGRES_PASSWORD) { $settings.Password = $rootEnv.POSTGRES_PASSWORD }
        if ($rootEnv.POSTGRES_DB) { $settings.Name = $rootEnv.POSTGRES_DB }
        if ($rootEnv.POSTGRES_PORT) { $settings.Port = $rootEnv.POSTGRES_PORT }
    }

    $appEnv = Read-EnvFile $EnvFile
    if ($appEnv.Count -gt 0) {
        $sources += $EnvFile
        if ($appEnv.DB_HOST) { $settings.Host = $appEnv.DB_HOST }
        if ($appEnv.DB_PORT) { $settings.Port = $appEnv.DB_PORT }
        if ($appEnv.DB_NAME) { $settings.Name = $appEnv.DB_NAME }
        if ($appEnv.DB_USER) { $settings.User = $appEnv.DB_USER }
        if ($appEnv.DB_PASSWORD) { $settings.Password = $appEnv.DB_PASSWORD }
    }

    if ($env:DB_HOST) { $settings.Host = $env:DB_HOST; $sources += "DB_HOST env" }
    if ($env:DB_PORT) { $settings.Port = $env:DB_PORT; $sources += "DB_PORT env" }
    if ($env:DB_NAME) { $settings.Name = $env:DB_NAME; $sources += "DB_NAME env" }
    if ($env:DB_USER) { $settings.User = $env:DB_USER; $sources += "DB_USER env" }
    if ($env:DB_PASSWORD) { $settings.Password = $env:DB_PASSWORD; $sources += "DB_PASSWORD env" }
    if ($env:PGPASSWORD) { $settings.Password = $env:PGPASSWORD; $sources += "PGPASSWORD env" }

    $settings.Source = ($sources | Select-Object -Unique) -join ", "
    return $settings
}

function Find-TorrentDump {
    $candidates = @(
        $PWD.Path,
        (Split-Path $PWD.Path -Parent),
        (Join-Path $env:USERPROFILE "Downloads\character-archive-final-torrent"),
        (Join-Path $env:USERPROFILE "Downloads\char-achrive-final\character-archive-final-torrent")
    )
    Write-DebugLog "Find-TorrentDump: scanning $($candidates.Count) locations"
    foreach ($dir in $candidates) {
        $dump = Join-Path $dir "database.dump"
        $status = Test-PathStatus $dump
        Write-DebugLog "  $dump -> $status"
        if ($status -eq "found (file)") {
            return $dump
        }
    }
    return $null
}

function Resolve-DumpPath([string]$Path, [string]$Source = "unknown") {
    $raw = $Path
    $Path = Normalize-PathValue $Path
    if (-not $Path) {
        Write-DebugLog "Resolve-DumpPath($Source): empty after normalize (raw='$raw')"
        return $null
    }
    try {
        $resolved = (Resolve-Path -LiteralPath $Path).Path
        Write-DebugLog "Resolve-DumpPath($Source): '$raw' -> '$resolved'"
        return $resolved
    } catch {
        Write-DebugLog "Resolve-DumpPath($Source): '$raw' -> unresolved ('$Path'), Resolve-Path failed: $($_.Exception.Message)"
        return $Path
    }
}

function Resolve-DumpPathOrDie {
    $candidateRecords = @()

    if ($DumpPath) {
        $candidateRecords += [PSCustomObject]@{
            Source = "-DumpPath parameter"
            Raw    = $DumpPath
            Path   = (Resolve-DumpPath $DumpPath "-DumpPath parameter")
        }
    } else {
        Write-DebugLog "Resolve-DumpPathOrDie: no -DumpPath parameter supplied"
    }

    if (Test-Path ".env") {
        Write-DebugLog "Resolve-DumpPathOrDie: reading paths from .env"
        foreach ($line in Get-Content ".env") {
            if ($line -match '^\s*DATABASE_DUMP_PATH=(.+)$') {
                $candidateRecords += [PSCustomObject]@{
                    Source = ".env DATABASE_DUMP_PATH"
                    Raw    = $Matches[1]
                    Path   = (Resolve-DumpPath $Matches[1] ".env DATABASE_DUMP_PATH")
                }
            } elseif ($line -match '^\s*TORRENT_DIR=(.+)$') {
                $torrentDir = Normalize-PathValue $Matches[1]
                $joined = Join-Path $torrentDir "database.dump"
                $candidateRecords += [PSCustomObject]@{
                    Source = ".env TORRENT_DIR + database.dump"
                    Raw    = $joined
                    Path   = (Resolve-DumpPath $joined ".env TORRENT_DIR")
                }
            }
        }
    } else {
        Write-DebugLog "Resolve-DumpPathOrDie: no .env in $PWD"
    }

    $detected = Find-TorrentDump
    if ($detected) {
        $candidateRecords += [PSCustomObject]@{
            Source = "auto-detect (Find-TorrentDump)"
            Raw    = $detected
            Path   = $detected
        }
    }

    Write-DebugLog "Resolve-DumpPathOrDie: evaluating $($candidateRecords.Count) candidate(s)"
    foreach ($record in $candidateRecords) {
        $status = Test-PathStatus $record.Path
        Write-DebugLog "  [$($record.Source)] raw='$($record.Raw)' path='$($record.Path)' -> $status"
    }

    $seen = @{}
    foreach ($record in $candidateRecords) {
        if (-not $record.Path -or $seen[$record.Path]) { continue }
        $seen[$record.Path] = $true
        if (Test-Path -LiteralPath $record.Path -PathType Leaf) {
            Write-DebugLog "Resolve-DumpPathOrDie: selected '$($record.Path)' from $($record.Source)"
            return $record.Path
        }
    }

    Write-Host "Dump file not found." -ForegroundColor Red
    Write-Host ""
    Write-Host "Candidates checked:"
    foreach ($record in $candidateRecords) {
        $status = Test-PathStatus $record.Path
        Write-Host "  [$status] $($record.Source)"
        Write-Host "           raw:  $($record.Raw)"
        Write-Host "           path: $($record.Path)"
    }
    Write-Host ""
    Write-Host "The torrent folder must contain database.dump at its root (alongside archive.7z.*)."
    Write-Host "Common locations:"
    Write-Host "  $env:USERPROFILE\Downloads\character-archive-final-torrent\database.dump"
    Write-Host "  $env:USERPROFILE\Downloads\char-achrive-final\character-archive-final-torrent\database.dump"
    Write-Host ""
    Write-Host "Re-run with -Debug for full resolution details."
    Write-Host "If using Docker instead of local Postgres, run: .\setup.ps1"
    exit 1
}

Write-DebugLog "init-db.ps1 starting"
Write-DebugLog "  PSScriptRoot: $PSScriptRoot"
Write-DebugLog "  PWD:          $PWD"
Write-DebugLog "  EnvFile:      $EnvFile"
Write-DebugLog "  DumpPath arg: $(if ($DumpPath) { $DumpPath } else { '(not set)' })"

$DumpPath = Resolve-DumpPathOrDie
Write-Host "DumpPath: $DumpPath"

$db = Get-DbSettings
if (-not (Test-Path $EnvFile)) {
    if (Test-Path ".env") {
        Write-Host "No $EnvFile — using Postgres settings from repo .env (POSTGRES_*)."
    } else {
        Write-Host "No $EnvFile — using local Postgres defaults (localhost:5432, user char_archive, password changeme)."
        Write-Host "Copy small_front/.env.example to small_front/.env if your settings differ."
    }
}
Write-DebugLog "Database config from: $($db.Source)"
Write-DebugLog "Database target: host=$($db.Host) port=$($db.Port) db=$($db.Name) user=$($db.User) password=(length $($db.Password.Length))"

$env:PGPASSWORD = $db.Password

Write-Host "Checking if database needs to be restored..."

$psqlCmd = "psql -h $($db.Host) -p $($db.Port) -U $($db.User) -d $($db.Name) -t -c `"SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';`""
Write-DebugLog "Running: $psqlCmd"

$tableCount = psql -h $db.Host -p $db.Port -U $db.User -d $db.Name -t -c `
    "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>$null
$tableCount = ($tableCount -replace '\s', '')
Write-DebugLog "Table count result: '$tableCount' (exit code $LASTEXITCODE)"

if ($tableCount -and $tableCount -ne "0") {
    Write-Host "Database already has $tableCount tables, skipping restore."
    exit 0
}

Write-Host "Database is empty, restoring from dump (this may take 30+ minutes)..."
. "$PSScriptRoot\scripts\db_import_progress.ps1"
Invoke-LocalDbRestoreWithProgress -Db $db -DumpPath $DumpPath
