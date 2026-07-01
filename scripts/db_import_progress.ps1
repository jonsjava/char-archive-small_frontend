# Shared database import progress helpers for setup.ps1 and init-db.ps1.

function Format-ByteSize([long]$Bytes) {
    if ($Bytes -ge 1GB) { return "{0:N1} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N1} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N1} KB" -f ($Bytes / 1KB) }
    return "$Bytes B"
}

function Convert-DockerMountPath([string]$Path) {
    return ($Path -replace '\\', '/')
}

function Get-PgRestoreObjectCountFromDump([string]$DumpPath) {
    if (-not (Test-Path -LiteralPath $DumpPath)) { return 0 }
    $dockerDump = Convert-DockerMountPath (Resolve-Path -LiteralPath $DumpPath).Path
    $raw = docker run --rm -v "${dockerDump}:/dump:ro" postgres:16-alpine `
        sh -c "pg_restore -l /dump 2>/dev/null | grep -c '^[0-9]'" 2>$null
    $count = 0
    [void][int]::TryParse(($raw -replace '\D', ''), [ref]$count)
    return $count
}

function Get-PostgresContainerLogs {
    return (docker compose logs postgres --no-color 2>&1 | Out-String)
}

function Get-PgRestoreLogStats {
    param([string]$Logs)
    if (-not $Logs) {
        return @{ Steps = 0; LastLine = '' }
    }
    $matches = [regex]::Matches($Logs, 'pg_restore: (creating|processing|connecting|executing)')
    $lines = $Logs -split "`r?`n" | Where-Object { $_ -match 'pg_restore:' }
    $last = if ($lines.Count -gt 0) { $lines[-1].Trim() } else { '' }
    if ($last.Length -gt 55) {
        $last = $last.Substring(0, 52) + '...'
    }
    return @{
        Steps    = $matches.Count
        LastLine = $last
    }
}

function Test-DbImportComplete {
    param(
        [string]$Logs,
        [hashtable]$Metrics
    )
    if ($Logs -match 'Database restore completed!') { return $true }
    if ($Logs -match 'Database already has [0-9]+ tables, skipping restore') { return $true }
    if ($Metrics -and $Metrics.TableCount -gt 0) {
        $active = docker compose exec -T postgres psql -U char_archive -d char_archive -t -A -c `
            "SELECT count(*) FROM pg_stat_activity WHERE query ILIKE '%pg_restore%' AND pid <> pg_backend_pid();" 2>$null
        if ($active -eq '0') { return $true }
    }
    return $false
}

function Get-DockerDbMetrics {
    $raw = docker compose exec -T postgres psql -U char_archive -d char_archive -t -A -c `
        "SELECT pg_database_size(current_database()), (SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public');" 2>$null
    if (-not $raw) { return $null }
    $parts = ($raw.Trim() -split '\|')
    if ($parts.Count -lt 2) { return $null }
    return @{
        DbSize     = [long]$parts[0]
        TableCount = [int]$parts[1]
    }
}

function Write-ImportProgressLine {
    param(
        [int]$Percent,
        [string]$Phase,
        [string]$Detail,
        [int]$ElapsedSec
    )
    $width = 36
    if ($Percent -lt 0) {
        $filled = ($ElapsedSec % ($width + 1))
        if ($filled -ge $width) { $filled = $width - 1 }
        $bar = ('=' * $filled) + '>' + (' ' * ($width - $filled - 1))
        $pctText = '...'
    } else {
        $filled = [Math]::Min($width, [Math]::Max(0, [int]($width * $Percent / 100)))
        $bar = ('=' * $filled) + (' ' * ($width - $filled))
        $pctText = "$Percent%"
    }
    $mins = [int]($ElapsedSec / 60)
    $secs = $ElapsedSec % 60
    $time = "{0:D2}:{1:D2}" -f $mins, $secs
    Write-Host ("`r  [{0}] {1}  {2}  ({3})  {4}    " -f $bar, $pctText, $Phase, $time, $Detail) -NoNewline
}

function Wait-ForDockerDbImport {
    param(
        [string]$DumpPath,
        [int]$PollSeconds = 5,
        [int]$MaxAttempts = 720
    )
    Write-Host "Waiting for database import (first run can take 30+ minutes)..."

    $dumpSize = 0
    if (Test-Path -LiteralPath $DumpPath) {
        $dumpSize = (Get-Item -LiteralPath $DumpPath).Length
    }

    Write-Host "  Measuring dump catalog size..."
    $totalObjects = Get-PgRestoreObjectCountFromDump $DumpPath
    if ($totalObjects -le 0 -and $dumpSize -gt 0) {
        $totalObjects = [Math]::Max(500, [int]($dumpSize / 80000))
    }
    if ($totalObjects -gt 0) {
        Write-Host "  Import has about $totalObjects restore steps."
    }

    $start = Get-Date
    $attempt = 0

    try {
        while ($attempt -lt $MaxAttempts) {
            $attempt++
            $elapsed = [int]((Get-Date) - $start).TotalSeconds
            $logs = Get-PostgresContainerLogs
            $logStats = Get-PgRestoreLogStats -Logs $logs
            $metrics = Get-DockerDbMetrics

            if (Test-DbImportComplete -Logs $logs -Metrics $metrics) {
                $tables = if ($metrics) { $metrics.TableCount } else { '?' }
                Write-ImportProgressLine -Percent 100 -Phase "Done" -Detail "tables: $tables" -ElapsedSec $elapsed
                Write-Host ""
                Write-Host "Database ready: $tables public tables."
                return
            }

            $pct = -1
            if ($totalObjects -gt 0 -and $logStats.Steps -gt 0) {
                $pct = [Math]::Min(99, [int](100 * $logStats.Steps / $totalObjects))
            }

            $detail = if ($logStats.LastLine) { $logStats.LastLine } else { "waiting for pg_restore output" }
            if ($metrics) {
                $detail = "tables: $($metrics.TableCount), size: $(Format-ByteSize $metrics.DbSize) - $detail"
            } elseif ($logStats.Steps -gt 0) {
                $detail = "step $($logStats.Steps) of ~$totalObjects - $detail"
            }

            $phase = if ($logs -match 'Starting database restore') { "Restoring" } else { "Starting" }
            Write-ImportProgressLine -Percent $pct -Phase $phase -Detail $detail -ElapsedSec $elapsed
            Start-Sleep -Seconds $PollSeconds
        }
    } finally {
        Write-Host ""
    }

    throw "Timed out waiting for database. Check: docker compose logs postgres"
}

function Invoke-LocalDbRestoreWithProgress {
    param(
        [hashtable]$Db,
        [string]$DumpPath,
        [int]$PollSeconds = 5
    )

    $dumpSize = (Get-Item -LiteralPath $DumpPath).Length
    $totalObjects = 0
    if (Get-Command pg_restore -ErrorAction SilentlyContinue) {
        $list = & pg_restore -l $DumpPath 2>$null | Where-Object { $_ -match '^\d' }
        $totalObjects = @($list).Count
    }
    if ($totalObjects -le 0) {
        $totalObjects = [Math]::Max(500, [int]($dumpSize / 80000))
    }

    $restoreArgs = @(
        '-h', $Db.Host,
        '-p', $Db.Port,
        '-U', $Db.User,
        '-d', $Db.Name,
        '-v', $DumpPath
    )

    $proc = Start-Process -FilePath pg_restore -ArgumentList $restoreArgs -PassThru -NoNewWindow
    $start = Get-Date
    $lastTables = 0

    try {
        while (-not $proc.HasExited) {
            $elapsed = [int]((Get-Date) - $start).TotalSeconds
            $raw = psql -h $Db.Host -p $Db.Port -U $Db.User -d $Db.Name -t -A -c `
                "SELECT pg_database_size(current_database()), (SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public');" 2>$null
            $pct = -1
            $detail = "pg_restore running"
            if ($raw) {
                $parts = ($raw.Trim() -split '\|')
                if ($parts.Count -ge 2) {
                    $dbSize = [long]$parts[0]
                    $lastTables = [int]$parts[1]
                    $estimated = [Math]::Max(1, [long]($dumpSize * 2.5))
                    $pct = [Math]::Min(99, [int](100 * $dbSize / $estimated))
                    $detail = "tables: $lastTables, size: $(Format-ByteSize $dbSize)"
                }
            }
            Write-ImportProgressLine -Percent $pct -Phase "Restoring" -Detail $detail -ElapsedSec $elapsed
            Start-Sleep -Seconds $PollSeconds
        }
    } finally {
        Write-Host ""
    }

    if ($proc.ExitCode -ne 0) {
        Write-Warning "pg_restore exited with code $($proc.ExitCode) (some warnings are normal for custom dumps)."
    }
    Write-Host "Database restore completed. Public tables: $lastTables"
}
