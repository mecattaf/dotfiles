package cli

import (
	"database/sql"
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

var stageColumns = []crmformat.ColumnDef{
	{Header: "REF", Field: "ref"},
	{Header: "PIPELINE", Field: "pipeline"},
	{Header: "NAME", Field: "name"},
	{Header: "POSITION", Field: "position"},
	{Header: "ROT DAYS", Field: "rot_days"},
	{Header: "ARCHIVED", Field: "archived_at"},
}

type stageAddOptions struct {
	rotDays int
	after   string
	first   bool
	format  string
}

type stageFormatOptions struct {
	format string
}

func newStageCmd(root *rootOptions) *cobra.Command {
	command := &cobra.Command{
		Use:   "stage",
		Short: "Manage ordered pipeline stages",
		Args:  cobra.NoArgs,
		Example: `  crm stage add p1 contacted --rot 14 --after sourced
  crm stage reorder p1 sourced contacted pitched`,
	}
	command.AddCommand(newStageAddCmd(root))
	command.AddCommand(newStageRenameCmd(root))
	command.AddCommand(newStageReorderCmd(root))
	command.AddCommand(newStageSetRotCmd(root))
	addLifecycleCommands(command, root, resolve.EntityStage)

	return command
}

func newStageAddCmd(root *rootOptions) *cobra.Command {
	options := &stageAddOptions{}
	command := &cobra.Command{
		Use:   "add <pipeline-ref> <name>",
		Short: "Add and position a stage",
		Args:  cobra.ExactArgs(2),
		Example: `  crm stage add p1 sourced
  crm stage add p1 contacted --rot 14 --after sourced
  crm stage add p1 inbox --first`,
		RunE: func(command *cobra.Command, arguments []string) error {
			selected, terminal, err := resolveEntityFormat(command, options.format)
			if err != nil {
				return err
			}
			var rotDays *int
			if command.Flags().Changed("rot") {
				if options.rotDays <= 0 {
					return model.NewExitError(
						model.ErrValidation,
						"rot days must be a positive integer or none",
					)
				}
				rotDays = &options.rotDays
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

			pipeline, err := resolve.Ref(
				command.Context(),
				database,
				resolve.EntityPipeline,
				arguments[0],
			)
			if err != nil {
				return err
			}
			var afterStageID *int64
			if command.Flags().Changed("after") {
				after, resolveErr := resolve.StageRef(
					command.Context(),
					database,
					pipeline.ID,
					options.after,
				)
				if resolveErr != nil {
					return resolveErr
				}
				afterStageID = &after.ID
			}

			stage, err := repo.NewStageRepo(database).Create(
				command.Context(),
				model.CreateStageInput{
					PipelineID:   pipeline.ID,
					Name:         arguments[1],
					RotDays:      rotDays,
					First:        options.first,
					AfterStageID: afterStageID,
				},
			)
			if err != nil {
				return err
			}

			return writeStages(command, []model.Stage{*stage}, selected, terminal)
		},
	}
	markPostWrite(command, string(resolve.EntityStage))
	command.Flags().IntVar(&options.rotDays, "rot", 0, "positive rotting threshold in days")
	command.Flags().StringVar(&options.after, "after", "", "place after this stage in the pipeline")
	command.Flags().BoolVar(&options.first, "first", false, "place first in the pipeline")
	command.MarkFlagsMutuallyExclusive("after", "first")
	addEntityFormatFlag(command, &options.format)

	return command
}

func newStageRenameCmd(root *rootOptions) *cobra.Command {
	options := &stageFormatOptions{}
	command := &cobra.Command{
		Use:   "rename <pipeline-ref> <stage-ref> <new-name>",
		Short: "Rename a stage within its pipeline",
		Args:  cobra.ExactArgs(3),
		Example: `  crm stage rename p1 contacted "first contact"
  crm stage rename "Seed raise" s3 "first contact"`,
		RunE: func(command *cobra.Command, arguments []string) error {
			selected, terminal, database, stage, err := resolveStageCommand(
				command,
				root,
				arguments[0],
				arguments[1],
				options.format,
			)
			if database != nil {
				defer func() {
					_ = database.Close()
				}()
			}
			if err != nil {
				return err
			}

			renamed, err := repo.NewStageRepo(database).Rename(
				command.Context(),
				stage.ID,
				arguments[2],
			)
			if err != nil {
				return err
			}

			return writeStages(command, []model.Stage{*renamed}, selected, terminal)
		},
	}
	markPostWrite(command, string(resolve.EntityStage))
	addEntityFormatFlag(command, &options.format)

	return command
}

func newStageReorderCmd(root *rootOptions) *cobra.Command {
	options := &stageFormatOptions{}
	command := &cobra.Command{
		Use:     "reorder <pipeline-ref> <stage-ref>...",
		Short:   "Replace a pipeline's complete stage order",
		Args:    cobra.MinimumNArgs(2),
		Example: `  crm stage reorder p1 sourced contacted pitched "term sheet" closed`,
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

			pipeline, err := resolve.Ref(
				command.Context(),
				database,
				resolve.EntityPipeline,
				arguments[0],
			)
			if err != nil {
				return err
			}
			stageRepository := repo.NewStageRepo(database)
			liveStages, err := stageRepository.ListByPipeline(command.Context(), pipeline.ID, false)
			if err != nil {
				return err
			}
			liveByID := make(map[int64]model.Stage, len(liveStages))
			for _, stage := range liveStages {
				liveByID[stage.ID] = stage
			}

			orderedIDs := make([]int64, 0, len(arguments)-1)
			seen := make(map[int64]struct{}, len(arguments)-1)
			for _, stageRef := range arguments[1:] {
				match, resolveErr := resolve.StageRef(
					command.Context(),
					database,
					pipeline.ID,
					stageRef,
				)
				if resolveErr != nil {
					return resolveErr
				}
				stage, live := liveByID[match.ID]
				if !live {
					return model.NewExitError(
						model.ErrValidation,
						"stage %s is not a live stage in pipeline %s",
						match.Ref,
						pipeline.Ref,
					)
				}
				if _, duplicate := seen[match.ID]; duplicate {
					return model.NewExitError(
						model.ErrValidation,
						"stage %s (%s) appears more than once in reorder",
						stage.Reference(),
						stage.Name,
					)
				}
				seen[match.ID] = struct{}{}
				orderedIDs = append(orderedIDs, match.ID)
			}

			missing := make([]string, 0)
			for _, stage := range liveStages {
				if _, present := seen[stage.ID]; !present {
					missing = append(missing, stage.Name)
				}
			}
			if len(missing) > 0 {
				return model.NewExitError(
					model.ErrValidation,
					"stage reorder for pipeline %s must list every live stage exactly once — missing: %s",
					pipeline.Ref,
					strings.Join(missing, ", "),
				)
			}

			stages, err := stageRepository.Reorder(command.Context(), pipeline.ID, orderedIDs)
			if err != nil {
				return err
			}

			return writeStages(command, stages, selected, terminal)
		},
	}
	markPostWrite(command, string(resolve.EntityStage))
	addEntityFormatFlag(command, &options.format)

	return command
}

func newStageSetRotCmd(root *rootOptions) *cobra.Command {
	options := &stageFormatOptions{}
	command := &cobra.Command{
		Use:   "set-rot <pipeline-ref> <stage-ref> <days|none>",
		Short: "Set or clear a stage rotting threshold",
		Args:  cobra.ExactArgs(3),
		Example: `  crm stage set-rot p1 pitched 7
  crm stage set-rot p1 pitched none`,
		RunE: func(command *cobra.Command, arguments []string) error {
			rotDays, err := parseRotDays(arguments[2])
			if err != nil {
				return err
			}
			selected, terminal, database, stage, err := resolveStageCommand(
				command,
				root,
				arguments[0],
				arguments[1],
				options.format,
			)
			if database != nil {
				defer func() {
					_ = database.Close()
				}()
			}
			if err != nil {
				return err
			}

			updated, err := repo.NewStageRepo(database).SetRot(
				command.Context(),
				stage.ID,
				rotDays,
			)
			if err != nil {
				return err
			}

			return writeStages(command, []model.Stage{*updated}, selected, terminal)
		},
	}
	markPostWrite(command, string(resolve.EntityStage))
	addEntityFormatFlag(command, &options.format)

	return command
}

func parseRotDays(value string) (*int, error) {
	if strings.EqualFold(strings.TrimSpace(value), "none") {
		return nil, nil
	}
	days, err := strconv.Atoi(value)
	if err != nil || days <= 0 {
		return nil, model.NewExitError(
			model.ErrValidation,
			"rot days must be a positive integer or none",
		)
	}

	return &days, nil
}

func resolveStageCommand(
	command *cobra.Command,
	root *rootOptions,
	pipelineRef string,
	stageRef string,
	requestedFormat string,
) (crmformat.Format, bool, *sql.DB, resolve.Match, error) {
	selected, terminal, err := resolveEntityFormat(command, requestedFormat)
	if err != nil {
		return "", false, nil, resolve.Match{}, err
	}
	paths, err := root.resolvePaths()
	if err != nil {
		return "", false, nil, resolve.Match{}, err
	}
	database, err := db.Open(paths.database)
	if err != nil {
		return "", false, nil, resolve.Match{}, err
	}
	pipeline, err := resolve.Ref(
		command.Context(),
		database,
		resolve.EntityPipeline,
		pipelineRef,
	)
	if err != nil {
		return "", false, database, resolve.Match{}, err
	}
	stage, err := resolve.StageRef(command.Context(), database, pipeline.ID, stageRef)
	if err != nil {
		return "", false, database, resolve.Match{}, err
	}

	return selected, terminal, database, stage, nil
}

func writeStages(
	command *cobra.Command,
	stages []model.Stage,
	selected crmformat.Format,
	terminal bool,
) error {
	rows := make([]crmformat.Row, 0, len(stages))
	for _, stage := range stages {
		rows = append(rows, stageRow(stage))
	}

	err := crmformat.WriteRecords(
		command.OutOrStdout(),
		rows,
		crmformat.Options{
			Format:   selected,
			Terminal: terminal,
			Columns:  stageColumns,
		},
	)
	if err != nil {
		return err
	}
	recordPostWriteRows(command, rows)

	return nil
}

func stageRow(stage model.Stage) crmformat.Row {
	rotDays := "never"
	if stage.RotDays != nil {
		rotDays = strconv.Itoa(*stage.RotDays)
	}

	return crmformat.Row{
		JSON: stage,
		Ref:  stage.Reference(),
		Cells: map[string]string{
			"ref":         stage.Reference(),
			"pipeline":    fmt.Sprintf("p%d", stage.PipelineID),
			"name":        stage.Name,
			"position":    strconv.Itoa(stage.Position),
			"rot_days":    rotDays,
			"archived_at": stringValue(stage.ArchivedAt),
		},
	}
}
