package main

import (
	"fmt"
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
		fmt.Fprintf(os.Stderr, "dcal: %v\n", err)
		os.Exit(exitCode(err))
	}
}
