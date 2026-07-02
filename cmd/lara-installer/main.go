package main

import (
	"fmt"
	"os"
)

const version = "0.1.0"

func main() {
	args := os.Args[1:]

	if len(args) == 0 || args[0] == "install" {
		runInstall()
		return
	}

	switch args[0] {
	case "--version":
		fmt.Println(version)
		os.Exit(0)
	case "doctor":
		runDoctor()
	default:
		fmt.Fprintf(os.Stderr, "Unknown command: %s\n", args[0])
		fmt.Fprintf(os.Stderr, "Usage: lara-installer [install|doctor|--version]\n")
		os.Exit(1)
	}
}
