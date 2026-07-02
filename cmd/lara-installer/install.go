package main

import (
	"bufio"
	"fmt"
	"os"
	"strings"
)

// installStep defines a single installation step with its run and rollback functions.
type installStep struct {
	Name     string
	Run      func() error
	Rollback func()
}

// installSteps defines the ordered list of installation steps.
var installSteps = []installStep{
	{
		Name: "github_login",
		Run: func() error {
			fmt.Println("  [..] Checking GitHub CLI (gh) status...")
			return nil
		},
		Rollback: func() {
			fmt.Println("  [..] No rollback needed for GitHub login check.")
		},
	},
	{
		Name: "clone_gentle_ai",
		Run: func() error {
			fmt.Println("  [..] Would clone Gentle AI repository...")
			return nil
		},
		Rollback: func() {
			fmt.Println("  [..] Would remove ~/gentle-ai directory.")
		},
	},
	{
		Name: "setup_gentleman_skills",
		Run: func() error {
			fmt.Println("  [..] Would install Gentleman Skills...")
			return nil
		},
		Rollback: func() {
			fmt.Println("  [..] Would remove Gentleman Skills directory.")
		},
	},
	{
		Name: "setup_engram",
		Run: func() error {
			fmt.Println("  [..] Would set up Engram persistent memory...")
			return nil
		},
		Rollback: func() {
			fmt.Println("  [..] Would clean up Engram configuration.")
		},
	},
	{
		Name: "setup_opencode",
		Run: func() error {
			fmt.Println("  [..] Would configure opencode with Lara agents...")
			return nil
		},
		Rollback: func() {
			fmt.Println("  [..] Would revert opencode configuration changes.")
		},
	},
	{
		Name: "setup_vscode",
		Run: func() error {
			fmt.Println("  [..] Would configure VSCode extensions and settings...")
			return nil
		},
		Rollback: func() {
			fmt.Println("  [..] Would revert VSCode settings changes.")
		},
	},
}

// runInstall executes the interactive installation wizard.
func runInstall() {
	fmt.Println()
	fmt.Println("  +-----------------------------------------+")
	fmt.Println("  |                                         |")
	fmt.Println("  |      LARA DIARIES INSTALLER             |")
	fmt.Println("  |            v" + version + "                       |")
	fmt.Println("  |                                         |")
	fmt.Println("  +-----------------------------------------+")
	fmt.Println()

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

	// --- Confirm with user ---
	fmt.Print("Proceed with installation? [Y/n]: ")
	reader := bufio.NewReader(os.Stdin)
	answer, _ := reader.ReadString('\n')
	answer = strings.TrimSpace(strings.ToLower(answer))
	if answer == "n" || answer == "no" {
		fmt.Println("[OK] Installation cancelled. Run again when ready.")
		os.Exit(0)
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
		if err := step.Run(); err != nil {
			msg := err.Error()
			fmt.Fprintf(os.Stderr, "  [FAIL] Step '%s' failed: %s\n", step.Name, msg)

			// Run rollback
			step.Rollback()
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
