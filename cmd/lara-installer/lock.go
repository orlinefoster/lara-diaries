package main

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"time"
)

// LockStatus represents the state of the install lock file.
type LockStatus int

const (
	// LockStatusNone means no lock file exists.
	LockStatusNone LockStatus = iota
	// LockStatusActive means the lock file exists and the owning PID is alive.
	LockStatusActive
	// LockStatusStale means the lock file exists but the owning PID is dead.
	LockStatusStale
)

// String returns a human-readable label for the lock status.
func (s LockStatus) String() string {
	switch s {
	case LockStatusNone:
		return "none"
	case LockStatusActive:
		return "active"
	case LockStatusStale:
		return "stale"
	default:
		return "unknown"
	}
}

// Lock holds the parsed contents of an install.lock file.
type Lock struct {
	PID       int
	Timestamp time.Time
	Hostname  string
}

// CreateLock atomically creates the lock file.
// Writes to a temporary file first, then renames to the final path
// to prevent readers from seeing partial content.
func CreateLock() error {
	lockPath := LockFile()

	dir := filepath.Dir(lockPath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("creating lock directory %s: %w", dir, err)
	}

	hostname, err := os.Hostname()
	if err != nil {
		hostname = "unknown"
	}

	content := fmt.Sprintf("%d\n%s\n%s\n",
		os.Getpid(),
		timeNow().Format(time.RFC3339),
		hostname,
	)

	// Atomic write: write to temp file, then rename.
	tmpPath := lockPath + ".tmp"
	if err := os.WriteFile(tmpPath, []byte(content), 0644); err != nil {
		return fmt.Errorf("writing temporary lock file: %w", err)
	}
	if err := os.Rename(tmpPath, lockPath); err != nil {
		// Clean up temp file on rename failure.
		_ = os.Remove(tmpPath)
		return fmt.Errorf("renaming lock file: %w", err)
	}

	return nil
}

// ReleaseLock removes the lock file. No error if the file does not exist.
func ReleaseLock() error {
	if err := os.Remove(LockFile()); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("removing lock file: %w", err)
	}
	return nil
}

// ReadLock reads and parses the lock file.
// Returns (nil, nil) if the file does not exist.
// Returns an error if the file exists but cannot be parsed.
func ReadLock() (*Lock, error) {
	f, err := os.Open(LockFile())
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil //nolint: nilnil
		}
		return nil, fmt.Errorf("opening lock file: %w", err)
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	var lines []string
	for scanner.Scan() {
		lines = append(lines, strings.TrimSpace(scanner.Text()))
	}
	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("scanning lock file: %w", err)
	}

	if len(lines) < 3 {
		return nil, fmt.Errorf("lock file has %d lines, expected at least 3", len(lines))
	}

	pid, err := strconv.Atoi(lines[0])
	if err != nil {
		return nil, fmt.Errorf("parsing PID from lock file: %w", err)
	}

	ts, err := time.Parse(time.RFC3339, lines[1])
	if err != nil {
		return nil, fmt.Errorf("parsing timestamp from lock file: %w", err)
	}

	return &Lock{
		PID:       pid,
		Timestamp: ts,
		Hostname:  lines[2],
	}, nil
}

// StaleLockStatus determines whether the lock file exists and if its
// owning process is still alive.
func StaleLockStatus() LockStatus {
	l, err := ReadLock()
	if err != nil || l == nil {
		return LockStatusNone
	}

	alive, err := isProcessAlive(l.PID)
	if err != nil {
		// Treat lookup errors as stale (process table may be gone, etc.)
		return LockStatusStale
	}
	if !alive {
		return LockStatusStale
	}
	return LockStatusActive
}

// isProcessAlive checks the OS process table for the given PID.
func isProcessAlive(pid int) (bool, error) {
	if pid <= 0 {
		return false, nil
	}
	if runtime.GOOS == "windows" {
		return windowsProcessAlive(pid)
	}
	return unixProcessAlive(pid)
}

// unixProcessAlive checks if a process is alive using `kill -0`.
func unixProcessAlive(pid int) (bool, error) {
	cmd := exec.Command("kill", "-0", strconv.Itoa(pid))
	if err := cmd.Run(); err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok && exitErr.ExitCode() == 1 {
			return false, nil
		}
		return false, err
	}
	return true, nil
}

// windowsProcessAlive checks if a process is alive using PowerShell's Get-Process.
func windowsProcessAlive(pid int) (bool, error) {
	cmd := exec.Command("powershell", "-NoProfile", "-Command",
		fmt.Sprintf("if (Get-Process -Id %d -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }", pid))
	if err := cmd.Run(); err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok && exitErr.ExitCode() == 1 {
			return false, nil
		}
		return false, err
	}
	return true, nil
}
