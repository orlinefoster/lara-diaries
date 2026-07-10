#!/usr/bin/env pwsh
# Lara Diaries - Memory Sync Script (Windows)
# Syncs engram memories to GitHub private repo via engram sync
$ErrorActionPreference = "Stop"

$engramRepo   = Join-Path $HOME "engram-memories"
$logDir       = Join-Path $env:LOCALAPPDATA "lara-diaries"
$logFile      = Join-Path $logDir "sync.log"
$project      = if ($args[0]) { $args[0] } else { "lara-diaries" }

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

function Sync-Memories {
    Write-Log "Sync Start (project: $project)"

    if (-not (Test-Path -LiteralPath $engramRepo)) {
        Write-Log "Repo no encontrado en: $engramRepo" -Level "ERROR"
        return $false
    }

    try {
        Push-Location $engramRepo
        Write-Log "Ejecutando git pull --rebase ..."
        $null = & git pull --rebase 2>&1

        # Export memories via engram sync
        Write-Log "Ejecutando: engram sync --project $project"
        $syncOutput = & engram sync --project $project 2>&1
        Write-Log $syncOutput

        $status = & git status --porcelain
        if (-not $status) {
            Write-Log "Sin cambios nuevos - nada que commitear."
            Pop-Location
            return $true
        }

        $dateStr = Get-Date -Format "yyyy-MM-dd HH:mm"
        $null = & git add .
        $null = & git commit -m "sync: memories $dateStr"
        Write-Log "Commit creado."

        $null = & git push
        Write-Log "Push exitoso."

        Pop-Location
        Write-Log "[OK] Sync completada exitosamente."
        return $true

    } catch {
        Write-Log "Error inesperado: $_" -Level "ERROR"
        try { Pop-Location } catch {}
        return $false
    }
}

$result = Sync-Memories
if ($result) { $syncStatus = "OK" } else { $syncStatus = "FAILED" }
Write-Log "Sync End ($syncStatus)"
if (-not $result) { exit 1 }
exit 0
