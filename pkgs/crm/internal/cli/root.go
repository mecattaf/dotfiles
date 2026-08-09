// Package cli defines the crm cobra command tree.
package cli

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/mecattaf/crm/internal/model"
	"github.com/spf13/cobra"
)

const allowMissingDatabase = "crm.mecattaf.dev/allow-missing-database"

type rootOptions struct {
	databasePath string
}

type resolvedPaths struct {
	database string
	base     string
}

// NewRootCmd constructs the root crm command and its persistent behavior.
func NewRootCmd(version string) *cobra.Command {
	options := &rootOptions{}

	root := &cobra.Command{
		Use:           "crm",
		Short:         "Personal git-backed CRM",
		SilenceUsage:  true,
		SilenceErrors: true,
		Version:       version,
	}
	root.SetUsageTemplate(strings.Replace(root.UsageTemplate(), "\nExamples:\n", "\nExample:\n", 1))
	root.SetVersionTemplate("{{.Version}}\n")
	root.PersistentFlags().StringVar(&options.databasePath, "db", "", "path to the CRM database")
	root.PersistentPreRunE = func(cmd *cobra.Command, _ []string) error {
		if cmd == root || cmd.Annotations[allowMissingDatabase] == "true" {
			return nil
		}

		return options.requireDatabase()
	}
	root.PersistentPostRun = func(cmd *cobra.Command, _ []string) {
		runPostWriteHook(cmd, options)
	}

	root.AddCommand(newInitCmd(options))
	registerNounCommand(root, newOrgCmd(options), "o")
	registerNounCommand(root, newContactCmd(options), "c")
	registerNounCommand(root, newInteractionCmd(options), "i")
	registerNounCommand(root, newPipelineCmd(options), "p")
	registerNounCommand(root, newStageCmd(options), "")
	registerNounCommand(root, newDealCmd(options), "d")
	root.AddCommand(newLogCmd(options))
	root.AddCommand(newShowCmd(options))
	root.AddCommand(newFindCmd(options))
	root.AddCommand(newContextCmd(options))
	root.AddCommand(newStatusCmd(options))
	root.AddCommand(newStaleCmd(options))
	root.AddCommand(newDupesCmd(options))
	root.AddCommand(newExportCmd(options))
	root.AddCommand(newImportCmd(options))
	root.AddCommand(newDoctorCmd(options))

	return root
}

// registerNounCommand applies the cross-cutting noun grammar in one place:
// short alias, singular/plural forms, and ls/list on every noun that lists.
func registerNounCommand(root, noun *cobra.Command, shortAlias string) {
	aliases := []string{noun.Name() + "s"}
	if shortAlias != "" {
		aliases = append([]string{shortAlias}, aliases...)
	}
	noun.Aliases = appendUnique(noun.Aliases, aliases...)
	for _, child := range noun.Commands() {
		if child.Name() == "ls" {
			child.Aliases = appendUnique(child.Aliases, "list")
		}
	}
	root.AddCommand(noun)
}

func appendUnique(existing []string, candidates ...string) []string {
	result := append([]string(nil), existing...)
	for _, candidate := range candidates {
		found := false
		for _, value := range result {
			if value == candidate {
				found = true
				break
			}
		}
		if !found {
			result = append(result, candidate)
		}
	}

	return result
}

func (o *rootOptions) resolvePaths() (resolvedPaths, error) {
	databasePath := o.databasePath
	if databasePath == "" {
		databasePath = os.Getenv("CRM_DB")
	}
	if databasePath == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return resolvedPaths{}, fmt.Errorf("resolve home directory: %w", err)
		}
		databasePath = filepath.Join(home, "mecattaf", "notes", "crm", "crm.db")
	}

	databasePath = filepath.Clean(databasePath)
	return resolvedPaths{
		database: databasePath,
		base:     filepath.Dir(databasePath),
	}, nil
}

func (o *rootOptions) requireDatabase() error {
	paths, err := o.resolvePaths()
	if err != nil {
		return err
	}

	info, err := os.Stat(paths.database)
	if errors.Is(err, os.ErrNotExist) {
		return model.NewExitError(
			model.ErrNotFound,
			"no database at %s (run 'crm init')",
			paths.database,
		)
	}
	if err != nil {
		return fmt.Errorf("inspect database %s: %w", paths.database, err)
	}
	if !info.Mode().IsRegular() {
		return model.NewExitError(
			model.ErrNotFound,
			"no database at %s (run 'crm init')",
			paths.database,
		)
	}

	return nil
}
