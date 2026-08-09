package cli

import (
	"strconv"
	"strings"

	"github.com/mecattaf/crm/internal/db"
	"github.com/mecattaf/crm/internal/db/repo"
	crmformat "github.com/mecattaf/crm/internal/format"
	"github.com/mecattaf/crm/internal/model"
	"github.com/spf13/cobra"
)

var findColumns = []crmformat.ColumnDef{
	{Header: "TYPE", Field: "type"},
	{Header: "REF", Field: "ref"},
	{Header: "NAME", Field: "name"},
	{Header: "DETAIL", Field: "detail"},
	{Header: "RANK", Field: "rank"},
}

type findOptions struct {
	entityType string
	limit      int
	format     string
}

func newFindCmd(root *rootOptions) *cobra.Command {
	options := &findOptions{}
	command := &cobra.Command{
		Use:   "find <query>",
		Short: "Search across CRM entities",
		Args: func(command *cobra.Command, arguments []string) error {
			if err := cobra.ExactArgs(1)(command, arguments); err != nil {
				return err
			}
			if strings.TrimSpace(arguments[0]) == "" {
				return model.NewExitError(model.ErrValidation, "find query must not be empty")
			}

			options.entityType = strings.TrimSpace(options.entityType)
			if options.entityType != "" && !model.ValidFindType(options.entityType) {
				return model.NewExitError(
					model.ErrValidation,
					"invalid find type %q (accepted: %s)",
					options.entityType,
					strings.Join(model.FindTypes, ","),
				)
			}
			if options.limit <= 0 {
				return model.NewExitError(model.ErrValidation, "limit must be positive")
			}

			_, _, err := resolveEntityFormat(command, options.format)
			return err
		},
		Example: `  crm find "nick kima"
  crm find dataroom --type interaction --limit 5
  crm find kima --format ids`,
		RunE: func(command *cobra.Command, arguments []string) error {
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

			results, err := repo.NewSearchRepo(database).Find(
				command.Context(),
				arguments[0],
				model.FindFilters{Type: options.entityType, Limit: options.limit},
			)
			if err != nil {
				return err
			}

			return writeFindResults(command, results, selected, terminal)
		},
	}
	command.Flags().StringVar(
		&options.entityType,
		"type",
		"",
		"filter by entity type ("+strings.Join(model.FindTypes, "|")+")",
	)
	command.Flags().IntVar(&options.limit, "limit", 20, "maximum results to return")
	command.Flags().StringVar(
		&options.format,
		"format",
		"",
		"output format ("+crmformat.AcceptedList(crmformat.EntityFormats())+")",
	)

	return command
}

func writeFindResults(
	command *cobra.Command,
	results []model.FindResult,
	selected crmformat.Format,
	terminal bool,
) error {
	rows := make([]crmformat.Row, 0, len(results))
	for _, result := range results {
		rows = append(rows, crmformat.Row{
			JSON: result,
			Ref:  result.Ref,
			Cells: map[string]string{
				"type":   result.Type,
				"ref":    result.Ref,
				"name":   result.Name,
				"detail": result.Detail,
				"rank":   strconv.FormatFloat(result.Rank, 'f', 6, 64),
			},
		})
	}

	return crmformat.WriteRecords(
		command.OutOrStdout(),
		rows,
		crmformat.Options{
			Format:   selected,
			Terminal: terminal,
			Columns:  findColumns,
		},
	)
}
