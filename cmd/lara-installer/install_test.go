package main

import (
	"sync"
	"testing"
)

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
	for _, step := range installSteps {
		t.Run(step.Name, func(t *testing.T) {
			defer func() {
				if r := recover(); r != nil {
					t.Fatalf("Rollback for %q panicked: %v", step.Name, r)
				}
			}()
			step.Rollback()
		})
	}
}

func TestCumulativeRollback_NoPanic(t *testing.T) {
	// rollbackAll must not panic even with no completed steps, partial steps,
	// or all steps completed.
	t.Run("no completed steps", func(t *testing.T) {
		state := NewInitialState("fresh")
		rollbackAll(state)
	})

	t.Run("first step completed", func(t *testing.T) {
		state := NewInitialState("fresh")
		_ = state.UpdateStep("github_login", func(s *Step) { s.Status = StepSuccess })
		rollbackAll(state)
	})

	t.Run("all steps completed", func(t *testing.T) {
		state := NewInitialState("fresh")
		for _, s := range installSteps {
			_ = state.UpdateStep(s.Name, func(st *Step) { st.Status = StepSuccess })
		}
		rollbackAll(state)
	})
}

func TestCompletedSteps_Partial(t *testing.T) {
	teardown := setupTestEnv(t)
	defer teardown()

	state := NewInitialState("fresh")
	_ = state.UpdateStep("github_login", func(s *Step) { s.Status = StepSuccess })
	_ = state.UpdateStep("clone_gentle_ai", func(s *Step) { s.Status = StepSuccess })
	// setup_gentleman_skills left pending

	completed := state.CompletedSteps()
	if len(completed) != 2 {
		t.Fatalf("CompletedSteps() = %d, want 2 (got %v)", len(completed), completed)
	}
	if completed[0] != "github_login" {
		t.Errorf("CompletedSteps[0] = %q, want %q", completed[0], "github_login")
	}
	if completed[1] != "clone_gentle_ai" {
		t.Errorf("CompletedSteps[1] = %q, want %q", completed[1], "clone_gentle_ai")
	}
}

func TestCompletedSteps_OnlySuccess(t *testing.T) {
	teardown := setupTestEnv(t)
	defer teardown()

	state := NewInitialState("fresh")
	_ = state.UpdateStep("github_login", func(s *Step) { s.Status = StepSuccess })
	_ = state.UpdateStep("clone_gentle_ai", func(s *Step) { s.Status = StepFailed })
	_ = state.UpdateStep("setup_gentleman_skills", func(s *Step) { s.Status = StepRunning })

	completed := state.CompletedSteps()
	if len(completed) != 1 {
		t.Fatalf("CompletedSteps() = %d, want 1 (got %v)", len(completed), completed)
	}
	if completed[0] != "github_login" {
		t.Errorf("CompletedSteps[0] = %q, want %q", completed[0], "github_login")
	}
}

func TestCompletedSteps_Empty(t *testing.T) {
	state := NewInitialState("fresh")
	completed := state.CompletedSteps()
	if len(completed) != 0 {
		t.Errorf("CompletedSteps() for empty state = %v, want []", completed)
	}
}

func TestRunHandlers_Execute(t *testing.T) {
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

func TestRollbackAll_ReverseOrder(t *testing.T) {
	// Verify that rollbackAll() calls rollback in reverse completion order.
	// Use a counter to track the order.
	var mu sync.Mutex
	order := []string{}

	// Save original rollbacks and restore after test
	orig := make([]func(), len(installSteps))
	for i, step := range installSteps {
		orig[i] = step.Rollback
	}
	t.Cleanup(func() {
		for i := range installSteps {
			installSteps[i].Rollback = orig[i]
		}
	})

	// Replace rollbacks with order-trackers
	for i := range installSteps {
		name := installSteps[i].Name
		installSteps[i].Rollback = func() {
			mu.Lock()
			order = append(order, name)
			mu.Unlock()
		}
	}

	state := NewInitialState("fresh")
	for _, s := range installSteps {
		_ = state.UpdateStep(s.Name, func(st *Step) { st.Status = StepSuccess })
	}

	rollbackAll(state)

	// Expected: last installed = first rolled back
	expected := []string{
		"setup_vscode",
		"setup_opencode",
		"setup_engram",
		"setup_gentleman_skills",
		"clone_gentle_ai",
		"github_login",
	}
	if len(order) != len(expected) {
		t.Fatalf("rollbackAll executed %d rollbacks, want %d\n  got:      %v\n  expected: %v",
			len(order), len(expected), order, expected)
	}
	for i, name := range expected {
		if order[i] != name {
			t.Errorf("rollback order[%d] = %q, want %q\n  got:      %v\n  expected: %v",
				i, order[i], name, order, expected)
		}
	}
}
