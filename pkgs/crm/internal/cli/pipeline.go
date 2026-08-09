package cli

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/mecattaf/crm/internal/db"
	"github.com/mecattaf/crm/internal/db/repo"
	crmformat "github.com/mecattaf/crm/internal/format"
	"github.com/mecattaf/crm/internal/model"
	"github.com/mecattaf/crm/internal/resolve"
	"github.com/spf13/cobra"
)

var pipelineColumns = []crmformat.ColumnDef{
	{Header: "REF", Field: "ref"},
	{Header: "NAME", Field: "name"},
	{Header: "POSITION", Field: "position"},
	{Header: "STAGES", Field: "stages"},
	{Header: "ARCHIVED", Field: "archived_at"},
}

type pipelineFormatOptions struct {
	format string
}

type pipelineListOptions struct {
	all    bool
	format string
}

func newPipelineCmd(root *rootOptions) *cobra.Command {
	command := &cobra.Command{
		Use:   "pipeline",
		Short: "Manage pipelines",
		Args:  cobra.NoArgs,
		Example: `  crm pipeline add "Seed raise"
  crm pipeline show p1`,
	}
	command.AddCommand(newPipelineAddCmd(root))
	command.AddCommand(newPipelineListCmd(root))
	command.AddCommand(newPipelineShowCmd(root))
	command.AddCommand(newPipelineRenameCmd(root))
	addLifecycleCommands(command, root, resolve.EntityPipeline)

	return command
}

func newPipelineAddCmd(root *rootOptions) *cobra.Command {
	options := &pipelineFormatOptions{}
	command := &cobra.Command{
		Use:   "add <name>",
		Short: "Add a pipeline",
		Args:  cobra.ExactArgs(1),
		Example: `  crm pipeline add "Seed raise"
  crm pipeline add "Customer motion" --format json`,
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

			pipeline, err := repo.NewPipelineRepo(database).Create(
				command.Context(),
				arguments[0],
			)
			if err != nil {
				return err
			}

			return writePipelines(command, []model.Pipeline{*pipeline}, selected, terminal)
		},
	}
	markPostWrite(command, string(resolve.EntityPipeline))
	addEntityFormatFlag(command, &options.format)

	return command
}

func newPipelineListCmd(root *rootOptions) *cobra.Command {
	options := &pipelineListOptions{}
	command := &cobra.Command{
		Use:   "ls",
		Short: "List pipelines",
		Args:  cobra.NoArgs,
		Example: `  crm pipeline ls
  crm pipeline ls --all --format json`,
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

			pipelines, err := repo.NewPipelineRepo(database).List(
				command.Context(),
				options.all,
			)
			if err != nil {
				return err
			}

			return writePipelines(command, pipelines, selected, terminal)
		},
	}
	command.Flags().BoolVar(&options.all, "all", false, "include archived pipelines")
	addEntityFormatFlag(command, &options.format)

	return command
}

func newPipelineShowCmd(root *rootOptions) *cobra.Command {
	options := &pipelineFormatOptions{}
	command := &cobra.Command{
		Use:   "show <ref>",
		Short: "Show a pipeline and its ordered stages",
		Args:  cobra.ExactArgs(1),
		Example: `  crm pipeline show p1
  crm p show "Seed raise" --format json`,
		RunE: func(command *cobra.Command, arguments []string) error {
			return showPipeline(command, root, arguments[0], options.format)
		},
	}
	addEntityFormatFlag(command, &options.format)

	return command
}

func showPipeline(
	command *cobra.Command,
	root *rootOptions,
	ref string,
	requestedFormat string,
) error {
	selected, terminal, err := resolveEntityFormat(command, requestedFormat)
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

	match, err := resolve.Ref(command.Context(), database, resolve.EntityPipeline, ref)
	if err != nil {
		return err
	}
	pipeline, err := repo.NewPipelineRepo(database).FindByID(command.Context(), match.ID)
	if err != nil {
		return err
	}

	return writePipelines(command, []model.Pipeline{*pipeline}, selected, terminal)
}

func newPipelineRenameCmd(root *rootOptions) *cobra.Command {
	options := &pipelineFormatOptions{}
	command := &cobra.Command{
		Use:   "rename <ref> <new-name>",
		Short: "Rename a pipeline",
		Args:  cobra.ExactArgs(2),
		Example: `  crm pipeline rename p1 "Seed round"
  crm pipeline rename "Seed raise" "Seed round"`,
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

			match, err := resolve.Ref(
				command.Context(),
				database,
				resolve.EntityPipeline,
				arguments[0],
			)
			if err != nil {
				return err
			}
			pipeline, err := repo.NewPipelineRepo(database).Rename(
				command.Context(),
				match.ID,
				arguments[1],
			)
			if err != nil {
				return err
			}

			return writePipelines(command, []model.Pipeline{*pipeline}, selected, terminal)
		},
	}
	markPostWrite(command, string(resolve.EntityPipeline))
	addEntityFormatFlag(command, &options.format)

	return command
}

func addEntityFormatFlag(command *cobra.Command, target *string) {
	command.Flags().StringVar(
		target,
		"format",
		"",
		"output format ("+crmformat.AcceptedList(crmformat.EntityFormats())+")",
	)
}

func writePipelines(
	command *cobra.Command,
	pipelines []model.Pipeline,
	selected crmformat.Format,
	terminal bool,
) error {
	rows := make([]crmformat.Row, 0, len(pipelines))
	for _, pipeline := range pipelines {
		rows = append(rows, pipelineRow(pipeline))
	}

	err := crmformat.WriteRecords(
		command.OutOrStdout(),
		rows,
		crmformat.Options{
			Format:   selected,
			Terminal: terminal,
			Columns:  pipelineColumns,
		},
	)
	if err != nil {
		return err
	}
	recordPostWriteRows(command, rows)

	return nil
}

func pipelineRow(pipeline model.Pipeline) crmformat.Row {
	return crmformat.Row{
		JSON: pipeline,
		Ref:  pipeline.Reference(),
		Cells: map[string]string{
			"ref":         pipeline.Reference(),
			"name":        pipeline.Name,
			"position":    strconv.Itoa(pipeline.Position),
			"stages":      pipelineStageSummary(pipeline.Stages),
			"archived_at": stringValue(pipeline.ArchivedAt),
		},
	}
}

func pipelineStageSummary(stages []model.Stage) string {
	values := make([]string, 0, len(stages))
	for _, stage := range stages {
		threshold := "never"
		if stage.RotDays != nil {
			threshold = fmt.Sprintf("%dd", *stage.RotDays)
		}
		values = append(
			values,
			fmt.Sprintf("%s %s (rot %s)", stage.Reference(), stage.Name, threshold),
		)
	}

	return strings.Join(values, "; ")
}
