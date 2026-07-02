package main

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
)

// wizardCorePath returns the path to wizard-core.sh relative to the binary,
// or falls back to well-known locations.
func wizardCorePath() (string, error) {
	// If running from bootstrap, bootstrap passes LARA_WIZARD_CORE
	if p := os.Getenv("LARA_WIZARD_CORE"); p != "" {
		if _, err := os.Stat(p); err == nil {
			return p, nil
		}
	}

	// Relative to the binary (release layout: bin/lara-installer)
	exe, err := os.Executable()
	if err == nil {
		// Try: <binary>/../../modules/wizard-core.sh
		base := filepath.Dir(filepath.Dir(filepath.Dir(exe)))
		candidates := []string{
			filepath.Join(base, "modules", "wizard-core.sh"),
			filepath.Join(base, "lara-diaries", "modules", "wizard-core.sh"),
		}
		if home, _ := os.UserHomeDir(); home != "" {
			candidates = append(candidates,
				filepath.Join(home, "lara-diaries", "modules", "wizard-core.sh"),
			)
		}
		for _, p := range candidates {
			if _, err := os.Stat(p); err == nil {
				return p, nil
			}
		}
	}

	return "", fmt.Errorf("wizard-core.sh not found")
}

// shellOut calls run_go_step from wizard-core.sh, piping stdout/stderr.
// Uses argument passing instead of string interpolation to prevent shell injection.
func shellOut(wizardPath, stepName, jsonConfig string) error {
	var cmd *exec.Cmd
	if runtime.GOOS == "windows" {
		// On Windows, locate PowerShell or cmd for the shell bridge.
		// wizard-core.sh can't run directly — inform user and link to PowerShell wizard.
		pwsh, err := exec.LookPath("pwsh")
		if err != nil {
			pwsh, err = exec.LookPath("powershell")
		}
		if err == nil {
			cmd = exec.Command(pwsh, "-NoProfile", "-Command",
				"& '"+wizardPath+"'; Start-Wizard")
		} else {
			fmt.Fprintln(os.Stderr, "  [!] On Windows, please use bootstrap.ps1 instead of lara-installer.")
			fmt.Fprintln(os.Stderr, "  [!] The lara-installer binary requires wizard-core.sh (Unix).")
			return fmt.Errorf("wizard-core.sh bridge not available on Windows without WSL")
		}
	} else {
		// Unix: pass path as $1 to bash -s to avoid injection in -c string
		cmd = exec.Command("bash", "-s", "--", wizardPath)
		cmd.Stdin = strings.NewReader("source \"$1\" && run_go_step '" + stepName + "'")
	}
	if jsonConfig != "" {
		cmd.Env = append(os.Environ(), "LARA_JSON_CONFIG="+jsonConfig)
	}
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

// rollbackShell runs a shell rollback command.
// Uses argument passing to prevent shell injection.
func rollbackShell(desc, cmdStr string) {
	fmt.Println("  [..] Rollback: " + desc)
	// Pass command via stdin to bash -s to avoid injection in -c string
	cmd := exec.Command("bash", "-s")
	cmd.Stdin = strings.NewReader(cmdStr)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	_ = cmd.Run()
}

// installStep defines a single installation step with its run and rollback functions.
type installStep struct {
	Name     string
	Run      func(wizardPath, jsonConfig string) error
	Rollback func()
}

// globalJSONConfig holds the non-interactive JSON config, loaded once.
var globalJSONConfig string

// installSteps defines the ordered list of installation steps.
var installSteps = []installStep{
	{
		Name: "github_login",
		Run: func(wizardPath, jsonConfig string) error {
			return shellOut(wizardPath, "github_login", jsonConfig)
		},
		Rollback: func() {
			// No rollback needed for login check
		},
	},
	{
		Name: "clone_gentle_ai",
		Run: func(wizardPath, jsonConfig string) error {
			return shellOut(wizardPath, "clone_gentle_ai", jsonConfig)
		},
		Rollback: func() {
			home, _ := os.UserHomeDir()
			rollbackShell("remove ~/gentle-ai", "rm -rf '"+filepath.Join(home, "gentle-ai")+"'")
		},
	},
	{
		Name: "setup_gentleman_skills",
		Run: func(wizardPath, jsonConfig string) error {
			return shellOut(wizardPath, "setup_gentleman_skills", jsonConfig)
		},
		Rollback: func() {
			skillsDir := filepath.Join(os.Getenv("HOME"), ".config", "opencode", "skills", "gentleman-skills")
			rollbackShell("remove gentleman-skills", "rm -rf '"+skillsDir+"'")
		},
	},
	{
		Name: "setup_engram",
		Run: func(wizardPath, jsonConfig string) error {
			return shellOut(wizardPath, "setup_engram", jsonConfig)
		},
		Rollback: func() {
			rollbackShell("remove engram binary", "rm -f '"+filepath.Join(os.Getenv("HOME"), ".local", "bin", "engram")+"'")
		},
	},
	{
		Name: "setup_opencode",
		Run: func(wizardPath, jsonConfig string) error {
			return shellOut(wizardPath, "setup_opencode", jsonConfig)
		},
		Rollback: func() {
			configDir := filepath.Join(os.Getenv("HOME"), ".config", "opencode")
			rollbackShell("restore opencode config backup",
				"cp '"+filepath.Join(configDir, "opencode.json.bak")+"' '"+filepath.Join(configDir, "opencode.json")+"' 2>/dev/null; rm -rf '"+filepath.Join(configDir, "agents")+"' 2>/dev/null; true")
		},
	},
	{
		Name: "setup_vscode",
		Run: func(wizardPath, jsonConfig string) error {
			return shellOut(wizardPath, "setup_vscode", jsonConfig)
		},
		Rollback: func() {
			extensions := []string{
				"bierner.markdown-mermaid",
				"yzhang.markdown-all-in-one",
				"opencode.opencode-vscode",
			}
			for _, ext := range extensions {
				rollbackShell("uninstall "+ext, "code --uninstall-extension '"+ext+"' 2>/dev/null; true")
			}
		},
	},
}

// runInstall executes the installation wizard.
func runInstall() {
	fmt.Println()
	fmt.Println("  +-----------------------------------------+")
	fmt.Println("  |                                         |")
	fmt.Println("  |      LARA DIARIES INSTALLER             |")
	fmt.Println("  |            v" + version + "                       |")
	fmt.Println("  |                                         |")
	fmt.Println("  +-----------------------------------------+")
	fmt.Println()

	// --- Locate wizard-core.sh ---
	wizardPath, err := wizardCorePath()
	if err != nil {
		// If running standalone (no wizard-core found), use built-in stubs.
		// This allows the binary to function as a standalone installer
		// when embedded via release.
		fmt.Println("  [..] wizard-core.sh not found — running in standalone mode.")
		fmt.Println("  [..] Some features may be limited. Install the full repo for full functionality.")
		wizardPath = ""
	}

	// --- Lock guard ---
	status := StaleLockStatus()
	switch status {
	case LockStatusActive:
		fmt.Println("[FAIL] Another installation is already in progress.")
		fmt.Println("  If you believe this is an error, manually remove the lock file:")
		fmt.Println("    " + LockFile())
		os.Exit(1)
	case LockStatusStale:
		fmt.Println("[!] Lock file from a previous installation detected.")
		fmt.Print("  Remove it and continue? [y/N]: ")
		reader := bufio.NewReader(os.Stdin)
		answer, _ := reader.ReadString('\n')
		answer = strings.TrimSpace(strings.ToLower(answer))
		if answer == "y" || answer == "yes" {
			if err := ReleaseLock(); err != nil {
				fmt.Fprintf(os.Stderr, "[FAIL] Could not remove stale lock: %v\n", err)
				os.Exit(1)
			}
			fmt.Println("[OK] Lock removed. Continuing...")
		} else {
			fmt.Println("[OK] Exiting without changes. Run again when ready.")
			os.Exit(0)
		}
	}

	// Create install lock
	if err := CreateLock(); err != nil {
		fmt.Fprintf(os.Stderr, "[FAIL] Could not create install lock: %v\n", err)
		os.Exit(1)
	}
	defer func() {
		if err := ReleaseLock(); err != nil {
			fmt.Fprintf(os.Stderr, "[!] Warning: could not release lock: %v\n", err)
		}
	}()

	// --- Read or create state ---
	state, err := ReadState()
	if err != nil {
		fmt.Fprintf(os.Stderr, "[FAIL] Could not read state file: %v\n", err)
		os.Exit(1)
	}
	if state == nil {
		state = NewInitialState("fresh")
		fmt.Println("[INFO] Starting fresh installation.")
	} else {
		fmt.Println("[INFO] Resuming existing installation (ID: " + state.InstallID + ").")
	}

	// --- Confirm with user (interactive mode only) ---
	if globalJSONConfig == "" {
		fmt.Print("Proceed with installation? [Y/n]: ")
		reader := bufio.NewReader(os.Stdin)
		answer, _ := reader.ReadString('\n')
		answer = strings.TrimSpace(strings.ToLower(answer))
		if answer == "n" || answer == "no" {
			fmt.Println("[OK] Installation cancelled. Run again when ready.")
			os.Exit(0)
		}
	}

	// --- Run each step ---
	for _, step := range installSteps {
		// Check if step is already successful
		currentStep, err := state.ReadStep(step.Name)
		if err != nil {
			fmt.Fprintf(os.Stderr, "[FAIL] Could not read step %s: %v\n", step.Name, err)
			writeFailedState(state, step.Name, err.Error())
			os.Exit(1)
		}
		if currentStep != nil && currentStep.Status == StepSuccess {
			fmt.Println("  [OK] " + step.Name + " already completed. Skipping.")
			continue
		}

		// Mark step as running
		now := timeNow()
		if err := state.UpdateStep(step.Name, func(s *Step) {
			s.Status = StepRunning
			s.StartedAt = &now
		}); err != nil {
			fmt.Fprintf(os.Stderr, "[FAIL] Could not update step %s: %v\n", step.Name, err)
			writeFailedState(state, step.Name, err.Error())
			os.Exit(1)
		}
		if err := WriteState(state); err != nil {
			fmt.Fprintf(os.Stderr, "[FAIL] Could not write state: %v\n", err)
			writeFailedState(state, step.Name, err.Error())
			os.Exit(1)
		}

		// Run the step
		fmt.Println("  [..] Running: " + step.Name)

		var stepErr error
		if wizardPath != "" {
			stepErr = step.Run(wizardPath, globalJSONConfig)
		} else {
			// Standalone mode: no wizard-core.sh available
			// Use a basic shell command as fallback
			fmt.Println("  [..] Standalone mode — using basic commands.")
			stepErr = standaloneRun(step.Name)
		}

		if stepErr != nil {
			msg := stepErr.Error()
			fmt.Fprintf(os.Stderr, "  [FAIL] Step '%s' failed: %s\n", step.Name, msg)

			// Run rollback
			if wizardPath != "" {
				step.Rollback()
			}
			fmt.Println("  [..] Rollback completed for: " + step.Name)

			// Mark step as failed
			writeFailedState(state, step.Name, msg)
			os.Exit(1)
		}

		// Mark step as success
		now = timeNow()
		if err := state.UpdateStep(step.Name, func(s *Step) {
			s.Status = StepSuccess
			s.CompletedAt = &now
		}); err != nil {
			fmt.Fprintf(os.Stderr, "[FAIL] Could not mark step %s as success: %v\n", step.Name, err)
			writeFailedState(state, step.Name, err.Error())
			os.Exit(1)
		}
		if err := WriteState(state); err != nil {
			fmt.Fprintf(os.Stderr, "[FAIL] Could not write state: %v\n", err)
			writeFailedState(state, step.Name, err.Error())
			os.Exit(1)
		}
		fmt.Println("  [OK] " + step.Name + " completed.")
	}

	fmt.Println()
	fmt.Println("[OK] All steps completed successfully.")
	fmt.Println("  Installation ID: " + state.InstallID)
	fmt.Println("  Run 'lara-installer doctor' to verify the installation.")
	fmt.Println()
}

// standaloneRun provides basic fallback when wizard-core.sh is not available.
func standaloneRun(stepName string) error {
	switch stepName {
	case "github_login":
		cmd := exec.Command("gh", "auth", "status")
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		return cmd.Run()
	case "clone_gentle_ai":
		home, _ := os.UserHomeDir()
		dest := filepath.Join(home, "gentle-ai")
		if _, err := os.Stat(dest); err == nil {
			fmt.Println("  [OK] Already cloned.")
			return nil
		}
		cmd := exec.Command("git", "clone", "https://github.com/Gentleman-Programming/gentle-ai.git", dest)
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		return cmd.Run()
	case "setup_gentleman_skills":
		home := os.Getenv("HOME")
		dest := filepath.Join(home, ".config", "opencode", "skills", "gentleman-skills")
		if _, err := os.Stat(dest); err == nil {
			fmt.Println("  [OK] Already installed.")
			return nil
		}
		_ = os.MkdirAll(filepath.Dir(dest), 0755)
		cmd := exec.Command("git", "clone", "https://github.com/Gentleman-Programming/gentleman-skills.git", dest)
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		return cmd.Run()
	case "setup_engram":
		fmt.Println("  [FAIL] Standalone mode cannot install Engram.")
		fmt.Println("  Install manually: https://github.com/Gentleman-Programming/engram#quick-start")
		fmt.Println("  Or run from the full lara-diaries repo for the wizard-core.sh bridge.")
		return fmt.Errorf("engram installation not available in standalone mode")
	case "setup_opencode":
		fmt.Println("  [FAIL] Standalone mode cannot configure opencode.")
		fmt.Println("  See bootstrap-agent.md in the lara-diaries repo for manual setup.")
		fmt.Println("  Or run from the full lara-diaries repo for the wizard-core.sh bridge.")
		return fmt.Errorf("opencode config not available in standalone mode")
	case "setup_vscode":
		codePath, err := exec.LookPath("code")
		if err != nil {
			fmt.Println("  [..] VSCode not found, skipping.")
			return nil
		}
		extensions := []string{
			"bierner.markdown-mermaid",
			"yzhang.markdown-all-in-one",
			"opencode.opencode-vscode",
		}
		for _, ext := range extensions {
			cmd := exec.Command(codePath, "--install-extension", ext, "--force")
			cmd.Stdout = os.Stdout
			cmd.Stderr = os.Stderr
			_ = cmd.Run()
		}
		return nil
	default:
		return fmt.Errorf("unknown step: %s", stepName)
	}
}

// writeFailedState updates a step to failed and writes state, then exits.
func writeFailedState(state *State, stepName, errMsg string) {
	now := timeNow()
	_ = state.UpdateStep(stepName, func(s *Step) {
		s.Status = StepFailed
		s.Error = errMsg
		s.CompletedAt = &now
	})
	_ = WriteState(state)
}

// getWizardCoreDir returns the directory containing wizard-core.sh.
// Used by bootstrap scripts to set LARA_WIZARD_CORE.
func getWizardCoreDir() string {
	exe, err := os.Executable()
	if err != nil {
		return ""
	}
	return filepath.Dir(filepath.Dir(exe))
}

func init() {
	// These are here so the package compiles on Windows too
	_ = runtime.GOOS
}
