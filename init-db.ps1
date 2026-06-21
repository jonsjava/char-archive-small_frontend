# Restore database.dump to a local PostgreSQL instance if the database is empty.
# For Docker-based setup, use setup.ps1 instead (init runs inside the postgres container).
#
# Usage:
#   .\init-db.ps1 -DumpPath "C:\Downloads\character-archive-final-torrent\database.dump"
#   .\init-db.ps1 -DumpPath "...\database.dump" -EnvFile "small_front\.env"

param(
    [Parameter(Mandatory = $true)]
    [string]$DumpPath,
    [string]$EnvFile = "small_front\.env"
)

$ErrorActionPreference = "Stop"

function Load-EnvFile([string]$Path) {
    if (-not (Test-Path $Path)) {
        Write-Error "Env file not found: $Path"
    }
    foreach ($line in Get-Content $Path) {
        if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }
        if ($line -match '^([^=]+)=(.*)$') {
            Set-Item -Path "env:$($Matches[1].Trim())" -Value $Matches[2].Trim()
        }
    }
}

if (-not (Test-Path -LiteralPath $DumpPath)) {
    Write-Error "Dump file not found: $DumpPath"
}

Load-EnvFile $EnvFile

$dbHost = if ($env:DB_HOST) { $env:DB_HOST } else { "localhost" }
$dbPort = if ($env:DB_PORT) { $env:DB_PORT } else { "5432" }
$dbName = if ($env:DB_NAME) { $env:DB_NAME } else { "char_archive" }
$dbUser = if ($env:DB_USER) { $env:DB_USER } else { "char_archive" }
$dbPassword = $env:DB_PASSWORD

if (-not $dbPassword) {
    Write-Error "DB_PASSWORD not set in $EnvFile"
}

$env:PGPASSWORD = $dbPassword

Write-Host "Checking if database needs to be restored..."

$tableCount = psql -h $dbHost -p $dbPort -U $dbUser -d $dbName -t -c `
    "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>$null
$tableCount = ($tableCount -replace '\s', '')

if ($tableCount -and $tableCount -ne "0") {
    Write-Host "Database already has $tableCount tables, skipping restore."
    exit 0
}

Write-Host "Database is empty, restoring from dump (this may take 30+ minutes)..."
pg_restore -h $dbHost -p $dbPort -U $dbUser -d $dbName -v $DumpPath
if ($LASTEXITCODE -ne 0) {
    Write-Warning "pg_restore exited with code $LASTEXITCODE (some warnings are normal for custom dumps)."
}
Write-Host "Database restore completed."
