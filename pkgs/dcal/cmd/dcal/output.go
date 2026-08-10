package main

import (
	"encoding/json"
	"fmt"
	"os"
)

var jsonOutput bool
var outputFormat string

func printJSON(v any) error {
	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	return enc.Encode(v)
}

// infof prints progress, prompts, and notices. Stdout is reserved for data.
func infof(format string, args ...any) {
	fmt.Fprintf(os.Stderr, format+"\n", args...)
}
