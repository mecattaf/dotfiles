package cli

import (
	"fmt"
	"strings"

	"github.com/mecattaf/crm/internal/db"
	"github.com/mecattaf/crm/internal/db/repo"
	crmformat "github.com/mecattaf/crm/internal/format"
	"github.com/mecattaf/crm/internal/model"
	"github.com/spf13/cobra"
)

var staleColumns = []crmformat.ColumnDef{
	{Header: "TYPE", Field: "type"},
	{Header: "REF", Field: "ref"},
	{Header: "NAME", Field: "name"},
	{Header: "LAST", Field: "last"},
}

type staleOptions struct {
	days        int
	entityType  string
	recentFirst bool
	format      string
}

func newStaleCmd(root *rootOptions) *cobra.Command {
	options := &staleOptions{}
	command := &cobra.Command{
		Use:   "stale",
		Short: "List contacts or organizations needing outreach",
		Args: func(command *cobra.Command, arguments []string) error {
			if err := cobra.NoArgs(command, arguments); err != nil {
				return err
			}
			if options.days <= 0 {
				return model.NewExitError(model.ErrValidation, "stale days must be positive")
			}
			options.entityType = strings.TrimSpace(options.entityType)
			if !model.ValidStaleType(options.entityType) {
				return model.NewExitError(
					model.ErrValidation,
					"invalid stale type %q (accepted: %s)",
					options.entityType,
					strings.Join(model.StaleTypes, ","),
				)
			}

			_, _, err := resolveEntityFormat(command, options.format)
			return err
		},
		Example: `  crm stale
  crm stale --days 60 --format ids
  crm stale --type org --recent-first`,
		RunE: func(command *cobra.Command, _ []string) error {
			selected, terminal, err := resolveEntityFormat(command, options.format)
			if err != nil {
				return err
			}
			paths, err := root.resolvePaths()
			if err != nil {
				return err
			}
			database, err := db.Open(paths.database)
			if err != nil {
				return err
			}
			defer func() {
				_ = database.Close()
			}()

			results, err := repo.NewReportRepo(database).Stale(
				command.Context(),
				model.StaleFilters{
					Days:        options.days,
					Type:        options.entityType,
					RecentFirst: options.recentFirst,
				},
			)
			if err != nil {
				return err
			}

			return writeStaleResults(command, results, selected, terminal)
		},
	}
	command.Flags().IntVar(&options.days, "days", 90, "positive last-touch threshold in days")
	command.Flags().StringVar(
		&options.entityType,
		"type",
		model.StaleTypeContact,
		"entity type ("+strings.Join(model.StaleTypes, "|")+")",
	)
	command.Flags().BoolVar(
		&options.recentFirst,
		"recent-first",
		false,
		"reverse the worklist order",
	)
	command.Flags().StringVar(
		&options.format,
		"format",
		"",
		"output format ("+crmformat.AcceptedList(crmformat.EntityFormats())+")",
	)
	mustRegisterStaleTypeCompletion(command)

	return command
}

func mustRegisterStaleTypeCompletion(command *cobra.Command) {
	if err := command.RegisterFlagCompletionFunc(
		"type",
		func(_ *cobra.Command, _ []string, toComplete string) ([]string, cobra.ShellCompDirective) {
			matches := make([]string, 0, len(model.StaleTypes))
			for _, entityType := range model.StaleTypes {
				if strings.HasPrefix(entityType, toComplete) {
					matches = append(matches, entityType)
				}
			}

			return matches, cobra.ShellCompDirectiveNoFileComp
		},
	); err != nil {
		panic(fmt.Sprintf("register stale type completion: %v", err))
	}
}

func writeStaleResults(
	command *cobra.Command,
	results []model.StaleResult,
	selected crmformat.Format,
	terminal bool,
) error {
	rows := make([]crmformat.Row, 0, len(results))
	for _, result := range results {
		last := "never"
		if result.Last != nil {
			last = *result.Last
		}
		rows = append(rows, crmformat.Row{
			JSON: result,
			Ref:  result.Ref,
			Cells: map[string]string{
				"type": result.Type,
				"ref":  result.Ref,
				"name": result.Name,
				"last": last,
			},
		})
	}

	return crmformat.WriteRecords(
		command.OutOrStdout(),
		rows,
		crmformat.Options{Format: selected, Terminal: terminal, Columns: staleColumns},
	)
}
