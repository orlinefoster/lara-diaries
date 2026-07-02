package main

import (
	"os"
	"runtime"
	"strings"
	"testing"
)

func TestDoctorResult_Struct(t *testing.T) {
	// Verify doctorCheck struct fields and behavior
	c := doctorCheck{
		Name:   "test check",
		Status: "OK",
		Detail: "all good",
	}

	if c.Name != "test check" {
		t.Errorf("Name = %q, want %q", c.Name, "test check")
	}
	if c.Status != "OK" {
		t.Errorf("Status = %q, want %q", c.Status, "OK")
	}
	if c.Detail != "all good" {
		t.Errorf("Detail = %q, want %q", c.Detail, "all good")
	}
}

func TestDoctorResult_StatusValues(t *testing.T) {
	validStatuses := map[string]bool{
		"OK":   true,
		"FAIL": true,
		"WARN": true,
	}

	result := runDoctorChecks()
	for _, check := range result {
		if !validStatuses[check.Status] {
			t.Errorf("check %q has invalid status %q", check.Name, check.Status)
		}
	}
}

func TestCheckOS_Compatibility(t *testing.T) {
	c := checkOS()

	switch runtime.GOOS {
	case "windows", "linux", "darwin":
		if c.Status != "OK" {
			t.Errorf("checkOS status = %q, want OK for GOOS=%q", c.Status, runtime.GOOS)
		}
	default:
		if c.Status != "FAIL" {
			t.Errorf("checkOS status = %q, want FAIL for GOOS=%q", c.Status, runtime.GOOS)
		}
	}

	if c.Name != "Operating System" {
		t.Errorf("checkOS.Name = %q, want %q", c.Name, "Operating System")
	}

	// Detail should mention the detected OS (case-insensitive)
	if !strings.Contains(strings.ToLower(c.Detail), runtime.GOOS) {
		t.Errorf("checkOS detail %q should mention %q (case-insensitive)", c.Detail, runtime.GOOS)
	}
}

func TestCheckStateDir_Accessibility(t *testing.T) {
	teardown := setupTestEnv(t)
	defer teardown()

	c := checkStateDir()

	// With setupTestEnv, StateDir() returns a temp dir that exists
	if c.Status != "OK" {
		t.Errorf("checkStateDir status = %q, want OK", c.Status)
	}
	if !strings.Contains(c.Detail, StateDir()) {
		t.Errorf("checkStateDir detail %q should contain path %q", c.Detail, StateDir())
	}
}

func TestCheckStateDir_NotExist(t *testing.T) {
	// Temporarily override StateDir to point to a non-existent path
	origStateDir := StateDir
	StateDir = func() string {
		return "/nonexistent/lara-diaries-test-path"
	}
	defer func() { StateDir = origStateDir }()

	c := checkStateDir()

	if c.Status != "OK" {
		// Non-existent directory should give OK (will be created on install)
		t.Errorf("checkStateDir status = %q, want OK for non-existent dir", c.Status)
	}
}

func TestCheckStateFile_NotExist(t *testing.T) {
	teardown := setupTestEnv(t)
	defer teardown()

	// No state file exists yet
	c := checkStateFile()

	if c.Status != "WARN" {
		t.Errorf("checkStateFile status = %q, want WARN for missing file", c.Status)
	}
}

func TestCheckStateFile_ValidState(t *testing.T) {
	teardown := setupTestEnv(t)
	defer teardown()

	// Create a valid state file
	state := NewInitialState("fresh")
	if err := WriteState(state); err != nil {
		t.Fatalf("WriteState: %v", err)
	}

	c := checkStateFile()

	if c.Status != "OK" {
		t.Errorf("checkStateFile status = %q, want OK for valid state", c.Status)
	}
	if !strings.Contains(c.Detail, state.InstallID) {
		t.Errorf("checkStateFile detail %q should contain InstallID %q", c.Detail, state.InstallID)
	}
}

func TestCheckStateFile_InvalidState(t *testing.T) {
	teardown := setupTestEnv(t)
	defer teardown()

	// Write invalid JSON to state file
	os.MkdirAll(StateDir(), 0755)
	if err := os.WriteFile(StateFile(), []byte("invalid json{{{"), 0644); err != nil {
		t.Fatalf("writing state file: %v", err)
	}

	c := checkStateFile()

	if c.Status != "FAIL" {
		t.Errorf("checkStateFile status = %q, want FAIL for invalid state", c.Status)
	}
}

func TestCheckLockFile_NoLock(t *testing.T) {
	teardown := setupTestEnv(t)
	defer teardown()

	// No lock file exists
	c := checkLockFile()

	if c.Status != "OK" {
		t.Errorf("checkLockFile status = %q, want OK for no lock", c.Status)
	}
}

func TestCheckLockFile_Active(t *testing.T) {
	teardown := setupTestEnv(t)
	defer teardown()

	// Create an active lock
	if err := CreateLock(); err != nil {
		t.Fatalf("CreateLock: %v", err)
	}

	c := checkLockFile()

	if c.Status != "WARN" {
		t.Errorf("checkLockFile status = %q, want WARN for active lock", c.Status)
	}
}

func TestCheckPrereq_Found(t *testing.T) {
	// Use a command guaranteed available on each platform
	cmd := "sh"
	if runtime.GOOS == "windows" {
		cmd = "cmd"
	}
	c := checkPrereq(cmd)

	if c.Status != "OK" {
		t.Errorf("checkPrereq(%q) status = %q, want OK", cmd, c.Status)
	}
	if !strings.Contains(c.Detail, "Found at") {
		t.Errorf("checkPrereq detail %q should mention 'Found at'", c.Detail)
	}
}

func TestCheckPrereq_NotFound(t *testing.T) {
	c := checkPrereq("this-command-definitely-does-not-exist-12345")

	if c.Status != "FAIL" {
		t.Errorf("checkPrereq status = %q, want FAIL", c.Status)
	}
}

func TestDoctorCheckCount(t *testing.T) {
	checks := runDoctorChecks()
	// runDoctorChecks now includes 11 checks:
	// OS, StateFile, StateConsistency, LockFile, git, gh, Shell, engram, gentle-ai, StateDir, SelfCheck
	if len(checks) < 10 {
		t.Errorf("got %d checks, want at least 10", len(checks))
	}
}

func TestCheckShell_BashFound(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("bash not typically on PATH on Windows")
	}
	c := checkShell()
	if c.Status != "OK" {
		t.Errorf("checkShell status = %q, want OK", c.Status)
	}
	if !strings.Contains(c.Detail, "Found at") {
		t.Errorf("checkShell detail %q should mention 'Found at'", c.Detail)
	}
}

func TestCheckShell_WindowsFallback(t *testing.T) {
	if runtime.GOOS != "windows" {
		t.Skip("Windows-specific test")
	}
	c := checkShell()
	// On Windows, should find pwsh or powershell.exe
	if c.Status != "OK" && c.Status != "WARN" {
		t.Errorf("checkShell status = %q, want OK or WARN on Windows", c.Status)
	}
}

func TestCheckStateConsistency_NoState(t *testing.T) {
	teardown := setupTestEnv(t)
	defer teardown()

	c := checkStateConsistency()
	if c.Status != "OK" {
		t.Errorf("checkStateConsistency with no state = %q, want OK", c.Status)
	}
}

func TestCheckStateConsistency_AllSuccess(t *testing.T) {
	teardown := setupTestEnv(t)
	defer teardown()

	state := NewInitialState("fresh")
	for _, s := range installSteps {
		_ = state.UpdateStep(s.Name, func(st *Step) { st.Status = StepSuccess })
	}
	if err := WriteState(state); err != nil {
		t.Fatalf("WriteState: %v", err)
	}

	c := checkStateConsistency()
	if c.Status != "OK" {
		t.Errorf("checkStateConsistency with all success = %q, want OK", c.Status)
	}
}

func TestCheckStateConsistency_StuckRunning(t *testing.T) {
	teardown := setupTestEnv(t)
	defer teardown()

	state := NewInitialState("fresh")
	_ = state.UpdateStep("github_login", func(s *Step) { s.Status = StepSuccess })
	_ = state.UpdateStep("clone_gentle_ai", func(s *Step) { s.Status = StepRunning })
	_ = state.UpdateStep("setup_engram", func(s *Step) { s.Status = StepPending })
	if err := WriteState(state); err != nil {
		t.Fatalf("WriteState: %v", err)
	}

	c := checkStateConsistency()
	if c.Status != "FAIL" {
		t.Errorf("checkStateConsistency with stuck running = %q, want FAIL", c.Status)
	}
}

func TestCheckInstalledTool_Found(t *testing.T) {
	// sh/cmd should always be on PATH
	cmd := "sh"
	if runtime.GOOS == "windows" {
		cmd = "cmd"
	}
	c := checkInstalledTool(cmd)
	if c.Status != "OK" {
		t.Errorf("checkInstalledTool(%q) = %q, want OK", cmd, c.Status)
	}
}

func TestCheckInstalledTool_NotFound(t *testing.T) {
	c := checkInstalledTool("this-tool-definitely-does-not-exist-99999")
	if c.Status != "WARN" {
		t.Errorf("checkInstalledTool(notfound) = %q, want WARN", c.Status)
	}
}
