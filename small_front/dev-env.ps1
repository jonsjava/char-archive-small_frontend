# Shared helpers for small_front PowerShell scripts.
# Dot-source from runme.ps1, rebuild_tags.ps1, import_watcher.ps1, etc.

$DevEnvRoot = $PSScriptRoot

function Import-DevEnvFile {
    param([string]$EnvFile = (Join-Path $DevEnvRoot ".env"))

    if (-not (Test-Path $EnvFile)) {
        throw "Missing .env — copy .env.example to .env and edit it."
    }

    foreach ($line in Get-Content $EnvFile) {
        if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }
        if ($line -match '^([^=]+)=(.*)$') {
            Set-Item -Path "env:$($Matches[1].Trim())" -Value $Matches[2].Trim()
        }
    }
}

function Resolve-VenvPath {
    $venvPath = $env:VENV_PATH
    if (-not $venvPath) {
        return Join-Path $env:USERPROFILE "venv"
    }
    if ($venvPath -eq "~" -or $venvPath.StartsWith("~/")) {
        return Join-Path $env:USERPROFILE $venvPath.TrimStart("~/")
    }
    return $venvPath
}

function Get-DevPython {
    $venvPath = Resolve-VenvPath
    $python = Join-Path $venvPath "Scripts\python.exe"
    $pip = Join-Path $venvPath "Scripts\pip.exe"

    if (-not (Test-Path $python)) {
        Write-Host "Creating virtualenv at $venvPath"
        python -m venv $venvPath
        & $pip install -r (Join-Path $DevEnvRoot "requirements.txt")
    }

    return $python
}
