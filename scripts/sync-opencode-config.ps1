#!/usr/bin/env pwsh
# Lara Diaries - OpenCode Config Sync Script (Windows)
# Backs up $env:APPDATA\opencode to opencode-config GitHub repo
$ErrorActionPreference = "Stop"

$configRepo   = Join-Path $HOME "opencode-config"
$opencodePath = Join-Path $env:APPDATA "opencode"
$logDir       = Join-Path $env:LOCALAPPDATA "lara-diaries"
$logFile      = Join-Path $logDir "sync-opencode.log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"
    switch ($Level) {
        "ERROR" { Write-Host $line -ForegroundColor Red }
        "WARN"  { Write-Host $line -ForegroundColor Yellow }
        default { Write-Host $line -ForegroundColor Gray }
    }
    if (-not (Test-Path -LiteralPath $logDir)) {
        $null = New-Item -ItemType Directory -Path $logDir -Force
    }
    Add-Content -Path $logFile -Value $line
}

function Sync-OpencodeConfig {
    Write-Log "OpenCode Config Sync Start"

    if (-not (Test-Path -LiteralPath $configRepo)) {
        Write-Log "Config repo no encontrado en: $configRepo" -Level "ERROR"
        return $false
    }
    if (-not (Test-Path -LiteralPath $opencodePath)) {
        Write-Log "OpenCode config no encontrado en: $opencodePath" -Level "ERROR"
        return $false
    }

    try {
        Push-Location $configRepo
        Write-Log "Ejecutando git pull --rebase ..."
        $null = & git pull --rebase 2>&1

        $configDir = Join-Path $configRepo "config"
        if (-not (Test-Path -LiteralPath $configDir)) {
            $null = New-Item -ItemType Directory -Path $configDir -Force
        }

        # Robocopy: /MIR mirrors, /XD exclude dirs
        $robocopyArgs = @(
            $opencodePath, $configDir, "/MIR",
            "/XD", "node_modules", ".git",
            "/NJH", "/NJS", "/NDL", "/NP"
        )
        $null = & robocopy @robocopyArgs
        Write-Log "Config files copied."

        $status = & git status --porcelain
        if (-not $status) {
            Write-Log "Sin cambios nuevos - nada que commitear."
            Pop-Location
            return $true
        }

        $dateStr = Get-Date -Format "yyyy-MM-dd HH:mm"
        $null = & git add .
        $null = & git commit -m "sync: opencode config $dateStr"
        Write-Log "Commit creado."

        $null = & git push
        Write-Log "Push exitoso."
        Pop-Location
        Write-Log "[OK] OpenCode Config Sync completada exitosamente."
        return $true

    } catch {
        Write-Log "Error inesperado: $_" -Level "ERROR"
        try { Pop-Location } catch {}
        return $false
    }
}

$result = Sync-OpencodeConfig
if ($result) { Write-Log "Sync End (OK)" } else { Write-Log "Sync End (FAILED)" -Level "ERROR"; exit 1 }
exit 0
