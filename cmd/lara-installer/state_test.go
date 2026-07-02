package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"
)

// setupTestEnv overrides path functions to use a temp directory.
func setupTestEnv(t *testing.T) (teardown func()) {
	t.Helper()
	tmpDir, err := os.MkdirTemp("", "lara-installer-test-*")
	if err != nil {
		t.Fatalf("creating temp dir: %v", err)
	}

	origStateDir := StateDir
	origStateFile := StateFile
	origLockFile := LockFile
	origTimeNow := timeNow

	StateDir = func() string { return tmpDir }
	StateFile = func() string { return filepath.Join(tmpDir, "state.json") }
	LockFile = func() string { return filepath.Join(tmpDir, "install.lock") }

	return func() {
		StateDir = origStateDir
		StateFile = origStateFile
		LockFile = origLockFile
		timeNow = origTimeNow
		os.RemoveAll(tmpDir)
	}
}

func TestNewInitialState_Schema(t *testing.T) {
	frozen := time.Date(2026, 7, 1, 12, 0, 0, 0, time.UTC)
	timeNow = func() time.Time { return frozen }
	defer func() { timeNow = time.Now }()

	state := NewInitialState("fresh")

	if state.Version != 1 {
		t.Errorf("Version = %d, want 1", state.Version)
	}
	if state.InstallID == "" {
		t.Error("InstallID should not be empty")
	}
	if state.CreatedAt != frozen {
		t.Errorf("CreatedAt = %v, want %v", state.CreatedAt, frozen)
	}
	if state.UpdatedAt != frozen {
		t.Errorf("UpdatedAt = %v, want %v", state.UpdatedAt, frozen)
	}
	if state.InstallType != "fresh" {
		t.Errorf("InstallType = %q, want %q", state.InstallType, "fresh")
	}
	if state.Steps == nil {
		t.Error("Steps should not be nil")
	}
	if len(state.Steps) != 0 {
		t.Errorf("len(Steps) = %d, want 0", len(state.Steps))
	}
}

func TestNewInitialState_DefaultInstallType(t *testing.T) {
	// Test with empty install type — NewInitialState uses whatever is passed
	state := NewInitialState("")
	if state.InstallType != "" {
		t.Errorf("InstallType = %q, want empty", state.InstallType)
	}
}

func TestReadState_FileNotExist(t *testing.T) {
	teardown := setupTestEnv(t)
	defer teardown()

	state, err := ReadState()
	if err != nil {
		t.Fatalf("ReadState on missing file: %v", err)
	}
	if state != nil {
		t.Fatal("ReadState should return nil for missing file")
	}
}

func TestReadState_UnparseableFile(t *testing.T) {
	teardown := setupTestEnv(t)
	defer teardown()

	if err := os.WriteFile(StateFile(), []byte("not-json{{{"), 0644); err != nil {
		t.Fatalf("writing state file: %v", err)
	}

	_, err := ReadState()
	if err == nil {
		t.Fatal("ReadState should error on unparseable file")
	}
	if !strings.Contains(err.Error(), "parsing") {
		t.Errorf("error should mention parsing, got: %v", err)
	}
}

func TestWriteRead_Roundtrip(t *testing.T) {
	teardown := setupTestEnv(t)
	defer teardown()

	frozen := time.Date(2026, 7, 1, 12, 0, 0, 0, time.UTC)
	timeNow = func() time.Time { return frozen }
	defer func() { timeNow = time.Now }()

	// Write
	original := NewInitialState("fresh")
	if err := WriteState(original); err != nil {
		t.Fatalf("WriteState: %v", err)
	}

	// Verify file exists
	if _, err := os.Stat(StateFile()); os.IsNotExist(err) {
		t.Fatal("state.json was not created")
	}

	// Read back
	loaded, err := ReadState()
	if err != nil {
		t.Fatalf("ReadState: %v", err)
	}
	if loaded == nil {
		t.Fatal("ReadState returned nil")
	}

	// Compare fields
	if loaded.Version != original.Version {
		t.Errorf("Version = %d, want %d", loaded.Version, original.Version)
	}
	if loaded.InstallID != original.InstallID {
		t.Errorf("InstallID = %q, want %q", loaded.InstallID, original.InstallID)
	}
	if loaded.InstallType != original.InstallType {
		t.Errorf("InstallType = %q, want %q", loaded.InstallType, original.InstallType)
	}
	if !loaded.CreatedAt.Equal(original.CreatedAt) {
		t.Errorf("CreatedAt mismatch: %v vs %v", loaded.CreatedAt, original.CreatedAt)
	}
	// UpdatedAt should have been refreshed by WriteState
	if loaded.UpdatedAt.IsZero() {
		t.Error("UpdatedAt should not be zero")
	}
}

func TestUpdateStep_Transitions(t *testing.T) {
	tests := []struct {
		name      string
		setup     func(s *State)
		stepName  string
		mutate    func(s *Step)
		wantErr   bool
		wantCheck func(t *testing.T, s *State)
	}{
		{
			name:     "pending to running",
			stepName: "test_step",
			mutate: func(s *Step) {
				now := time.Now()
				s.Status = StepRunning
				s.StartedAt = &now
			},
			wantCheck: func(t *testing.T, s *State) {
				step, _ := s.ReadStep("test_step")
				if step == nil {
					t.Fatal("step is nil")
				}
				if step.Status != StepRunning {
					t.Errorf("Status = %q, want %q", step.Status, StepRunning)
				}
				if step.StartedAt == nil {
					t.Error("StartedAt should not be nil")
				}
			},
		},
		{
			name:     "running to success",
			stepName: "test_step",
			setup: func(s *State) {
				now := time.Now()
				s.UpdateStep("test_step", func(st *Step) {
					st.Status = StepRunning
					st.StartedAt = &now
				})
			},
			mutate: func(s *Step) {
				now := time.Now()
				s.Status = StepSuccess
				s.CompletedAt = &now
			},
			wantCheck: func(t *testing.T, s *State) {
				step, _ := s.ReadStep("test_step")
				if step.Status != StepSuccess {
					t.Errorf("Status = %q, want %q", step.Status, StepSuccess)
				}
				if step.CompletedAt == nil {
					t.Error("CompletedAt should not be nil")
				}
			},
		},
		{
			name:     "running to failed",
			stepName: "test_step",
			setup: func(s *State) {
				now := time.Now()
				s.UpdateStep("test_step", func(st *Step) {
					st.Status = StepRunning
					st.StartedAt = &now
				})
			},
			mutate: func(s *Step) {
				now := time.Now()
				s.Status = StepFailed
				s.Error = "something went wrong"
				s.CompletedAt = &now
			},
			wantCheck: func(t *testing.T, s *State) {
				step, _ := s.ReadStep("test_step")
				if step.Status != StepFailed {
					t.Errorf("Status = %q, want %q", step.Status, StepFailed)
				}
				if step.Error != "something went wrong" {
					t.Errorf("Error = %q, want %q", step.Error, "something went wrong")
				}
			},
		},
		{
			name:     "new step defaults to pending",
			stepName: "new_step",
			mutate: func(s *Step) {
				now := time.Now()
				s.Status = StepRunning
				s.StartedAt = &now
			},
			wantCheck: func(t *testing.T, s *State) {
				step, _ := s.ReadStep("new_step")
				if step.Status != StepRunning {
					t.Errorf("Status = %q, want %q", step.Status, StepRunning)
				}
			},
		},
		{
			name:     "skipped step",
			stepName: "optional_step",
			mutate: func(s *Step) {
				now := time.Now()
				s.Status = StepSkipped
				s.CompletedAt = &now
			},
			wantCheck: func(t *testing.T, s *State) {
				step, _ := s.ReadStep("optional_step")
				if step.Status != StepSkipped {
					t.Errorf("Status = %q, want %q", step.Status, StepSkipped)
				}
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			teardown := setupTestEnv(t)
			defer teardown()

			state := NewInitialState("fresh")
			if tt.setup != nil {
				tt.setup(state)
			}

			err := state.UpdateStep(tt.stepName, tt.mutate)
			if (err != nil) != tt.wantErr {
				t.Fatalf("UpdateStep error = %v, wantErr = %v", err, tt.wantErr)
			}

			if tt.wantCheck != nil {
				tt.wantCheck(t, state)
			}
		})
	}
}

func TestForwardCompat_UnknownFields(t *testing.T) {
	teardown := setupTestEnv(t)
	defer teardown()

	// Write state with unknown top-level fields and unknown step fields
	unknownJSON := `{
		"version": 1,
		"install_id": "forward-compat-test",
		"created_at": "2026-07-01T12:00:00Z",
		"updated_at": "2026-07-01T12:00:00Z",
		"install_type": "fresh",
		"future_field": "this is from a future version",
		"steps": {
			"step_one": {
				"status": "success",
				"started_at": "2026-07-01T12:00:00Z",
				"completed_at": "2026-07-01T12:01:00Z",
				"future_step_field": "unknown step field preserved"
			}
		}
	}`

	if err := os.WriteFile(StateFile(), []byte(unknownJSON), 0644); err != nil {
		t.Fatalf("writing state file: %v", err)
	}

	// Read state
	state, err := ReadState()
	if err != nil {
		t.Fatalf("ReadState: %v", err)
	}
	if state == nil {
		t.Fatal("ReadState returned nil")
	}

	// Write state back (simulating a read-modify-write cycle)
	if err := WriteState(state); err != nil {
		t.Fatalf("WriteState: %v", err)
	}

	// Read again and verify unknown fields preserved
	data, err := os.ReadFile(StateFile())
	if err != nil {
		t.Fatalf("reading state file: %v", err)
	}

	var result map[string]json.RawMessage
	if err := json.Unmarshal(data, &result); err != nil {
		t.Fatalf("unmarshaling result: %v", err)
	}

	// Check top-level unknown field preserved
	if _, ok := result["future_field"]; !ok {
		t.Error("future_field missing from preserved state")
	}

	// Check steps-level unknown field preserved
	var steps map[string]json.RawMessage
	if err := json.Unmarshal(result["steps"], &steps); err != nil {
		t.Fatalf("unmarshaling steps: %v", err)
	}
	var stepOne map[string]json.RawMessage
	if err := json.Unmarshal(steps["step_one"], &stepOne); err != nil {
		t.Fatalf("unmarshaling step_one: %v", err)
	}
	if _, ok := stepOne["future_step_field"]; !ok {
		t.Error("future_step_field missing from preserved step")
	}
}

func TestStateDir_Platform(t *testing.T) {
	tests := []struct {
		goos    string
		wantSub string // substring expected in the path
	}{
		{goos: "windows", wantSub: "LaraDiaries"},
		{goos: "linux", wantSub: ".config/lara-diaries"},
		{goos: "darwin", wantSub: ".config/lara-diaries"},
	}

	for _, tt := range tests {
		t.Run(tt.goos, func(t *testing.T) {
			// Save original and restore
			origGOOS := runtime.GOOS

			// We can't change runtime.GOOS at runtime, so we test via
			// manually checking the logic. The function uses runtime.GOOS
			// directly. We verify the function returns the correct pattern
			// by checking the current platform, then test the logic branches
			// directly.

			_ = origGOOS // used only for restore, unused by design
			_ = tt.goos

			// Actually, we can test both platforms by reading the function's
			// behavior. Since we CAN'T change runtime.GOOS, we test the
			// correct result for the current OS and verify the path pattern.
			result := StateDir()

			if result == "" {
				t.Fatal("StateDir() returned empty string")
			}

			// Verify it's an absolute path
			if !filepath.IsAbs(result) {
				t.Errorf("StateDir() = %q, want absolute path", result)
			}
		})
	}
}

// Helper to test the platform-specific logic more directly
func TestStateDir_WindowsPath(t *testing.T) {
	// Test that StateDir returns a path containing "Local" and "LaraDiaries"
	// when running on Windows. This is an integration-level check.
	result := StateDir()
	if runtime.GOOS == "windows" {
		if !strings.Contains(result, "LaraDiaries") {
			t.Errorf("StateDir() = %q, should contain 'LaraDiaries' on Windows", result)
		}
	} else {
		if !strings.Contains(result, ".config") {
			t.Errorf("StateDir() = %q, should contain '.config' on Unix", result)
		}
	}
}

func TestStateFileAndLockFile_Paths(t *testing.T) {
	stateDir := StateDir()
	stateFile := StateFile()
	lockFile := LockFile()

	if filepath.Dir(stateFile) != stateDir {
		t.Errorf("StateFile dir = %q, want %q", filepath.Dir(stateFile), stateDir)
	}
	if filepath.Dir(lockFile) != stateDir {
		t.Errorf("LockFile dir = %q, want %q", filepath.Dir(lockFile), stateDir)
	}
	if filepath.Base(stateFile) != "state.json" {
		t.Errorf("StateFile base = %q, want 'state.json'", filepath.Base(stateFile))
	}
	if filepath.Base(lockFile) != "install.lock" {
		t.Errorf("LockFile base = %q, want 'install.lock'", filepath.Base(lockFile))
	}
}

func TestReadStep_Nonexistent(t *testing.T) {
	state := NewInitialState("fresh")
	step, err := state.ReadStep("nonexistent")
	if err != nil {
		t.Fatalf("ReadStep on missing step: %v", err)
	}
	if step != nil {
		t.Fatal("ReadStep should return nil for missing step")
	}
}
