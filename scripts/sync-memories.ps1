#!/usr/bin/env pwsh
# Lara Diaries - Memory Sync Script
# Syncs local engram database to GitHub private repo for cross-device persistence.
# Usage: .\sync-memories.ps1
# Scheduled via Task Scheduler (Lara-MemorySync) every 30 minutes.

<#
.SYNOPSIS
    Sync engram memory database to engram-memories GitHub repo.
.DESCRIPTION
    Pulls latest from engram-memories, copies local engram DB files,
    commits and pushes. Logs all results to lara-diaries\sync.log.
.NOTES
    Compatible with Windows PowerShell 5.1 and PowerShell Core 7+.
#>

$ErrorActionPreference = "Stop"

# ── CONFIGURATION ─────────────────────────────
$engramRepo   = Join-Path $HOME "engram-memories"
$engramData   = Join-Path $env:LOCALAPPDATA "engram"
$logDir       = Join-Path $env:LOCALAPPDATA "lara-diaries"
$logFile      = Join-Path $logDir "sync.log"

# ── LOGGING ───────────────────────────────────
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

# ── MAIN SYNC LOGIC ───────────────────────────
function Sync-Memories {
    Write-Log "Sync Start"
    Write-Log "Repo: $engramRepo"
    Write-Log "Data: $engramData"

    if (-not (Test-Path -LiteralPath $engramRepo)) {
        Write-Log "Repo no encontrado en: $engramRepo" -Level "ERROR"
        Write-Log "Ejecuta el wizard de Lara Diaries para crearlo." -Level "ERROR"
        return $false
    }

    if (-not (Test-Path -LiteralPath $engramData)) {
        Write-Log "Directorio de datos engram no encontrado: $engramData" -Level "WARN"
        Write-Log "Puede que engram no este instalado o no haya generado datos aun." -Level "WARN"
        return $false
    }

    try {
        Push-Location $engramRepo
        Write-Log "Ejecutando git pull --rebase ..."

        $pullOutput = & git pull --rebase 2>&1
        $pullExit = $LASTEXITCODE

        if ($pullExit -ne 0) {
            $pullText = ($pullOutput | Out-String).Trim()
            Write-Log "git pull fallo (exit code: $pullExit)" -Level "ERROR"
            Write-Log "Output: $pullText" -Level "ERROR"

            if ($pullText -match "conflict|merge|CONFLICT") {
                Write-Log "CONFLICTO DETECTADO - abortando sync" -Level "ERROR"
                Write-Log "Resolve los conflictos manualmente en $engramRepo" -Level "ERROR"
                Pop-Location
                return $false
            }

            if ($pullText -match "no tracking" -or $pullText -match "No remote") {
                Write-Log "Repo sin upstream remoto aun. Es normal en la primera sync." -Level "WARN"
            } else {
                Pop-Location
                return $false
            }
        } else {
            Write-Log "git pull completado exitosamente."
        }

        $dbFiles = Get-ChildItem -Path $engramData -Filter "*.db" -ErrorAction SilentlyContinue
        if (-not $dbFiles) {
            Write-Log "No se encontraron archivos .db en $engramData" -Level "WARN"
            Pop-Location
            return $false
        }

        foreach ($db in $dbFiles) {
            $dest = Join-Path $engramRepo $db.Name
            Copy-Item -Path $db.FullName -Destination $dest -Force
            Write-Log "  Copiado: $($db.Name)"
        }

        $null = & git add .
        $addExit = $LASTEXITCODE
        if ($addExit -ne 0) {
            Write-Log "git add fallo (exit code: $addExit)" -Level "ERROR"
            Pop-Location
            return $false
        }

        $status = & git status --porcelain
        if (-not $status) {
            Write-Log "Sin cambios nuevos - nada que commitear."
            Pop-Location
            return $true
        }

        $dateStr = Get-Date -Format "yyyy-MM-dd HH:mm"
        $null = & git commit -m "sync: memories $dateStr"
        $commitExit = $LASTEXITCODE
        if ($commitExit -ne 0) {
            Write-Log "git commit fallo (exit code: $commitExit)" -Level "ERROR"
            Pop-Location
            return $false
        }
        Write-Log "Commit creado: sync: memories $dateStr"

        $null = & git push
        $pushExit = $LASTEXITCODE
        if ($pushExit -ne 0) {
            Write-Log "git push fallo (exit code: $pushExit)" -Level "ERROR"
            Pop-Location
            return $false
        }
        Write-Log "Push exitoso."

        Pop-Location
        Write-Log "[OK] Sync completada exitosamente."
        return $true

    } catch {
        Write-Log "Error inesperado durante sync: $_" -Level "ERROR"
        try { Pop-Location } catch {}
        return $false
    }
}

# ── ENTRY POINT ───────────────────────────────
$result = Sync-Memories
if ($result) { $syncStatus = "OK" } else { $syncStatus = "FAILED" }
Write-Log "Sync End ($syncStatus)"

if (-not $result) {
    exit 1
}
exit 0
