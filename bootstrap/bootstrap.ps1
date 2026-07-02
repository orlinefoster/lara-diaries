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
    Write-Host "[!] Falling back to script-based wizard..." -ForegroundColor Yellow

    $wizardCore = Join-Path $PSScriptRoot "..\modules\wizard-core.ps1"
    $resolvedPath = Resolve-Path $wizardCore -ErrorAction SilentlyContinue

    if (-not $resolvedPath) {
        Write-Host "[FAIL] wizard-core.ps1 not found at $wizardCore" -ForegroundColor Red
        Write-Host "  Make sure you are running from the full lara-diaries repository." -ForegroundColor Yellow
        exit 1
    }

    . $resolvedPath
    Start-Wizard
}

# ---- MAIN ----
$binaryPath = Get-BinaryPath

if (Test-Path -LiteralPath $binaryPath) {
    Write-Host "[OK] lara-installer binary found. Running..." -ForegroundColor Green
    & $binaryPath @args
    exit $LASTEXITCODE
}

# Binary not found: attempt download
Write-Host "[..] lara-installer not found at $binaryPath" -ForegroundColor Yellow
$installed = Install-Binary

if (-not $installed) {
    Start-FallbackWizard
    exit $LASTEXITCODE
}

# Run the freshly installed binary
& $binaryPath @args
exit $LASTEXITCODE
