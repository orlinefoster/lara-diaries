package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

const version = "0.1.0"

func main() {
	args := os.Args[1:]

	if len(args) == 0 || args[0] == "install" {
		// Check for --config flag
		for i, arg := range args {
			if arg == "--config" && i+1 < len(args) {
				configPath := args[i+1]
				data, err := os.ReadFile(configPath)
				if err != nil {
					fmt.Fprintf(os.Stderr, "[FAIL] Could not read config file: %v\n", err)
					os.Exit(1)
				}
				globalJSONConfig = strings.TrimSpace(string(data))
				break
			}
		}
		runInstall()
		return
	}

	switch args[0] {
	case "--version":
		fmt.Println(version)
		os.Exit(0)
	case "doctor":
		runDoctor()
	case "--help", "-h":
		printUsage()
	default:
		fmt.Fprintf(os.Stderr, "Unknown command: %s\n", args[0])
		printUsage()
		os.Exit(1)
	}
}

func printUsage() {
	exe := filepath.Base(os.Args[0])
	fmt.Printf(`%[1]s — Lara Diaries Installer v%s

Usage:
  %[1]s install [--config <file>]   Run the installer (default)
  %[1]s doctor                       System health check
  %[1]s --version                    Show version
  %[1]s --help                       Show this help

Flags:
  --config <file>   JSON config file for non-interactive install
                    (omit for interactive wizard)

Examples:
  %[1]s install
  %[1]s install --config /path/to/config.json
  %[1]s doctor
`, exe, version)
}

func init() {
	// Register --config parsing before main runs
	// (handled in main() directly)
}
