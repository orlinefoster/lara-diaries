package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestCreateLock_CreatesFile(t *testing.T) {
	teardown := setupTestEnv(t)
	defer teardown()

	frozen := time.Date(2026, 7, 1, 12, 0, 0, 0, time.UTC)
	timeNow = func() time.Time { return frozen }
	defer func() { timeNow = time.Now }()

	if err := CreateLock(); err != nil {
		t.Fatalf("CreateLock: %v", err)
	}

	// Verify file exists
	if _, err := os.Stat(LockFile()); os.IsNotExist(err) {
		t.Fatal("lock file was not created")
	}

	// Read and verify content
	data, err := os.ReadFile(LockFile())
	if err != nil {
		t.Fatalf("reading lock file: %v", err)
	}

	lines := strings.Split(strings.TrimSpace(string(data)), "\n")
	if len(lines) < 3 {
		t.Fatalf("expected at least 3 lines, got %d", len(lines))
	}

	// Line 1: PID (should be our PID)
	if lines[0] == "" {
		t.Error("PID line is empty")
	}

	// Line 2: Timestamp (RFC3339)
	_, err = time.Parse(time.RFC3339, strings.TrimSpace(lines[1]))
	if err != nil {
		t.Errorf("timestamp not parseable as RFC3339: %v", err)
	}

	// Line 3: Hostname
	if strings.TrimSpace(lines[2]) == "" {
		t.Error("hostname is empty")
	}
}

func TestCreateLock_CreatesDirectory(t *testing.T) {
	teardown := setupTestEnv(t)
	defer teardown()

	// Remove the test dir to verify CreateLock creates it
	os.RemoveAll(StateDir())

	if err := CreateLock(); err != nil {
		t.Fatalf("CreateLock: %v", err)
	}

	if _, err := os.Stat(StateDir()); os.IsNotExist(err) {
		t.Fatal("CreateLock should create the state directory")
	}
}

func TestReleaseLock_RemovesFile(t *testing.T) {
	teardown := setupTestEnv(t)
	defer teardown()

	if err := CreateLock(); err != nil {
		t.Fatalf("CreateLock: %v", err)
	}

	if err := ReleaseLock(); err != nil {
		t.Fatalf("ReleaseLock: %v", err)
	}

	if _, err := os.Stat(LockFile()); !os.IsNotExist(err) {
		t.Fatal("lock file should not exist after ReleaseLock")
	}
}

func TestReleaseLock_NoErrorOnMissing(t *testing.T) {
	teardown := setupTestEnv(t)
	defer teardown()

	if err := ReleaseLock(); err != nil {
		t.Fatalf("ReleaseLock on missing file: %v", err)
	}
}

func TestReadLock_ParsesContent(t *testing.T) {
	teardown := setupTestEnv(t)
	defer teardown()

	frozen := time.Date(2026, 7, 1, 12, 0, 0, 0, time.UTC)
	timeNow = func() time.Time { return frozen }
	defer func() { timeNow = time.Now }()

	if err := CreateLock(); err != nil {
		t.Fatalf("CreateLock: %v", err)
	}

	lock, err := ReadLock()
	if err != nil {
		t.Fatalf("ReadLock: %v", err)
	}
	if lock == nil {
		t.Fatal("ReadLock returned nil")
	}

	if lock.PID <= 0 {
		t.Errorf("PID = %d, want > 0", lock.PID)
	}
	if lock.Hostname == "" {
		t.Error("Hostname should not be empty")
	}
}

func TestReadLock_NotExist(t *testing.T) {
	teardown := setupTestEnv(t)
	defer teardown()

	lock, err := ReadLock()
	if err != nil {
		t.Fatalf("ReadLock on missing file: %v", err)
	}
	if lock != nil {
		t.Fatal("ReadLock should return nil for missing file")
	}
}

func TestReadLock_InvalidContent(t *testing.T) {
	teardown := setupTestEnv(t)
	defer teardown()

	dir := StateDir()
	os.MkdirAll(dir, 0755)
	if err := os.WriteFile(filepath.Join(dir, "install.lock"), []byte("not-enough-lines"), 0644); err != nil {
		t.Fatalf("writing lock file: %v", err)
	}

	_, err := ReadLock()
	if err == nil {
		t.Fatal("ReadLock should error on invalid content")
	}
}

func TestStaleLockStatus_None(t *testing.T) {
	teardown := setupTestEnv(t)
	defer teardown()

	status := StaleLockStatus()
	if status != LockStatusNone {
		t.Errorf("StaleLockStatus = %v, want %v", status, LockStatusNone)
	}
}

func TestStaleLockStatus_Active(t *testing.T) {
	teardown := setupTestEnv(t)
	defer teardown()

	// Create lock with our own PID — it's definitely alive
	if err := CreateLock(); err != nil {
		t.Fatalf("CreateLock: %v", err)
	}

	status := StaleLockStatus()
	if status != LockStatusActive {
		t.Errorf("StaleLockStatus = %v, want %v", status, LockStatusActive)
	}
}

func TestStaleLockStatus_Stale(t *testing.T) {
	teardown := setupTestEnv(t)
	defer teardown()

	// Write a lock file with a PID that doesn't exist
	dir := StateDir()
	os.MkdirAll(dir, 0755)
	content := "99999\n2024-01-01T00:00:00Z\ndead-host\n"
	if err := os.WriteFile(filepath.Join(dir, "install.lock"), []byte(content), 0644); err != nil {
		t.Fatalf("writing lock file: %v", err)
	}

	status := StaleLockStatus()
	if status != LockStatusStale {
		t.Errorf("StaleLockStatus = %v, want %v", status, LockStatusStale)
	}
}

func TestLockStatus_String(t *testing.T) {
	tests := []struct {
		status LockStatus
		want   string
	}{
		{LockStatusNone, "none"},
		{LockStatusActive, "active"},
		{LockStatusStale, "stale"},
		{LockStatus(99), "unknown"},
	}

	for _, tt := range tests {
		t.Run(tt.want, func(t *testing.T) {
			if got := tt.status.String(); got != tt.want {
				t.Errorf("LockStatus(%d).String() = %q, want %q", tt.status, got, tt.want)
			}
		})
	}
}

func TestLock_AtomicWrite(t *testing.T) {
	teardown := setupTestEnv(t)
	defer teardown()

	// CreateLock uses atomic write (temp file + rename)
	if err := CreateLock(); err != nil {
		t.Fatalf("CreateLock: %v", err)
	}

	// Verify no .tmp file remains
	tmpFiles, _ := filepath.Glob(filepath.Join(StateDir(), "*.tmp"))
	if len(tmpFiles) > 0 {
		t.Errorf("temporary files remain after lock creation: %v", tmpFiles)
	}
}
