#!/usr/bin/env pwsh
# Lara Diaries - Windows Bootstrap
# Usage: .\bootstrap.ps1 [-Check] [-DryRun]
# Requires: PowerShell 5.1+ or PowerShell Core 7+

<#
.SYNOPSIS
    Lara Diaries bootstrap script for Windows.
.DESCRIPTION
    Checks for git, gh CLI, Node.js, winget, and guides through setup.

    -Check   : Only check prerequisites and report status. No installation.
    -DryRun  : Show what would be installed without making changes.
.NOTES
    Compatible with Windows PowerShell 5.1 and PowerShell Core 7+.
#>

param(
    [switch]$Check,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$script:IsDryRun = $DryRun
$script:IsCheckOnly = $Check

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

    $script:PrereqResults = @{
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
    foreach ($key in $script:PrereqResults.Keys) { if (-not $script:PrereqResults[$key]) { $count = $count + 1 } }
    if ($count -gt 0) {
        Write-Host "[!] Algunos prerequisitos no se pudieron instalar automaticamente." -ForegroundColor Yellow
        Write-Host "   Instalalos manualmente y volve a ejecutar este script.`n" -ForegroundColor Yellow
        return $false
    }
    Write-Host "[OK] Todos los prerequisitos estan en orden.`n" -ForegroundColor Green
    return $true
}

# ── CHECK MODE ────────────────────────────────
function Start-CheckOnly {
    Write-Host "`n  [CHECK MODE] Solo diagnostico - no se instalara nada.`n" -ForegroundColor Cyan

    if (-not $script:PrereqResults) {
        $null = Test-Prerequisites
    }

    Write-Host "`n  Resumen del check:" -ForegroundColor Cyan
    Write-Host "  git:  $(if ($script:PrereqResults['git'])  { 'OK' } else { 'FALTA' })" -ForegroundColor $(if ($script:PrereqResults['git'])  { 'Green' } else { 'Red' })
    Write-Host "  gh:   $(if ($script:PrereqResults['gh'])   { 'OK' } else { 'FALTA' })" -ForegroundColor $(if ($script:PrereqResults['gh'])   { 'Green' } else { 'Red' })
    Write-Host "  node: $(if ($script:PrereqResults['node']) { 'OK' } else { 'FALTA' })" -ForegroundColor $(if ($script:PrereqResults['node']) { 'Green' } else { 'Red' })
    $codeCmd = Get-Command "code" -ErrorAction SilentlyContinue
    Write-Host "  code: $(if ($codeCmd) { 'OK' } else { 'OPCIONAL' })" -ForegroundColor $(if ($codeCmd) { 'Green' } else { 'Yellow' })
    $opencodeCmd = Get-Command "opencode" -ErrorAction SilentlyContinue
    Write-Host "  opencode: $(if ($opencodeCmd) { 'OK' } else { 'FALTA - instalar primero' })" -ForegroundColor $(if ($opencodeCmd) { 'Green' } else { 'Red' })
    Write-Host "`n  Para instalar: ejecuta .\bootstrap.ps1 sin parametros." -ForegroundColor Cyan
    Write-Host "  Para simular:  ejecuta .\bootstrap.ps1 -DryRun`n" -ForegroundColor Cyan
}

# ── DRY-RUN MODE ──────────────────────────────
function Start-DryRun {
    Write-Host "`n  [DRY-RUN] Plan de instalacion - nada se modificara.`n" -ForegroundColor Cyan

    # Detectar estado de cada componente
    $gitOk     = Get-Command "git" -ErrorAction SilentlyContinue
    $ghOk      = Get-Command "gh" -ErrorAction SilentlyContinue
    $nodeOk    = Get-Command "node" -ErrorAction SilentlyContinue
    $codeOk    = Get-Command "code" -ErrorAction SilentlyContinue
    $engramOk  = Get-Command "engram" -ErrorAction SilentlyContinue
    $opencodeOk = Get-Command "opencode" -ErrorAction SilentlyContinue
    $gaDir     = Test-Path (Join-Path $HOME "gentle-ai")
    $skillsDir = Test-Path (Join-Path $env:APPDATA "opencode\skills\Gentleman-Skills")
    $ggaDir    = Test-Path (Join-Path $HOME "gentleman-guardian-angel")
    $ghUser    = & gh api user --jq .login 2>$null
    $engramRepo = Test-Path (Join-Path $HOME "engram-memories")
    $configRepo = Test-Path (Join-Path $HOME "opencode-config")

    Write-Host "  +------------------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  |               PLAN DE INSTALACION                    |" -ForegroundColor Cyan
    Write-Host "  +------------------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  | Prerequisites:                                       |" -ForegroundColor Cyan
    Write-Host "  |   git:       $(if ($gitOk) { 'OK' } else { 'FALTA' })                                         |"
    Write-Host "  |   gh:        $(if ($ghOk) { 'OK' } else { 'FALTA' })                                         |"
    Write-Host "  |   node:      $(if ($nodeOk) { 'OK' } else { 'FALTA' })                                         |"
    Write-Host "  |   opencode:  $(if ($opencodeOk) { 'OK' } else { 'FALTA - instalarlo primero' })                |"
    Write-Host "  |------------------------------------------------------|" -ForegroundColor Cyan
    Write-Host "  | Componentes a instalar/configurar:                    |" -ForegroundColor Cyan
    if ($gaDir)    { Write-Host "  |   [OK] Gentle AI (ya instalado)                              |" -ForegroundColor Green }
    else           { Write-Host "  |   [+] Gentle AI (pendiente)                                  |" -ForegroundColor Yellow }
    if ($skillsDir){ Write-Host "  |   [OK] Gentleman Skills (ya instalado)                        |" -ForegroundColor Green }
    else           { Write-Host "  |   [+] Gentleman Skills (pendiente)                            |" -ForegroundColor Yellow }
    if ($engramOk) { Write-Host "  |   [OK] Engram (ya instalado)                                  |" -ForegroundColor Green }
    else           { Write-Host "  |   [+] Engram (pendiente)                                      |" -ForegroundColor Yellow }
    if ($codeOk)   { Write-Host "  |   [OK] VSCode (ya instalado)                                  |" -ForegroundColor Green }
    else           { Write-Host "  |   [?] VSCode (opcional - recomendado)                         |" -ForegroundColor Yellow }
    if ($ggaDir)   { Write-Host "  |   [OK] GGA code review (ya instalado)                         |" -ForegroundColor Green }
    else           { Write-Host "  |   [?] GGA code review (opcional)                              |" -ForegroundColor Gray }
    Write-Host "  |------------------------------------------------------|" -ForegroundColor Cyan
    Write-Host "  | Repositorios GitHub:                                 |" -ForegroundColor Cyan
    if ($ghUser)   { Write-Host "  |   Usuario: $($ghUser.PadRight(44))|" }
    else           { Write-Host "  |   gh no autenticado - se pedira login                          |" -ForegroundColor Yellow }
    if ($engramRepo){Write-Host "  |   [OK] engram-memories (local)                                |" -ForegroundColor Green }
    else            {Write-Host "  |   [+] engram-memories (se creara)                              |" -ForegroundColor Yellow }
    if ($configRepo){Write-Host "  |   [OK] opencode-config (local)                                |" -ForegroundColor Green }
    else            {Write-Host "  |   [+] opencode-config (se creara)                             |" -ForegroundColor Yellow }
    Write-Host "  +------------------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  | Sync: cada 30 min via Task Scheduler                  |" -ForegroundColor Cyan
    Write-Host "  +------------------------------------------------------+" -ForegroundColor Cyan

    Write-Host "`n  [DRY-RUN] Simulacion completada. Nada se instalo ni modifico." -ForegroundColor Cyan
    Write-Host "  Para instalar de verdad, ejecuta .\bootstrap.ps1 sin parametros.`n" -ForegroundColor Cyan
}

# ── WIZARD MAIN ───────────────────────────────
function Start-WizardMain {
    if ($script:IsCheckOnly) { Start-CheckOnly; return }
    if ($script:IsDryRun) { Start-DryRun; return }

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

    # Check-only mode: skip prereq install, just report
    if ($script:IsCheckOnly) { Start-CheckOnly; return }

    # Dry-run mode: check prereqs but don't block on missing
    if ($script:IsDryRun) {
        if (-not $script:PrereqResults) { $null = Test-Prerequisites }
        Start-DryRun
        return
    }

    # Normal mode: prereqs must be satisfied
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
