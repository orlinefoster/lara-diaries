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

func runDoctor() {
	var checks []doctorCheck
	allOK := true

	fmt.Println()
	fmt.Println("  +-----------------------------------------+")
	fmt.Println("  |                                         |")
	fmt.Println("  |      LARA DIARIES DOCTOR                |")
	fmt.Println("  |            v" + version + "                       |")
	fmt.Println("  |                                         |")
	fmt.Println("  +-----------------------------------------+")
	fmt.Println()

	// 1. OS compatibility
	osCheck := checkOS()
	checks = append(checks, osCheck)
	if osCheck.Status != "OK" {
		allOK = false
	}

	// 2. State file
	stateCheck := checkStateFile()
	checks = append(checks, stateCheck)
	if stateCheck.Status == "FAIL" {
		allOK = false
	}

	// 3. Lock file status
	lockCheck := checkLockFile()
	checks = append(checks, lockCheck)

	// 4. Prerequisites: git, gh
	gitCheck := checkPrereq("git")
	checks = append(checks, gitCheck)
	if gitCheck.Status == "FAIL" {
		allOK = false
	}

	ghCheck := checkPrereq("gh")
	checks = append(checks, ghCheck)
	if ghCheck.Status == "FAIL" {
		allOK = false
	}

	// 5. State directory accessibility
	dirCheck := checkStateDir()
	checks = append(checks, dirCheck)
	if dirCheck.Status == "FAIL" {
		allOK = false
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
