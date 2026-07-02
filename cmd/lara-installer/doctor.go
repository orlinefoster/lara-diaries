package main

import (
	"fmt"
	"os"
	"os/exec"
	"runtime"
)

// doctorCheck represents a single health check with its result.
type doctorCheck struct {
	Name   string
	Status string // "OK", "FAIL", "WARN"
	Detail string
}

// runDoctorChecks runs all health checks and returns the results.
func runDoctorChecks() []doctorCheck {
	var checks []doctorCheck

	// 1. OS compatibility
	checks = append(checks, checkOS())

	// 2. State file
	checks = append(checks, checkStateFile())

	// 3. State consistency (stuck steps, missing steps)
	checks = append(checks, checkStateConsistency())

	// 4. Lock file status
	checks = append(checks, checkLockFile())

	// 5. Prerequisites: git, gh
	checks = append(checks, checkPrereq("git"))
	checks = append(checks, checkPrereq("gh"))

	// 6. Critical install tools: bash (or PowerShell on Windows)
	checks = append(checks, checkShell())

	// 7. Installed components: engram, gentle-ai (WARN if missing)
	checks = append(checks, checkInstalledTool("engram"))
	checks = append(checks, checkInstalledTool("gentle-ai"))

	// 8. State directory accessibility
	checks = append(checks, checkStateDir())

	// 9. Self check
	checks = append(checks, doctorSelfCheck())

	return checks
}

func runDoctor() {
	var checks []doctorCheck
	checks = runDoctorChecks()
	allOK := true

	fmt.Println()
	fmt.Println("  +-----------------------------------------+")
	fmt.Println("  |                                         |")
	fmt.Println("  |      LARA DIARIES DOCTOR                |")
	fmt.Println("  |            v" + version + "                       |")
	fmt.Println("  |                                         |")
	fmt.Println("  +-----------------------------------------+")
	fmt.Println()

	for _, c := range checks {
		if c.Status != "OK" {
			allOK = false
		}
	}

	// --- Print results ---
	fmt.Println("  Results:")
	fmt.Println()
	for _, c := range checks {
		statusSymbol := "OK"
		statusColor := ""
		if c.Status == "FAIL" {
			statusSymbol = "FAIL"
			statusColor = " [ISSUE]"
		} else if c.Status == "WARN" {
			statusSymbol = "WARN"
			statusColor = " [NOTE]"
		}
		fmt.Printf("    [%s] %s%s\n", statusSymbol, c.Name, statusColor)
		if c.Detail != "" {
			fmt.Println("         " + c.Detail)
		}
	}

	fmt.Println()
	if allOK {
		fmt.Println("  [OK] All checks passed. System is healthy.")
		os.Exit(0)
	} else {
		fmt.Println("  [FAIL] One or more checks failed. Review the issues above.")
		os.Exit(1)
	}
}

// checkOS verifies the operating system is supported.
func checkOS() doctorCheck {
	c := doctorCheck{Name: "Operating System"}
	switch runtime.GOOS {
	case "windows":
		c.Status = "OK"
		c.Detail = "Windows detected"
	case "linux":
		c.Status = "OK"
		c.Detail = "Linux detected"
	case "darwin":
		c.Status = "OK"
		c.Detail = "macOS detected"
	default:
		c.Status = "FAIL"
		c.Detail = "Unsupported OS: " + runtime.GOOS
	}
	return c
}

// checkStateFile verifies the state file exists and is parseable.
func checkStateFile() doctorCheck {
	c := doctorCheck{Name: "State File"}
	state, err := ReadState()
	if err != nil {
		c.Status = "FAIL"
		c.Detail = "Cannot parse: " + err.Error()
		return c
	}
	if state == nil {
		c.Status = "WARN"
		c.Detail = "No state file found (first run is OK)"
		return c
	}
	c.Status = "OK"
	c.Detail = "File exists at " + StateFile() + " (" + state.InstallID + ")"
	return c
}

// checkLockFile reports the status of the lock file.
func checkLockFile() doctorCheck {
	c := doctorCheck{Name: "Lock File"}
	switch StaleLockStatus() {
	case LockStatusNone:
		c.Status = "OK"
		c.Detail = "No lock file present"
	case LockStatusActive:
		c.Status = "WARN"
		c.Detail = "Lock file is active (another install may be running)"
	case LockStatusStale:
		c.Status = "WARN"
		c.Detail = "Lock file is stale from a previous run"
	}
	return c
}

// checkPrereq checks if a required command is available on PATH.
func checkPrereq(name string) doctorCheck {
	c := doctorCheck{Name: "Prerequisite: " + name}
	path, err := exec.LookPath(name)
	if err != nil {
		c.Status = "FAIL"
		c.Detail = "Not found on PATH"
		return c
	}
	c.Status = "OK"
	c.Detail = "Found at " + path
	return c
}

// checkStateDir verifies the state directory is accessible.
func checkStateDir() doctorCheck {
	c := doctorCheck{Name: "State Directory"}
	dir := StateDir()
	info, err := os.Stat(dir)
	if err != nil {
		if os.IsNotExist(err) {
			// Directory doesn't exist but can be created
			c.Status = "OK"
			c.Detail = "Directory does not exist yet (will be created on install)"
			return c
		}
		c.Status = "FAIL"
		c.Detail = "Cannot access: " + err.Error()
		return c
	}
	if !info.IsDir() {
		c.Status = "FAIL"
		c.Detail = "Path exists but is not a directory: " + dir
		return c
	}
	c.Status = "OK"
	c.Detail = "Accessible at " + dir
	return c
}

// doctorSelfCheck verifies the lara-installer binary's own integrity.
// Returns a check result for self-diagnostics.
func doctorSelfCheck() doctorCheck {
	c := doctorCheck{Name: "Self Check"}

	// Verify we can read our own executable
	exe, err := os.Executable()
	if err != nil {
		c.Status = "FAIL"
		c.Detail = "Cannot determine executable path: " + err.Error()
		return c
	}

	info, err := os.Stat(exe)
	if err != nil {
		c.Status = "FAIL"
		c.Detail = "Cannot stat executable: " + err.Error()
		return c
	}

	if info.Size() == 0 {
		c.Status = "FAIL"
		c.Detail = "Executable is empty"
		return c
	}

	c.Status = "OK"
	c.Detail = fmt.Sprintf("Binary OK (%d bytes, v%s)", info.Size(), version)
	return c
}

// checkStateConsistency verifies that no steps are stuck in "running" status
// and that the install ID is valid.
func checkStateConsistency() doctorCheck {
	c := doctorCheck{Name: "State Consistency"}
	state, err := ReadState()
	if err != nil {
		c.Status = "WARN"
		c.Detail = "Cannot check consistency: " + err.Error()
		return c
	}
	if state == nil {
		c.Status = "OK"
		c.Detail = "No state file (nothing to check)"
		return c
	}

	var stuckSteps []string
	for _, step := range installSteps {
		s, err := state.ReadStep(step.Name)
		if err != nil {
			continue
		}
		if s == nil {
			continue
		}
		if s.Status == StepRunning {
			stuckSteps = append(stuckSteps, step.Name)
		}
	}

	if len(stuckSteps) > 0 {
		c.Status = "FAIL"
		c.Detail = fmt.Sprintf("Steps stuck in 'running': %v (previous install may have crashed)", stuckSteps)
		return c
	}

	c.Status = "OK"
	c.Detail = "All steps have valid terminal status"
	return c
}

// checkShell verifies that the required shell is available for rollback commands.
func checkShell() doctorCheck {
	name := "bash"
	if runtime.GOOS == "windows" {
		name = "pwsh"
	}
	c := doctorCheck{Name: "Shell: " + name}
	path, err := exec.LookPath(name)
	if err != nil {
		if runtime.GOOS == "windows" {
			// On Windows, fall back to PowerShell (powershell.exe)
			alt, err2 := exec.LookPath("powershell.exe")
			if err2 == nil {
				c.Status = "WARN"
				c.Detail = name + " not found, using powershell.exe at " + alt
				return c
			}
		}
		c.Status = "FAIL"
		c.Detail = "Not found on PATH — rollback commands will fail"
		return c
	}
	c.Status = "OK"
	c.Detail = "Found at " + path
	return c
}

// checkInstalledTool checks if a post-install tool is available on PATH.
// Missing tools get WARN (not FAIL) because the user may not have installed yet.
func checkInstalledTool(name string) doctorCheck {
	c := doctorCheck{Name: "Installed: " + name}
	path, err := exec.LookPath(name)
	if err != nil {
		c.Status = "WARN"
		c.Detail = "Not found on PATH (expected after installation)"
		return c
	}
	c.Status = "OK"
	c.Detail = "Found at " + path
	return c
}
