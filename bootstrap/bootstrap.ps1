#!/usr/bin/env pwsh
# Lara Diaries - Windows Bootstrap
# Usage: .\bootstrap.ps1
# Requires: PowerShell 5.1+ or PowerShell Core 7+

<#
.SYNOPSIS
    Lara Diaries bootstrap script for Windows.
.DESCRIPTION
    Checks for git, gh CLI, Node.js, winget, and guides through setup.
.NOTES
    Compatible with Windows PowerShell 5.1 and PowerShell Core 7+.
#>

$ErrorActionPreference = "Stop"

# ── BANNER ────────────────────────────────────
function Show-Banner {
    Clear-Host
    Write-Host "  +-----------------------------------------+" -ForegroundColor Cyan
    Write-Host "  |                                         |" -ForegroundColor Cyan
    Write-Host "  |      LARA DIARIES BOOTSTRAP             |" -ForegroundColor Cyan
    Write-Host "  |            v1.0.0                       |" -ForegroundColor Cyan
    Write-Host "  |                                         |" -ForegroundColor Cyan
    Write-Host "  |  Tu asistente siempre te espera.        |" -ForegroundColor Cyan
    Write-Host "  |                                         |" -ForegroundColor Cyan
    Write-Host "  +-----------------------------------------+" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Sistema de bootstrap para opencode + Gentle AI" -ForegroundColor Cyan
    Write-Host ""
}

# ── OS DETECTION ──────────────────────────────
function Test-WindowsOS {
    $os = [Environment]::OSVersion
    $isWindows = ($os.Platform -eq [System.PlatformID]::Win32NT)
    if (-not $isWindows) {
        Write-Host "[FAIL] Este script es para Windows. Detectado: $($os.ToString())" -ForegroundColor Red
        Write-Host "  Usa bootstrap.sh para Linux/macOS." -ForegroundColor Yellow
        return $false
    }
    Write-Host "[OK] Sistema operativo: Windows $($os.VersionString)" -ForegroundColor Green
    return $true
}

# ── ADMIN CHECK ───────────────────────────────
function Test-AdminRights {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "[!] No estas ejecutando como Administrador." -ForegroundColor Yellow
        Write-Host "    Algunas instalaciones (winget) podrian fallar." -ForegroundColor Yellow
        Write-Host "    Sugerencia: Ejecuta PowerShell como Administrador." -ForegroundColor Yellow
        Write-Host ""
    } else {
        Write-Host "[OK] Ejecutando como Administrador" -ForegroundColor Green
    }
    return $isAdmin
}

# ── PREREQUISITE CHECK ────────────────────────
function Test-Prerequisite {
    param([string]$Name, [string]$WinGetId, [string]$DownloadUrl)

    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) {
        $version = & $Name --version 2>$null
        if (-not $version) { $version = "(version desconocida)" }
        Write-Host "  [OK] $Name encontrado: $version" -ForegroundColor Green
        return $true
    }

    Write-Host "  [FAIL] $Name NO encontrado" -ForegroundColor Red

    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        Write-Host "    Instalando con winget: $WinGetId ..." -ForegroundColor Yellow
        try {
            $null = & winget install --id $WinGetId --accept-source-agreements --accept-package-agreements 2>&1
            $cmd = Get-Command $Name -ErrorAction SilentlyContinue
            if ($cmd) {
                Write-Host "    [OK] $Name instalado correctamente" -ForegroundColor Green
                return $true
            } else {
                Write-Host "    [!] La instalacion de $Name podria no haber funcionado." -ForegroundColor Red
                Write-Host "     Descargalo manualmente: $DownloadUrl" -ForegroundColor Yellow
                return $false
            }
        } catch {
            Write-Host "    [!] Error al instalar $Name con winget: $_" -ForegroundColor Red
            Write-Host "     Descargalo manualmente: $DownloadUrl" -ForegroundColor Yellow
            return $false
        }
    } else {
        Write-Host "    winget no esta disponible." -ForegroundColor Yellow
        Write-Host "    Descargalo manualmente: $DownloadUrl" -ForegroundColor Yellow
        return $false
    }
}

function Test-Prerequisites {
    Write-Host "`n  Verificando prerequisitos..." -ForegroundColor Cyan
    Write-Host ""

    $results = @{
        git  = Test-Prerequisite -Name "git"  -WinGetId "Git.Git"           -DownloadUrl "https://git-scm.com/downloads/win"
        gh   = Test-Prerequisite -Name "gh"   -WinGetId "GitHub.cli"        -DownloadUrl "https://cli.github.com/"
        node = Test-Prerequisite -Name "node" -WinGetId "OpenJS.NodeJS.LTS" -DownloadUrl "https://nodejs.org/"
    }

    # VSCode is optional — check but don't fail if missing
    $codeCmd = Get-Command "code" -ErrorAction SilentlyContinue
    if ($codeCmd) {
        Write-Host "  [OK] VSCode encontrado" -ForegroundColor Green
    } else {
        Write-Host "  [!] VSCode no encontrado (opcional, se instalara en el wizard)" -ForegroundColor Yellow
    }

    Write-Host ""
    $count = 0
    foreach ($key in $results.Keys) { if (-not $results[$key]) { $count = $count + 1 } }
    if ($count -gt 0) {
        Write-Host "[!] Algunos prerequisitos no se pudieron instalar automaticamente." -ForegroundColor Yellow
        Write-Host "   Instalalos manualmente y volve a ejecutar este script.`n" -ForegroundColor Yellow
        return $false
    }
    Write-Host "[OK] Todos los prerequisitos estan en orden.`n" -ForegroundColor Green
    return $true
}

# ── WIZARD MAIN ───────────────────────────────
function Start-WizardMain {
    Write-Host "Queres que proceda con la configuracion completa de Lara Diaries?" -ForegroundColor Magenta
    $confirm = Read-Host "  (S/N, predeterminado: S)"

    $shouldProceed = $true
    if ($confirm -ne "") {
        if ($confirm -notlike "S*" -and $confirm -notlike "s*") {
            $shouldProceed = $false
        }
    }
    if (-not $shouldProceed) {
        Write-Host "`n  Bueno, cuando quieras estoy aca." -ForegroundColor Cyan
        Write-Host "  Ejecuta bootstrap.ps1 de nuevo cuando estes listx.`n" -ForegroundColor Cyan
        exit 0
    }

    $wizardCore = Join-Path $PSScriptRoot "..\modules\wizard-core.ps1"
    $resolvedPath = Resolve-Path $wizardCore -ErrorAction Stop
    . $resolvedPath
    Start-Wizard
}

# ── ENTRY POINT ───────────────────────────────
function Main {
    Show-Banner
    if (-not (Test-WindowsOS)) { exit 1 }
    $null = Test-AdminRights
    if (-not (Test-Prerequisites)) {
        Write-Host "Resolve los prerequisitos faltantes y volve a ejecutar el script.`n" -ForegroundColor Yellow
        exit 1
    }
    Start-WizardMain
}

# Run only if not dot-sourced
if ($MyInvocation.InvocationName -ne '.') {
    Main
}
