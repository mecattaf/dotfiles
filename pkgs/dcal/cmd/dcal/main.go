package main

import (
	"os"

	"github.com/mecattaf/dcal/internal/support/log"
)

var (
	Version   = "dev"
	BuildTime = "unknown"
	Commit    = "unknown"
)

func main() {
	log.SetEnvPrefix("DCAL")
	if err := rootCmd.Execute(); err != nil {
		printCommandError(os.Stderr, err)
		os.Exit(exitCode(err))
	}
}
