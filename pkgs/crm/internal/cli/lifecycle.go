package cli

import (
	"bufio"
	"context"
	"database/sql"
	"errors"
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/mecattaf/crm/internal/db"
	"github.com/mecattaf/crm/internal/db/repo"
	crmformat "github.com/mecattaf/crm/internal/format"
	"github.com/mecattaf/crm/internal/model"
	"github.com/mecattaf/crm/internal/resolve"
	"github.com/spf13/cobra"
)

type lifecycleOptions struct {
	format string
}

type deleteOptions struct {
	format  string
	confirm bool
}

type resolvedDeleteTarget struct {
	name string
	ref  string
	row  crmformat.Row
}

type deletedOrgRecord struct {
	model.Org
	Deleted bool `json:"deleted"`
}

type deletedContactRecord struct {
	model.Contact
	Deleted bool `json:"deleted"`
}

type deletedInteractionRecord struct {
	model.Interaction
	Deleted bool `json:"deleted"`
}

type deletedPipelineRecord struct {
	model.Pipeline
	Deleted bool `json:"deleted"`
}

type deletedStageRecord struct {
	model.Stage
	Deleted bool `json:"deleted"`
}

type deletedDealRecord struct {
	model.Deal
	Deleted bool `json:"deleted"`
}

func addLifecycleCommands(
	parent *cobra.Command,
	root *rootOptions,
	entity resolve.Entity,
) {
	parent.AddCommand(newLifecycleCmd(root, entity, true))
	parent.AddCommand(newLifecycleCmd(root, entity, false))
	parent.AddCommand(newDeleteCmd(root, entity))
}

func newLifecycleCmd(
	root *rootOptions,
	entity resolve.Entity,
	archive bool,
) *cobra.Command {
	options := &lifecycleOptions{}
	verb := "archive"
	short := "Archive " + lifecycleLabel(entity)
	use := verb + " <ref>"
	example := fmt.Sprintf("  crm %s archive %s1", entity, referencePrefix(entity))
	args := cobra.ExactArgs(1)
	if !archive {
		verb = "unarchive"
		short = "Restore archived " + lifecycleLabel(entity)
		use = verb + " <ref>"
		example = fmt.Sprintf("  crm %s unarchive %s1", entity, referencePrefix(entity))
	}
	if entity == resolve.EntityStage {
		use = verb + " <pipeline-ref> <stage-ref>"
		example = fmt.Sprintf("  crm stage %s p1 s1", verb)
		args = cobra.ExactArgs(2)
	}

	command := &cobra.Command{
		Use:     use,
		Short:   short,
		Args:    args,
		Example: example,
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

			match, err := resolveLifecycleTarget(
				command.Context(),
				database,
				entity,
				arguments,
				false,
			)
			if err != nil && archive && errors.Is(err, model.ErrNotFound) {
				archivedMatch, archivedErr := resolveLifecycleTarget(
					command.Context(),
					database,
					entity,
					arguments,
					true,
				)
				switch {
				case archivedErr == nil:
					return model.NewExitError(
						model.ErrConflict,
						"%s %s is already archived",
						entity,
						archivedMatch.Ref,
					)
				case errors.Is(archivedErr, model.ErrAmbiguous):
					return archivedErr
				}
			}
			if err != nil {
				return err
			}

			row, err := mutateLifecycle(
				command.Context(),
				database,
				entity,
				match.ID,
				archive,
			)
			if err != nil {
				return err
			}

			rows := []crmformat.Row{row}
			if err := crmformat.WriteRecords(
				command.OutOrStdout(),
				rows,
				crmformat.Options{
					Format:   selected,
					Terminal: terminal,
					Columns:  lifecycleColumns(entity),
				},
			); err != nil {
				return err
			}
			recordPostWriteRows(command, rows)

			return nil
		},
	}
	markPostWrite(command, string(entity))
	addEntityFormatFlag(command, &options.format)

	return command
}

func newDeleteCmd(root *rootOptions, entity resolve.Entity) *cobra.Command {
	options := &deleteOptions{}
	use := "delete <ref>"
	example := fmt.Sprintf("  crm %s delete %s1 --confirm", entity, referencePrefix(entity))
	args := cobra.ExactArgs(1)
	if entity == resolve.EntityStage {
		use = "delete <pipeline-ref> <stage-ref>"
		example = "  crm stage delete p1 s1 --confirm"
		args = cobra.ExactArgs(2)
	}

	command := &cobra.Command{
		Use:     use,
		Short:   "Permanently delete " + lifecycleLabel(entity),
		Args:    args,
		Example: example,
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

			match, err := resolveLifecycleTarget(
				command.Context(),
				database,
				entity,
				arguments,
				false,
			)
			if err != nil {
				return err
			}
			target, err := loadDeleteTarget(
				command.Context(),
				database,
				entity,
				match.ID,
			)
			if err != nil {
				return err
			}
			if err := requireDeleteConfirmation(command, options.confirm, entity, target); err != nil {
				return err
			}
			if err := deleteEntity(command.Context(), database, entity, match.ID); err != nil {
				return err
			}

			rows := []crmformat.Row{target.row}
			if err := crmformat.WriteRecords(
				command.OutOrStdout(),
				rows,
				crmformat.Options{
					Format:   selected,
					Terminal: terminal,
					Columns:  deleteColumns(entity),
				},
			); err != nil {
				return err
			}
			recordPostWriteRows(command, rows)

			return nil
		},
	}
	markPostWrite(command, string(entity))
	command.Flags().BoolVar(
		&options.confirm,
		"confirm",
		false,
		"confirm irreversible deletion without prompting",
	)
	addEntityFormatFlag(command, &options.format)

	return command
}

func requireDeleteConfirmation(
	command *cobra.Command,
	confirmed bool,
	entity resolve.Entity,
	target resolvedDeleteTarget,
) error {
	if confirmed {
		return nil
	}
	if !crmformat.IsTerminal(os.Stdin) {
		return model.NewExitError(
			model.ErrValidation,
			"refusing to delete without --confirm (non-interactive)",
		)
	}

	terminal, err := os.Open("/dev/tty")
	if err != nil {
		return fmt.Errorf("open /dev/tty for delete confirmation: %w", err)
	}
	defer func() {
		_ = terminal.Close()
	}()

	return readDeleteConfirmation(
		terminal,
		command.ErrOrStderr(),
		entity,
		target.name,
		target.ref,
	)
}

func readDeleteConfirmation(
	input io.Reader,
	messages io.Writer,
	entity resolve.Entity,
	name string,
	ref string,
) error {
	if _, err := fmt.Fprintf(messages, "Delete %s %q (%s)? [y/N] ", entity, name, ref); err != nil {
		return fmt.Errorf("write delete confirmation: %w", err)
	}

	answer, err := bufio.NewReader(input).ReadString('\n')
	if err != nil && !errors.Is(err, io.EOF) {
		return fmt.Errorf("read delete confirmation: %w", err)
	}
	answer = strings.TrimSpace(answer)
	if strings.EqualFold(answer, "y") || strings.EqualFold(answer, "yes") {
		return nil
	}

	return model.NewExitError(model.ErrValidation, "delete cancelled")
}

func resolveLifecycleTarget(
	ctx context.Context,
	database *sql.DB,
	entity resolve.Entity,
	arguments []string,
	archivedConflictProbe bool,
) (resolve.Match, error) {
	if entity != resolve.EntityStage {
		if archivedConflictProbe {
			return resolve.ArchivedRefForConflict(ctx, database, entity, arguments[0])
		}

		return resolve.Ref(ctx, database, entity, arguments[0])
	}

	pipeline, err := resolve.Ref(ctx, database, resolve.EntityPipeline, arguments[0])
	if err != nil {
		return resolve.Match{}, err
	}
	if archivedConflictProbe {
		return resolve.ArchivedStageRefForConflict(
			ctx,
			database,
			pipeline.ID,
			arguments[1],
		)
	}

	return resolve.StageRef(ctx, database, pipeline.ID, arguments[1])
}

func loadDeleteTarget(
	ctx context.Context,
	database *sql.DB,
	entity resolve.Entity,
	id int64,
) (resolvedDeleteTarget, error) {
	switch entity {
	case resolve.EntityOrg:
		record, err := repo.NewOrgRepo(database).FindByID(ctx, id)
		if err != nil {
			return resolvedDeleteTarget{}, err
		}
		row := organizationRow(*record)
		row.JSON = deletedOrgRecord{Org: *record, Deleted: true}

		return newResolvedDeleteTarget(record.Name, record.Reference(), row), nil
	case resolve.EntityContact:
		record, err := repo.NewContactRepo(database).FindByID(ctx, id)
		if err != nil {
			return resolvedDeleteTarget{}, err
		}
		row := contactRow(*record)
		row.JSON = deletedContactRecord{Contact: *record, Deleted: true}

		return newResolvedDeleteTarget(record.Name, record.Reference(), row), nil
	case resolve.EntityInteraction:
		record, err := repo.NewInteractionRepo(database).FindByID(ctx, id)
		if err != nil {
			return resolvedDeleteTarget{}, err
		}
		row := interactionRow(*record)
		row.JSON = deletedInteractionRecord{Interaction: *record, Deleted: true}

		return newResolvedDeleteTarget(record.Summary, record.Reference(), row), nil
	case resolve.EntityPipeline:
		record, err := repo.NewPipelineRepo(database).FindByID(ctx, id)
		if err != nil {
			return resolvedDeleteTarget{}, err
		}
		row := pipelineRow(*record)
		row.JSON = deletedPipelineRecord{Pipeline: *record, Deleted: true}

		return newResolvedDeleteTarget(record.Name, record.Reference(), row), nil
	case resolve.EntityStage:
		record, err := repo.NewStageRepo(database).FindByID(ctx, id)
		if err != nil {
			return resolvedDeleteTarget{}, err
		}
		row := stageRow(*record)
		row.JSON = deletedStageRecord{Stage: *record, Deleted: true}

		return newResolvedDeleteTarget(record.Name, record.Reference(), row), nil
	case resolve.EntityDeal:
		record, err := repo.NewDealRepo(database).FindByID(ctx, id)
		if err != nil {
			return resolvedDeleteTarget{}, err
		}
		row := dealRow(*record, *record)
		row.JSON = deletedDealRecord{Deal: *record, Deleted: true}

		return newResolvedDeleteTarget(record.Title, record.Reference(), row), nil
	default:
		return resolvedDeleteTarget{}, model.NewExitError(
			model.ErrValidation,
			"unsupported delete entity %q",
			entity,
		)
	}
}

func newResolvedDeleteTarget(name, ref string, row crmformat.Row) resolvedDeleteTarget {
	row.Cells["deleted"] = "true"

	return resolvedDeleteTarget{name: name, ref: ref, row: row}
}

func deleteEntity(
	ctx context.Context,
	database *sql.DB,
	entity resolve.Entity,
	id int64,
) error {
	switch entity {
	case resolve.EntityOrg:
		return repo.NewOrgRepo(database).Delete(ctx, id)
	case resolve.EntityContact:
		return repo.NewContactRepo(database).Delete(ctx, id)
	case resolve.EntityInteraction:
		return repo.NewInteractionRepo(database).Delete(ctx, id)
	case resolve.EntityPipeline:
		return repo.NewPipelineRepo(database).Delete(ctx, id)
	case resolve.EntityStage:
		return repo.NewStageRepo(database).Delete(ctx, id)
	case resolve.EntityDeal:
		return repo.NewDealRepo(database).Delete(ctx, id)
	default:
		return model.NewExitError(
			model.ErrValidation,
			"unsupported delete entity %q",
			entity,
		)
	}
}

func mutateLifecycle(
	ctx context.Context,
	database *sql.DB,
	entity resolve.Entity,
	id int64,
	archive bool,
) (crmformat.Row, error) {
	switch entity {
	case resolve.EntityOrg:
		repository := repo.NewOrgRepo(database)
		var organization *model.Org
		var err error
		if archive {
			organization, err = repository.Archive(ctx, id)
		} else {
			organization, err = repository.Unarchive(ctx, id)
		}
		if err != nil {
			return crmformat.Row{}, err
		}

		return organizationRow(*organization), nil
	case resolve.EntityContact:
		repository := repo.NewContactRepo(database)
		var contact *model.Contact
		var err error
		if archive {
			contact, err = repository.Archive(ctx, id)
		} else {
			contact, err = repository.Unarchive(ctx, id)
		}
		if err != nil {
			return crmformat.Row{}, err
		}

		return contactRow(*contact), nil
	case resolve.EntityInteraction:
		repository := repo.NewInteractionRepo(database)
		var interaction *model.Interaction
		var err error
		if archive {
			interaction, err = repository.Archive(ctx, id)
		} else {
			interaction, err = repository.Unarchive(ctx, id)
		}
		if err != nil {
			return crmformat.Row{}, err
		}

		return interactionRow(*interaction), nil
	case resolve.EntityPipeline:
		repository := repo.NewPipelineRepo(database)
		var pipeline *model.Pipeline
		var err error
		if archive {
			pipeline, err = repository.Archive(ctx, id)
		} else {
			pipeline, err = repository.Unarchive(ctx, id)
		}
		if err != nil {
			return crmformat.Row{}, err
		}

		return pipelineRow(*pipeline), nil
	case resolve.EntityStage:
		repository := repo.NewStageRepo(database)
		var stage *model.Stage
		var err error
		if archive {
			stage, err = repository.Archive(ctx, id)
		} else {
			stage, err = repository.Unarchive(ctx, id)
		}
		if err != nil {
			return crmformat.Row{}, err
		}

		return stageRow(*stage), nil
	case resolve.EntityDeal:
		repository := repo.NewDealRepo(database)
		var deal *model.Deal
		var err error
		if archive {
			deal, err = repository.Archive(ctx, id)
		} else {
			deal, err = repository.Unarchive(ctx, id)
		}
		if err != nil {
			return crmformat.Row{}, err
		}

		return dealRow(*deal, *deal), nil
	default:
		return crmformat.Row{}, model.NewExitError(
			model.ErrValidation,
			"unsupported lifecycle entity %q",
			entity,
		)
	}
}

func lifecycleColumns(entity resolve.Entity) []crmformat.ColumnDef {
	switch entity {
	case resolve.EntityOrg:
		return orgColumns
	case resolve.EntityContact:
		return contactColumns
	case resolve.EntityInteraction:
		return interactionTableColumns
	case resolve.EntityPipeline:
		return pipelineColumns
	case resolve.EntityStage:
		return stageColumns
	case resolve.EntityDeal:
		return dealColumns
	default:
		return nil
	}
}

func deleteColumns(entity resolve.Entity) []crmformat.ColumnDef {
	columns := append([]crmformat.ColumnDef(nil), lifecycleColumns(entity)...)

	return append(columns, crmformat.ColumnDef{Header: "DELETED", Field: "deleted"})
}

func referencePrefix(entity resolve.Entity) string {
	switch entity {
	case resolve.EntityOrg:
		return "o"
	case resolve.EntityContact:
		return "c"
	case resolve.EntityInteraction:
		return "i"
	case resolve.EntityPipeline:
		return "p"
	case resolve.EntityStage:
		return "s"
	case resolve.EntityDeal:
		return "d"
	default:
		return ""
	}
}

func lifecycleLabel(entity resolve.Entity) string {
	if entity == resolve.EntityOrg {
		return "organization"
	}

	return string(entity)
}
