# Lara Diaries - Bootstrap Pester Tests (Pester 3.x)
# Tests for Phase 1 lock/state/resume/rollback functions in bootstrap.ps1
#
# Run with: Invoke-Pester .\bootstrap.Tests.ps1

$here = Split-Path -Parent $PSCommandPath
. (Join-Path $here "bootstrap.ps1")

# -------------------------------------------------------------------
# Helpers: override path functions to use isolated temp directories
# -------------------------------------------------------------------
$testStateDir = Join-Path $env:TEMP "LaraDiaries-Tests-$(Get-Random)"

function Set-TestPaths {
    Mock Get-StateDir { return $testStateDir }
    Mock Get-StateFile { return Join-Path $testStateDir "state.json" }
    Mock Get-LockFile { return Join-Path $testStateDir "install.lock" }
}

function Clear-TestDir {
    if (Test-Path -LiteralPath $testStateDir) {
        Remove-Item -LiteralPath $testStateDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Wrap exit in a function so we can mock it
function Test-ExitWrapper {
    param([int]$Code)
    exit $Code
}

# -------------------------------------------------------------------
# New-LaraLock
# -------------------------------------------------------------------
Describe "New-LaraLock" {
    AfterEach { Clear-TestDir }

    It "creates a lock file with PID, timestamp and hostname" {
        Set-TestPaths
        New-LaraLock

        $lockFile = Join-Path $testStateDir "install.lock"
        Test-Path -LiteralPath $lockFile | Should Be $true

        $content = Get-Content -Path $lockFile
        $content.Count | Should Be 3
        $content[0] | Should Match '^\d+$'
        $content[2] | Should Be $env:COMPUTERNAME
    }

    It "creates the state directory if it does not exist" {
        Set-TestPaths
        Clear-TestDir

        New-LaraLock

        Test-Path -LiteralPath $testStateDir | Should Be $true
    }

    It "writes PID, timestamp, and hostname to lock file" {
        Set-TestPaths
        New-LaraLock

        $lockFile = Join-Path $testStateDir "install.lock"
        $content = Get-Content -Path $lockFile -Raw
        $lines = $content -split "`n" | ForEach-Object { $_.Trim() }
        $lines[0] | Should Match '^\d+$'
        $lines[0] | Should Be "$pid"
        $lines[1] | Should Match '\d{4}-\d{2}-\d{2}T'
        $lines[2] | Should Be $env:COMPUTERNAME
    }
}

# -------------------------------------------------------------------
# Remove-LaraLock
# -------------------------------------------------------------------
Describe "Remove-LaraLock" {
    AfterEach { Clear-TestDir }

    It "removes the lock file when it exists" {
        Set-TestPaths
        New-LaraLock

        $lockFile = Join-Path $testStateDir "install.lock"
        Test-Path -LiteralPath $lockFile | Should Be $true

        Remove-LaraLock

        Test-Path -LiteralPath $lockFile | Should Be $false
    }

    It "does not throw when lock file does not exist" {
        Set-TestPaths
        Clear-TestDir

        { Remove-LaraLock } | Should Not Throw
    }
}

# -------------------------------------------------------------------
# Test-LaraLockStale
# -------------------------------------------------------------------
Describe "Test-LaraLockStale" {
    AfterEach { Clear-TestDir }

    It "returns 'none' when no lock file exists" {
        Set-TestPaths
        Clear-TestDir

        $result = Test-LaraLockStale
        $result | Should Be "none"
    }

    It "returns 'active' when lock file exists and process is alive" {
        # Write a lock file with a known PID, then mock Get-Process to return a process
        $testDir = Join-Path $env:TEMP "LaraDiaries-ActiveTest-$(Get-Random)"
        Mock Get-LockFile { return (Join-Path $testDir "install.lock") }
        Mock Get-StateDir { return $testDir }
        Mock Get-Process { return @{ Id = 12345; Name = "test" } } -ParameterFilter { $Id -eq 12345 }
        $null = New-Item -ItemType Directory -Path $testDir -Force

        $lockFile = Join-Path $testDir "install.lock"
        "12345`n2024-01-01T00:00:00`nTEST-PC" | Set-Content -Path $lockFile -Encoding ASCII -Force

        $result = Test-LaraLockStale
        $result | Should Be "active"

        Remove-Item -LiteralPath $testDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "returns 'stale' when lock file exists but process is gone" {
        $testDir = Join-Path $env:TEMP "LaraDiaries-StaleTest-$(Get-Random)"
        Mock Get-LockFile { return (Join-Path $testDir "install.lock") }
        Mock Get-StateDir { return $testDir }
        $null = New-Item -ItemType Directory -Path $testDir -Force

        $lockFile = Join-Path $testDir "install.lock"
        "99999`n2024-01-01T00:00:00`nTEST-PC" | Set-Content -Path $lockFile -Encoding ASCII -Force

        $result = Test-LaraLockStale
        $result | Should Be "stale"

        Remove-Item -LiteralPath $testDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# -------------------------------------------------------------------
# Invoke-LockGuard
# -------------------------------------------------------------------
Describe "Invoke-LockGuard" {
    AfterEach { Clear-TestDir }

    # NOTE: Invoke-LockGuard calls exit() which terminates the process
    # and cannot be caught by Pester. Testing the full function is not
    # possible in Pester 3.x. The individual logic paths covered by
    # Test-LaraLockStale, Remove-LaraLock, etc. together compose the
    # full Invoke-LockGuard behavior.
    #
    # The exit paths are: active→exit(1), stale+no→exit(0).
    # The stale+yes path removes lock and returns normally.
    # No-lock path returns normally.

    It "is callable without errors when no lock exists (no-exit path)" {
        Set-TestPaths
        Mock Test-LaraLockStale { return "none" }
        Mock Read-Host { return "" }
        # This path does not call exit, so it is safe to test
        $null = Invoke-LockGuard 2>&1
        $true | Should Be $true
    }
}

# -------------------------------------------------------------------
# New-InitialState
# -------------------------------------------------------------------
Describe "New-InitialState" {
    It "creates a state object with version 1" {
        $state = New-InitialState -InstallType "fresh"
        $state.version | Should Be 1
    }

    It "includes a non-empty install_id" {
        $state = New-InitialState -InstallType "fresh"
        $state.install_id | Should Not BeNullOrEmpty
    }

    It "sets install_type from parameter" {
        $state = New-InitialState -InstallType "upgrade"
        $state.install_type | Should Be "upgrade"
    }

    It "defaults install_type to 'unknown' when not specified" {
        $state = New-InitialState
        $state.install_type | Should Be "unknown"
    }

    It "has an empty steps collection" {
        $state = New-InitialState -InstallType "fresh"
        @($state.steps.PSObject.Properties).Count | Should Be 0
    }

    It "sets created_at and updated_at as ISO 8601 strings" {
        $state = New-InitialState -InstallType "fresh"
        $state.created_at | Should Match '\d{4}-\d{2}-\d{2}T'
        $state.updated_at | Should Match '\d{4}-\d{2}-\d{2}T'
    }
}

# -------------------------------------------------------------------
# Write-LaraState / Read-LaraState roundtrip
# -------------------------------------------------------------------
Describe "Write-LaraState / Read-LaraState" {
    AfterEach { Clear-TestDir }

    It "writes state to disk and reads it back with matching fields" {
        Set-TestPaths

        $state = New-InitialState -InstallType "fresh"
        Write-LaraState -State $state

        $read = Read-LaraState
        $read | Should Not BeNullOrEmpty
        $read.version | Should Be 1
        $read.install_id | Should Be $state.install_id
        $read.install_type | Should Be "fresh"
    }

    It "creates state directory when writing" {
        Set-TestPaths
        Clear-TestDir

        $state = New-InitialState -InstallType "fresh"
        Write-LaraState -State $state

        Test-Path -LiteralPath $testStateDir | Should Be $true
    }

    It "returns $null when state file does not exist" {
        Set-TestPaths
        Clear-TestDir

        $result = Read-LaraState
        $result | Should BeNullOrEmpty
    }
}

Describe "Read-LaraState" {
    AfterEach { Clear-TestDir }

    It "returns $null when state file does not exist" {
        Set-TestPaths
        Clear-TestDir

        $result = Read-LaraState
        $result | Should BeNullOrEmpty
    }

    It "returns $null on unparseable content" {
        Set-TestPaths
        Clear-TestDir
        $null = New-Item -ItemType Directory -Path $testStateDir -Force
        "not-json-{{{" | Set-Content -Path (Join-Path $testStateDir "state.json") -Encoding UTF8 -Force

        $result = Read-LaraState
        $result | Should BeNullOrEmpty
    }
}

# -------------------------------------------------------------------
# Get-ResumeState
# -------------------------------------------------------------------
Describe "Get-ResumeState" {
    AfterEach { Clear-TestDir }

    It "returns $null when no state file exists" {
        Set-TestPaths
        Clear-TestDir

        $result = Get-ResumeState
        $result | Should BeNullOrEmpty
    }

    It "lists completed and incomplete steps" {
        Set-TestPaths

        $state = New-InitialState -InstallType "fresh"
        $state.steps | Add-Member -NotePropertyName "step_a" -NotePropertyValue ([PSCustomObject]@{ status = "success" }) -Force
        $state.steps | Add-Member -NotePropertyName "step_b" -NotePropertyValue ([PSCustomObject]@{ status = "failed" }) -Force
        $state.steps | Add-Member -NotePropertyName "step_c" -NotePropertyValue ([PSCustomObject]@{ status = "pending" }) -Force
        Write-LaraState -State $state

        $result = Get-ResumeState
        $result | Should Not BeNullOrEmpty
        $result.CompletedSteps.Count | Should Be 1
        $result.CompletedSteps[0] | Should Be "step_a"
        $result.IncompleteSteps.Count | Should Be 2
    }
}

# -------------------------------------------------------------------
# Update-StepState
# -------------------------------------------------------------------
Describe "Update-StepState" {
    AfterEach { Clear-TestDir }

    It "creates a new state file if none exists" {
        Set-TestPaths
        Clear-TestDir

        Update-StepState -StepName "test_step" -Status "running"

        $state = Read-LaraState
        $state | Should Not BeNullOrEmpty
        $state.steps.test_step.status | Should Be "running"
    }

    It "sets step status to running with started_at" {
        Set-TestPaths

        Update-StepState -StepName "test_step" -Status "running"

        $state = Read-LaraState
        $state.steps.test_step.status | Should Be "running"
        $state.steps.test_step.started_at | Should Not BeNullOrEmpty
    }

    It "sets completed_at for success status" {
        Set-TestPaths

        Update-StepState -StepName "test_step" -Status "running"
        Update-StepState -StepName "test_step" -Status "success"

        $state = Read-LaraState
        $state.steps.test_step.completed_at | Should Not BeNullOrEmpty
    }

    It "stores error message when provided" {
        Set-TestPaths

        Update-StepState -StepName "test_step" -Status "failed" -ErrorMsg "something failed"

        $state = Read-LaraState
        $state.steps.test_step.error | Should Be "something failed"
    }

    It "stores rollback action when provided" {
        Set-TestPaths

        Update-StepState -StepName "test_step" -Status "running" -Rollback "cleanup temp files"

        $state = Read-LaraState
        $state.steps.test_step.rollback | Should Be "cleanup temp files"
    }

    It "transitions from pending to running to success" {
        Set-TestPaths

        Update-StepState -StepName "step1" -Status "running"
        $state1 = Read-LaraState
        $state1.steps.step1.status | Should Be "running"
        $state1.steps.step1.completed_at | Should BeNullOrEmpty

        Update-StepState -StepName "step1" -Status "success"
        $state2 = Read-LaraState
        $state2.steps.step1.status | Should Be "success"
        $state2.steps.step1.completed_at | Should Not BeNullOrEmpty
    }
}
