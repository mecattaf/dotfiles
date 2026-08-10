package main

import (
	"fmt"

	"github.com/spf13/cobra"
)

var rootCmd = &cobra.Command{
	Use:           "dcal",
	Short:         "dcal CLI",
	Long:          "dcal — local and synced calendars from one ergonomic command line.",
	Args:          cobra.NoArgs,
	SilenceErrors: true,
	SilenceUsage:  true,
	PersistentPreRunE: func(_ *cobra.Command, _ []string) error {
		switch outputFormat {
		case "", "text":
		case "json":
			jsonOutput = true
		default:
			return fmt.Errorf("unsupported format %q (expected text or json)", outputFormat)
		}
		return nil
	},
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
	rootCmd.PersistentFlags().StringVar(&outputFormat, "format", "text", "Output format for read commands: text or json")
	rootCmd.PersistentFlags().BoolVar(&jsonOutput, "json", false, "Output JSON (deprecated: use --format json)")
	_ = rootCmd.PersistentFlags().MarkDeprecated("json", "use --format json")

	rootCmd.AddCommand(versionCmd)
	rootCmd.AddCommand(daemonCmd)
	rootCmd.AddCommand(ipcCmd)
	rootCmd.AddCommand(accountCmd)
	rootCmd.AddCommand(syncCmd)
	rootCmd.AddCommand(remindersCmd)
	rootCmd.AddCommand(eventsCmd)
	rootCmd.AddCommand(calendarCmd)
	rootCmd.AddCommand(addCmd)
	rootCmd.AddCommand(listCmd)
	rootCmd.AddCommand(agendaCmd)
	rootCmd.AddCommand(showCmd)
	rootCmd.AddCommand(editCmd)
	rootCmd.AddCommand(removeCmd)
	rootCmd.AddCommand(doneCmd)
	rootCmd.AddCommand(statusCmd)
}
