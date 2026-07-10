#!/usr/bin/env pwsh
# Lara Diaries - Windows Bootstrap
# Usage: .\bootstrap.ps1 [install|doctor|--version]
# Downloads and runs the lara-installer binary, with fallback to wizard-core.

$ErrorActionPreference = "Stop"

# Configurable binary download URL (override via env var)
$script:BinaryBaseUrl = if ($env:LARA_INSTALLER_BASE_URL) {
    $env:LARA_INSTALLER_BASE_URL
} else {
    "https://github.com/orlinefoster/lara-diaries/releases/latest/download"
}

$script:Version = "0.1.0"
$script:BinDir = Join-Path $env:LOCALAPPDATA "LaraDiaries\bin"

function Get-BinaryName {
    $arch = $env:PROCESSOR_ARCHITECTURE
    if ($arch -eq 'ARM64') {
        return "lara-installer-windows-arm64.exe"
    }
    return "lara-installer-windows-amd64.exe"
}

function Get-BinaryPath {
    return Join-Path $script:BinDir "lara-installer.exe"
}

function Install-Binary {
    $binaryName = Get-BinaryName
    $binaryPath = Get-BinaryPath
    $binDir = $script:BinDir

    Write-Host "[..] Downloading lara-installer v$($script:Version)..." -ForegroundColor Cyan
    $url = "$($script:BinaryBaseUrl)/$binaryName"
    $tempFile = Join-Path $env:TEMP $binaryName

    try {
        Invoke-WebRequest -Uri $url -OutFile $tempFile -UseBasicParsing -ErrorAction Stop
    } catch {
        Write-Host "[!] Download failed: $_" -ForegroundColor Yellow
        return $false
    }

    # Verify SHA256 if checksum file is available
    $checksumUrl = "$($script:BinaryBaseUrl)/$binaryName.sha256"
    try {
        $checksumContent = (Invoke-WebRequest -Uri $checksumUrl -UseBasicParsing -ErrorAction Stop).Content.Trim()
        $expectedHash = $checksumContent.Split(' ')[0]
        $actualHash = (Get-FileHash -LiteralPath $tempFile -Algorithm SHA256).Hash.ToLower()
        if ($actualHash -ne $expectedHash.ToLower()) {
            Write-Host "[!] SHA256 checksum mismatch." -ForegroundColor Red
            Write-Host "  Expected: $expectedHash" -ForegroundColor Red
            Write-Host "  Got:      $actualHash" -ForegroundColor Red
            Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
            return $false
        }
        Write-Host "[OK] Checksum verified." -ForegroundColor Green
    } catch {
        Write-Host "[!] No checksum file available, skipping verification." -ForegroundColor Yellow
    }

    # Move binary to bin dir
    if (-not (Test-Path -LiteralPath $binDir)) {
        $null = New-Item -ItemType Directory -Path $binDir -Force -ErrorAction Stop
    }
    try {
        Move-Item -LiteralPath $tempFile -Destination $binaryPath -Force -ErrorAction Stop
    } catch {
        Write-Host "[!] Could not move binary to $binDir : $_" -ForegroundColor Yellow
        return $false
    }

    Write-Host "[OK] Binary installed to $binaryPath" -ForegroundColor Green
    return $true
}

function Start-FallbackWizard {
    param(
        [string]$NonInteractive = $null,
        [switch]$CheckOnly,
        [switch]$DryRun
    )

    $wizardCore = Join-Path $PSScriptRoot "..\modules\wizard-core.ps1"
    $resolvedPath = Resolve-Path $wizardCore -ErrorAction SilentlyContinue

    if (-not $resolvedPath) {
        Write-Host "[FAIL] wizard-core.ps1 not found at $wizardCore" -ForegroundColor Red
        Write-Host "  Make sure you are running from the full lara-diaries repository." -ForegroundColor Yellow
        exit 1
    }

    . $resolvedPath

    if ($NonInteractive) {
        Write-Host "[!] Running non-interactive install from JSON config..." -ForegroundColor Yellow
        $null = Start-NonInteractiveWizard -ConfigJson $NonInteractive
    } elseif ($CheckOnly) {
        Write-Host "[!] Check mode not available in script fallback." -ForegroundColor Yellow
        Write-Host "  Install the lara-installer binary and use: lara-installer doctor" -ForegroundColor Yellow
    } elseif ($DryRun) {
        Write-Host "[!] Dry-run mode not available in script fallback." -ForegroundColor Yellow
        Write-Host "  Run without -DryRun for interactive installation." -ForegroundColor Yellow
    } else {
        Write-Host "[!] Falling back to script-based wizard..." -ForegroundColor Yellow
        Start-Wizard
    }
}

# ── PHASE 1: LOCK & STATE ─────────────────────
# These functions mirror the Go lara-installer state+lock logic,
# providing state.json management directly from PowerShell.
# They are used by the interactive wizard and independently when
# the Go binary is unavailable.

function Get-StateDir {
    return Join-Path $env:LOCALAPPDATA "LaraDiaries"
}

function Get-StateFile {
    return Join-Path (Get-StateDir) "state.json"
}

function Get-LockFile {
    return Join-Path (Get-StateDir) "install.lock"
}

function New-LaraLock {
    <#
    .SYNOPSIS
        Creates an install lock file at the state directory.
        Writes PID, timestamp, and hostname for staleness checks.
    .EXAMPLE
        New-LaraLock
    #>
    $lockFile = Get-LockFile
    $lockDir = Split-Path $lockFile -Parent
    if (-not (Test-Path -LiteralPath $lockDir)) {
        $null = New-Item -ItemType Directory -Path $lockDir -Force -ErrorAction Stop
    }
    $content = "$pid`n$(Get-Date -Format 'o')`n$env:COMPUTERNAME"
    Set-Content -Path $lockFile -Value $content -Encoding ASCII -Force -ErrorAction Stop
}

function Remove-LaraLock {
    <#
    .SYNOPSIS
        Removes the install lock file. No error if file does not exist.
    .EXAMPLE
        Remove-LaraLock
    #>
    $lockFile = Get-LockFile
    if (Test-Path -LiteralPath $lockFile) {
        Remove-Item -LiteralPath $lockFile -Force -ErrorAction SilentlyContinue
    }
}

function Test-LaraLockStale {
    <#
    .SYNOPSIS
        Checks the status of the lock file.
    .DESCRIPTION
        Returns "none" if no lock file exists, "active" if the
        owning process is alive, or "stale" if the process is gone.
    .EXAMPLE
        Test-LaraLockStale
    #>
    $lockFile = Get-LockFile
    if (-not (Test-Path -LiteralPath $lockFile)) {
        return "none"
    }
    try {
        $firstLine = Get-Content -Path $lockFile -TotalCount 1 -ErrorAction Stop
        $lockPid = [int]::Parse($firstLine.Trim())
        $proc = Get-Process -Id $lockPid -ErrorAction SilentlyContinue
        if ($proc) {
            return "active"
        }
        return "stale"
    } catch {
        return "stale"
    }
}

function Invoke-LockGuard {
    <#
    .SYNOPSIS
        Guards install execution against concurrent or stale locks.
    .DESCRIPTION
        If lock is active, exits with error. If stale, prompts user
        to remove or abort. Called at the start of runInstall.
    .EXAMPLE
        Invoke-LockGuard
    #>
    $status = Test-LaraLockStale
    switch ($status) {
        "active" {
            Write-Host "[FAIL] Another installation is already in progress." -ForegroundColor Red
            exit 1
        }
        "stale" {
            Write-Host "[!] Stale lock file detected." -ForegroundColor Yellow
            $answer = Read-Host "  Remove it and continue? [y/N]"
            if ($answer -match "^(y|yes)$") {
                Remove-LaraLock
                Write-Host "[OK] Lock removed." -ForegroundColor Green
            } else {
                Write-Host "[OK] Exiting."
                exit 0
            }
        }
    }
}

function New-InitialState {
    <#
    .SYNOPSIS
        Creates a fresh state object for a new installation.
    .PARAMETER InstallType
        Type of install: "fresh", "upgrade", or custom string.
    .EXAMPLE
        New-InitialState -InstallType "fresh"
    #>
    param([string]$InstallType = "unknown")
    $now = Get-Date -Format "o"
    return [PSCustomObject]@{
        version      = 1
        install_id   = [guid]::NewGuid().ToString()
        created_at   = $now
        updated_at   = $now
        install_type = $InstallType
        steps        = [PSCustomObject]@{}
    }
}

function Write-LaraState {
    <#
    .SYNOPSIS
        Serializes a state object to state.json.
    .PARAMETER State
        The state PSCustomObject to persist.
    .EXAMPLE
        Write-LaraState -State $myState
    #>
    param([PSCustomObject]$State)
    $stateDir = Get-StateDir
    if (-not (Test-Path -LiteralPath $stateDir)) {
        $null = New-Item -ItemType Directory -Path $stateDir -Force -ErrorAction Stop
    }
    $State.updated_at = (Get-Date -Format "o")
    $json = $State | ConvertTo-Json -Compress
    Set-Content -Path (Get-StateFile) -Value $json -Encoding UTF8 -Force -ErrorAction Stop
}

function Read-LaraState {
    <#
    .SYNOPSIS
        Reads and deserializes state.json.
    .DESCRIPTION
        Returns $null if the file does not exist or is unparseable.
    .EXAMPLE
        $state = Read-LaraState
    #>
    $stateFile = Get-StateFile
    if (-not (Test-Path -LiteralPath $stateFile)) {
        return $null
    }
    try {
        $content = Get-Content -Path $stateFile -Raw -Encoding UTF8 -ErrorAction Stop
        if (-not $content) { return $null }
        return $content | ConvertFrom-Json -ErrorAction Stop
    } catch {
        return $null
    }
}

function Get-ResumeState {
    <#
    .SYNOPSIS
        Reads state and returns resume metadata: completed/incomplete steps.
    .EXAMPLE
        $resume = Get-ResumeState
        if ($resume) { $resume.CompletedSteps }
    #>
    $state = Read-LaraState
    if (-not $state) { return $null }
    $stepNames = if ($state.steps) { $state.steps.PSObject.Properties.Name } else { @() }
    $completedSteps = @()
    $incompleteSteps = @()
    foreach ($name in $stepNames) {
        $step = $state.steps.$name
        if ($step.status -eq "success") {
            $completedSteps += $name
        } else {
            $incompleteSteps += $name
        }
    }
    return [PSCustomObject]@{
        State            = $state
        CompletedSteps   = $completedSteps
        IncompleteSteps  = $incompleteSteps
    }
}

function Update-StepState {
    <#
    .SYNOPSIS
        Updates the status of a single installation step in state.json.
    .PARAMETER StepName
        Unique step identifier (e.g. "github_login").
    .PARAMETER Status
        One of: pending, running, success, failed, skipped.
    .PARAMETER ErrorMsg
        Optional error detail for failed steps.
    .PARAMETER Rollback
        Optional rollback action description.
    .EXAMPLE
        Update-StepState -StepName "github_login" -Status "running"
        Update-StepState -StepName "clone_repo" -Status "failed" -ErrorMsg "Network timeout"
    #>
    param(
        [string]$StepName,
        [string]$Status,
        [string]$ErrorMsg = $null,
        [string]$Rollback = $null
    )
    $state = Read-LaraState
    if (-not $state) {
        $state = New-InitialState -InstallType "unknown"
    }
    $now = (Get-Date -Format "o")
    if (-not $state.steps.$StepName) {
        $state.steps | Add-Member -NotePropertyName $StepName -NotePropertyValue ([PSCustomObject]@{
            status       = "pending"
            started_at   = $null
            completed_at = $null
            error        = $null
            rollback     = $null
        }) -Force
    }
    $state.steps.$StepName.status = $Status
    if ($Status -eq "running" -and -not $state.steps.$StepName.started_at) {
        $state.steps.$StepName.started_at = $now
    }
    if ($Status -in @("success","failed","skipped")) {
        $state.steps.$StepName.completed_at = $now
    }
    if ($ErrorMsg) { $state.steps.$StepName.error = $ErrorMsg }
    if ($Rollback) { $state.steps.$StepName.rollback = $Rollback }
    Write-LaraState -State $state
}

# ---- FALLBACK PATH ----
# The functions below (Install-Binary, Start-FallbackWizard) implement
# the fallback download-and-run strategy. When the Go binary is not
# found, bootstrap.ps1 downloads it from GitHub Releases. If the
# download fails, it falls back to the script-based wizard-core.ps1.
# This two-phase hybrid ensures operation even without network access
# to the release artifacts.

# Guard: skip MAIN when dot-sourced for testing (Pester)
if ($MyInvocation.InvocationName -ne '.') {
    # ---- PARSE FLAGS ----
    $nonInteractive = $null
    $checkOnly = $false
    $dryRun = $false
    $goArgs = @()

    $i = 0
    while ($i -lt $args.Count) {
        $arg = $args[$i]
        switch -Regex ($arg) {
            '^--non-interactive$' {
                $i++
                if ($i -lt $args.Count) { $nonInteractive = $args[$i] }
            }
            '^--check$|^-c$'      { $checkOnly = $true }
            '^--dry-run$|^-n$'    { $dryRun = $true }
            '^--help$|^-h$' {
                Write-Host @"
Usage: .\bootstrap.ps1 [--check|--dry-run|--non-interactive <json>|install|doctor|--version]

  install           Run the full installer (default)
  doctor            System health check (if binary available)
  --version         Show version
  --check, -c       Diagnose system state without installing
  --dry-run, -n     Show installation plan without changes
  --non-interactive AI-driven install from JSON config
  --help, -h        Show this help
"@
                exit 0
            }
            default {
                # Subcommands for the Go binary
                if ($arg -in @('doctor', 'install', '--version')) {
                    $goArgs += $arg
                }
            }
        }
        $i++
    }

    # ---- MAIN ----
    # On Windows, the Go binary is primarily useful for doctor/check mode
    # (doesn't need wizard-core.sh for that). Install-mode always uses
    # the PowerShell wizard directly (bootstrap.ps1 is the proper entry point).

    $binaryPath = Get-BinaryPath
    $binaryAvailable = Test-Path -LiteralPath $binaryPath

    # doctor and --check → use Go binary if available, otherwise PS fallback
    if ($goArgs -contains "doctor") {
        if ($binaryAvailable) {
            Write-Host "[OK] Running lara-installer doctor..." -ForegroundColor Green
            & $binaryPath doctor
            exit $LASTEXITCODE
        }
        Write-Host "[!] lara-installer binary not found." -ForegroundColor Yellow
        Write-Host "  Download from: https://github.com/orlinefoster/lara-diaries/releases" -ForegroundColor Yellow
        exit 1
    }

    # --check and --dry-run → shell fallback (status report)
    if ($checkOnly -or $dryRun -or $nonInteractive) {
        Start-FallbackWizard -NonInteractive $nonInteractive -CheckOnly:$checkOnly -DryRun:$dryRun
        exit $LASTEXITCODE
    }

    # Interactive install: use PowerShell wizard directly
    Start-FallbackWizard
}
