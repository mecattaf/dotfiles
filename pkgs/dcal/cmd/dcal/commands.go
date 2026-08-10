package main

import (
	"fmt"

	"github.com/spf13/cobra"
)

var rootCmd = &cobra.Command{
	Use:   "dcal",
	Short: "dcal CLI",
	Long:  "dcal — local, Google, Microsoft, CalDAV, and iCloud calendars in one standalone app.",
	Args:  cobra.NoArgs,
}

var versionCmd = &cobra.Command{
	Use:   "version",
	Short: "Show version information",
	RunE: func(_ *cobra.Command, _ []string) error {
		if jsonOutput {
			return printJSON(map[string]string{
				"version":   Version,
				"commit":    Commit,
				"buildTime": BuildTime,
			})
		}
		fmt.Printf("dcal %s (commit %s, built %s)\n", Version, Commit, BuildTime)
		return nil
	},
}

func init() {
	rootCmd.PersistentFlags().BoolVar(&jsonOutput, "json", false, "Output JSON for programmatic usage (where supported)")

	rootCmd.AddCommand(versionCmd)
	rootCmd.AddCommand(daemonCmd)
	rootCmd.AddCommand(ipcCmd)
	rootCmd.AddCommand(accountCmd)
	rootCmd.AddCommand(syncCmd)
	rootCmd.AddCommand(remindersCmd)
	rootCmd.AddCommand(eventsCmd)
}
