package cli

import (
	"fmt"
	"math"
	"strconv"
	"strings"

	"github.com/mecattaf/crm/internal/db"
	"github.com/mecattaf/crm/internal/db/repo"
	crmformat "github.com/mecattaf/crm/internal/format"
	"github.com/mecattaf/crm/internal/model"
	"github.com/spf13/cobra"
)

var dupeColumns = []crmformat.ColumnDef{
	{Header: "LEFT", Field: "left"},
	{Header: "RIGHT", Field: "right"},
	{Header: "SCORE", Field: "score"},
	{Header: "REASONS", Field: "reasons"},
}

type dupeOptions struct {
	entityType string
	threshold  float64
	limit      int
	format     string
}

func newDupesCmd(root *rootOptions) *cobra.Command {
	options := &dupeOptions{}
	command := &cobra.Command{
		Use:   "dupes",
		Short: "Find likely duplicate contacts and organizations",
		Args: func(command *cobra.Command, arguments []string) error {
			if err := cobra.NoArgs(command, arguments); err != nil {
				return err
			}
			options.entityType = strings.TrimSpace(options.entityType)
			if options.entityType != "" && !model.ValidDupeType(options.entityType) {
				return model.NewExitError(
					model.ErrValidation,
					"invalid dupes type %q (accepted: %s)",
					options.entityType,
					strings.Join(model.DupeTypes, ","),
				)
			}
			if math.IsNaN(options.threshold) || math.IsInf(options.threshold, 0) ||
				options.threshold < 0 || options.threshold > 1 {
				return model.NewExitError(
					model.ErrValidation,
					"threshold must be between 0 and 1",
				)
			}
			if options.limit < 0 {
				return model.NewExitError(model.ErrValidation, "limit must not be negative")
			}

			_, _, err := resolveDupeFormat(command, options.format)
			return err
		},
		Example: `  crm dupes
  crm dupes --type contact --threshold 0.3 --format json`,
		RunE: func(command *cobra.Command, _ []string) error {
			selected, terminal, err := resolveDupeFormat(command, options.format)
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

			results, err := repo.NewDupeRepo(database).Find(
				command.Context(),
				model.DupeFilters{
					Type:      options.entityType,
					Threshold: options.threshold,
					Limit:     options.limit,
				},
			)
			if err != nil {
				return err
			}

			return writeDupeResults(command, results, selected, terminal)
		},
	}
	command.Flags().StringVar(
		&options.entityType,
		"type",
		"",
		"filter by entity type ("+strings.Join(model.DupeTypes, "|")+")",
	)
	command.Flags().Float64Var(
		&options.threshold,
		"threshold",
		0.3,
		"minimum weighted duplicate score from 0 to 1",
	)
	command.Flags().IntVar(&options.limit, "limit", 0, "maximum pairs to return (0 means all)")
	command.Flags().StringVar(
		&options.format,
		"format",
		"",
		"output format ("+crmformat.AcceptedList(dupeFormats())+")",
	)

	return command
}

func dupeFormats() []crmformat.Format {
	return []crmformat.Format{crmformat.FormatTable, crmformat.FormatJSON}
}

func resolveDupeFormat(
	command *cobra.Command,
	requested string,
) (crmformat.Format, bool, error) {
	terminal := crmformat.IsTerminal(command.OutOrStdout())
	selected, err := crmformat.Resolve(requested, terminal, dupeFormats())
	return selected, terminal, err
}

func writeDupeResults(
	command *cobra.Command,
	results []model.DupeResult,
	selected crmformat.Format,
	terminal bool,
) error {
	rows := make([]crmformat.Row, 0, len(results))
	for _, result := range results {
		rows = append(rows, crmformat.Row{
			JSON: result,
			Cells: map[string]string{
				"left":    dupeRecordLabel(result.Left),
				"right":   dupeRecordLabel(result.Right),
				"score":   strconv.FormatFloat(result.Score, 'f', 2, 64),
				"reasons": strings.Join(result.Reasons, ", "),
			},
		})
	}

	return crmformat.WriteRecords(
		command.OutOrStdout(),
		rows,
		crmformat.Options{Format: selected, Terminal: terminal, Columns: dupeColumns},
	)
}

func dupeRecordLabel(record any) string {
	switch value := record.(type) {
	case model.Contact:
		return fmt.Sprintf("%s %s", value.Reference(), value.Name)
	case model.Org:
		return fmt.Sprintf("%s %s", value.Reference(), value.Name)
	default:
		return fmt.Sprintf("%T", record)
	}
}
