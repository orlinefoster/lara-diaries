package main

import "testing"

func TestSteps_ExpectedNames(t *testing.T) {
	expected := []string{
		"github_login",
		"clone_gentle_ai",
		"setup_gentleman_skills",
		"setup_engram",
		"setup_opencode",
		"setup_vscode",
	}

	if len(installSteps) != len(expected) {
		t.Fatalf("len(installSteps) = %d, want %d", len(installSteps), len(expected))
	}

	for i, step := range installSteps {
		if step.Name != expected[i] {
			t.Errorf("installSteps[%d].Name = %q, want %q", i, step.Name, expected[i])
		}
	}
}

func TestSteps_HaveRunAndRollback(t *testing.T) {
	for _, step := range installSteps {
		if step.Run == nil {
			t.Errorf("step %q has nil Run function", step.Name)
		}
		if step.Rollback == nil {
			t.Errorf("step %q has nil Rollback function", step.Name)
		}
	}
}

func TestSteps_AllHaveUniqueNames(t *testing.T) {
	seen := make(map[string]bool)
	for _, step := range installSteps {
		if seen[step.Name] {
			t.Errorf("duplicate step name: %q", step.Name)
		}
		seen[step.Name] = true
	}
}

func TestStepLifecycle_TransitionValidation(t *testing.T) {
	// Test the State machine transitions through install-like states
	teardown := setupTestEnv(t)
	defer teardown()

	state := NewInitialState("fresh")

	// Simulate a step lifecycle: pending -> running -> success
	t.Run("lifecycle", func(t *testing.T) {
		now := timeNow()
		if err := state.UpdateStep("github_login", func(s *Step) {
			s.Status = StepRunning
			s.StartedAt = &now
		}); err != nil {
			t.Fatalf("UpdateStep to running: %v", err)
		}

		step, err := state.ReadStep("github_login")
		if err != nil {
			t.Fatalf("ReadStep: %v", err)
		}
		if step.Status != StepRunning {
			t.Errorf("Status = %q, want %q", step.Status, StepRunning)
		}

		// Mark success
		now2 := timeNow()
		if err := state.UpdateStep("github_login", func(s *Step) {
			s.Status = StepSuccess
			s.CompletedAt = &now2
		}); err != nil {
			t.Fatalf("UpdateStep to success: %v", err)
		}

		step, err = state.ReadStep("github_login")
		if err != nil {
			t.Fatalf("ReadStep: %v", err)
		}
		if step.Status != StepSuccess {
			t.Errorf("Status = %q, want %q", step.Status, StepSuccess)
		}
		if step.CompletedAt == nil {
			t.Error("CompletedAt should not be nil after success")
		}
	})
}

func TestStepLifecycle_RollbackPath(t *testing.T) {
	teardown := setupTestEnv(t)
	defer teardown()

	state := NewInitialState("fresh")

	// Simulate a failed step with rollback
	now := timeNow()
	if err := state.UpdateStep("clone_gentle_ai", func(s *Step) {
		s.Status = StepRunning
		s.StartedAt = &now
	}); err != nil {
		t.Fatalf("UpdateStep to running: %v", err)
	}

	// Step fails
	now2 := timeNow()
	if err := state.UpdateStep("clone_gentle_ai", func(s *Step) {
		s.Status = StepFailed
		s.Error = "network timeout"
		s.CompletedAt = &now2
	}); err != nil {
		t.Fatalf("UpdateStep to failed: %v", err)
	}

	step, err := state.ReadStep("clone_gentle_ai")
	if err != nil {
		t.Fatalf("ReadStep: %v", err)
	}
	if step.Status != StepFailed {
		t.Errorf("Status = %q, want %q", step.Status, StepFailed)
	}
	if step.Error != "network timeout" {
		t.Errorf("Error = %q, want %q", step.Error, "network timeout")
	}
	if step.CompletedAt == nil {
		t.Error("CompletedAt should not be nil after failure")
	}
}

func TestRollbackHandlers_Execute(t *testing.T) {
	// Verify that each step's rollback handler can be called without error
	for _, step := range installSteps {
		t.Run(step.Name, func(t *testing.T) {
			// Rollback should not panic
			defer func() {
				if r := recover(); r != nil {
					t.Fatalf("Rollback for %q panicked: %v", step.Name, r)
				}
			}()
			step.Rollback()
		})
	}
}

func TestRunHandlers_Execute(t *testing.T) {
	// Verify that each step's run handler does not panic when called.
	// The standaloneRun path is triggered by runInstall(), not by step.Run directly.
	// With an empty wizardPath, shellOut will return an error — that's expected.
	for _, step := range installSteps {
		t.Run(step.Name, func(t *testing.T) {
			defer func() {
				if r := recover(); r != nil {
					t.Fatalf("Run for %q panicked: %v", step.Name, r)
				}
			}()
			// Run with empty wizard path — will error but should not panic
			_ = step.Run("", "")
		})
	}
}
