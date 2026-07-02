package main

import (
	"crypto/rand"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"time"
)

// StepStatus represents the lifecycle state of an install step.
type StepStatus string

const (
	StepPending StepStatus = "pending"
	StepRunning StepStatus = "running"
	StepSuccess StepStatus = "success"
	StepFailed  StepStatus = "failed"
	StepSkipped StepStatus = "skipped"
)

// Step holds the known fields of an installation step.
// Unknown fields in the stored JSON are preserved through the
// map-merge technique used in UpdateStep.
type Step struct {
	Status      StepStatus `json:"status"`
	StartedAt   *time.Time `json:"started_at"`
	CompletedAt *time.Time `json:"completed_at"`
	Error       string     `json:"error,omitempty"`
	Rollback    string     `json:"rollback,omitempty"`
}

// State holds the complete installation state.
// Steps uses json.RawMessage values so unknown fields within each
// step object are preserved across read/write cycles.
type State struct {
	Version     int                        `json:"version"`
	InstallID   string                     `json:"install_id"`
	CreatedAt   time.Time                  `json:"created_at"`
	UpdatedAt   time.Time                  `json:"updated_at"`
	InstallType string                     `json:"install_type"`
	Steps       map[string]json.RawMessage `json:"steps"`

	// raw holds the original file bytes so unknown top-level fields
	// are preserved when writing. Populated by ReadState; nil for
	// freshly created states via NewInitialState.
	raw []byte
}

// timeNow is overridable for testing.
var timeNow = time.Now

// StateDir is overridable for testing.
var StateDir = func() string {
	if runtime.GOOS == "windows" {
		localAppData := os.Getenv("LOCALAPPDATA")
		if localAppData == "" {
			localAppData = filepath.Join(os.Getenv("USERPROFILE"), "AppData", "Local")
		}
		return filepath.Join(localAppData, "LaraDiaries")
	}
	home, err := os.UserHomeDir()
	if err != nil {
		home = os.Getenv("HOME")
		if home == "" {
			home = "/tmp" // last-resort fallback
		}
	}
	return filepath.Join(home, ".config", "lara-diaries")
}

// StateFile is overridable for testing.
var StateFile = func() string {
	return filepath.Join(StateDir(), "state.json")
}

// LockFile is overridable for testing.
var LockFile = func() string {
	return filepath.Join(StateDir(), "install.lock")
}

// ReadState reads and parses the state.json file.
// Returns (nil, nil) if the file does not exist.
// Returns an error if the file exists but is unparseable.
func ReadState() (*State, error) {
	path := StateFile()
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil //nolint: nilnil
		}
		return nil, fmt.Errorf("reading state file: %w", err)
	}

	var s State
	if err := json.Unmarshal(data, &s); err != nil {
		return nil, fmt.Errorf("parsing state file: %w", err)
	}
	s.raw = data
	return &s, nil
}

// WriteState marshals the state and writes it to disk.
// Unknown top-level fields from the original file (loaded via ReadState)
// are preserved by merging the known fields into the original JSON.
// Steps-level unknown fields are preserved because Steps is
// map[string]json.RawMessage.
func WriteState(s *State) error {
	s.UpdatedAt = timeNow()

	// Marshal current known state to get the authoritative values.
	knownJSON, err := json.Marshal(s)
	if err != nil {
		return fmt.Errorf("marshaling known state: %w", err)
	}

	var knownMap map[string]json.RawMessage
	if err := json.Unmarshal(knownJSON, &knownMap); err != nil {
		return fmt.Errorf("parsing known state: %w", err)
	}

	// Start from original raw JSON (if available) to preserve unknown
	// top-level fields that may exist from a future version.
	var merged map[string]json.RawMessage
	if s.raw != nil {
		if err := json.Unmarshal(s.raw, &merged); err != nil {
			merged = make(map[string]json.RawMessage)
		}
	} else {
		merged = make(map[string]json.RawMessage)
	}

	// Overlay known fields — this replaces existing keys but leaves
	// unknown keys untouched.
	for k, v := range knownMap {
		merged[k] = v
	}

	data, err := json.MarshalIndent(merged, "", "  ")
	if err != nil {
		return fmt.Errorf("marshaling merged state: %w", err)
	}

	path := StateFile()
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("creating state directory %s: %w", dir, err)
	}
	if err := os.WriteFile(path, data, 0644); err != nil {
		return fmt.Errorf("writing state file: %w", err)
	}
	return nil
}

// NewInitialState creates a fresh State with the given install type.
// Steps is initialized as an empty map (never nil).
func NewInitialState(installType string) *State {
	now := timeNow()
	return &State{
		Version:     1,
		InstallID:   newUUID(),
		CreatedAt:   now,
		UpdatedAt:   now,
		InstallType: installType,
		Steps:       make(map[string]json.RawMessage),
	}
}

// UpdateStep reads a step's raw JSON, applies the mutation function to the
// known Step fields, then writes back the result while preserving any unknown
// fields within the step object.
//
// If the step does not exist, it is created with a default Step{Status: pending}
// before the mutation is applied.
func (s *State) UpdateStep(name string, fn func(*Step)) error {
	raw, exists := s.Steps[name]

	// Build the original map (for roundtrip preservation) and parse known fields.
	var originalMap map[string]interface{}
	var step Step

	if exists {
		// Parse unknown fields into a map for preservation.
		if err := json.Unmarshal(raw, &originalMap); err != nil {
			originalMap = make(map[string]interface{})
		}
		// Parse known fields into the Step struct.
		if err := json.Unmarshal(raw, &step); err != nil {
			step = Step{Status: StepPending}
		}
	} else {
		originalMap = make(map[string]interface{})
		step = Step{Status: StepPending}
	}

	// Apply the mutation.
	fn(&step)

	// Marshal known fields back.
	knownJSON, err := json.Marshal(step)
	if err != nil {
		return fmt.Errorf("marshaling step %s: %w", name, err)
	}

	var knownMap map[string]interface{}
	if err := json.Unmarshal(knownJSON, &knownMap); err != nil {
		return fmt.Errorf("parsing step %s: %w", name, err)
	}

	// Overlay known fields onto the original to preserve unknown fields.
	for k, v := range knownMap {
		originalMap[k] = v
	}

	merged, err := json.Marshal(originalMap)
	if err != nil {
		return fmt.Errorf("marshaling merged step %s: %w", name, err)
	}

	s.Steps[name] = json.RawMessage(merged)
	return nil
}

// ReadStep unmarshals a single step's raw JSON into a Step struct.
// Returns (nil, nil) if the step does not exist.
// A step with only unknown fields will have zero-value Step fields.
func (s *State) ReadStep(name string) (*Step, error) {
	raw, ok := s.Steps[name]
	if !ok {
		return nil, nil //nolint: nilnil
	}
	var step Step
	if err := json.Unmarshal(raw, &step); err != nil {
		return nil, fmt.Errorf("reading step %s: %w", name, err)
	}
	return &step, nil
}

// CompletedSteps returns the step names (in installSteps order) that have
// status StepSuccess. Used by cumulative rollback to know what to undo.
func (s *State) CompletedSteps() []string {
	var completed []string
	for _, step := range installSteps {
		if st, err := s.ReadStep(step.Name); err == nil && st != nil && st.Status == StepSuccess {
			completed = append(completed, step.Name)
		}
	}
	return completed
}

// newUUID generates a UUID v4 string using crypto/rand.
func newUUID() string {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		// crypto/rand.Read only fails on system-level entropy errors.
		panic(fmt.Sprintf("failed to read random bytes for UUID: %v", err))
	}
	// Set version 4 bits.
	b[6] = (b[6] & 0x0f) | 0x40
	// Set variant bits (10xx).
	b[8] = (b[8] & 0x3f) | 0x80
	return fmt.Sprintf("%08x-%04x-%04x-%04x-%012x",
		b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
}
