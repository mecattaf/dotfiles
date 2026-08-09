package cli

import (
	"context"
	"database/sql"
	"errors"
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

var dealColumns = []crmformat.ColumnDef{
	{Header: "REF", Field: "ref"},
	{Header: "TITLE", Field: "title"},
	{Header: "ORG", Field: "org_id"},
	{Header: "CONTACT", Field: "contact_id"},
	{Header: "PIPELINE", Field: "pipeline"},
	{Header: "STAGE", Field: "stage"},
	{Header: "STATUS", Field: "status"},
	{Header: "REASON", Field: "outcome_reason"},
	{Header: "CLOSED", Field: "closed_at"},
	{Header: "DAYS", Field: "days_in_stage"},
	{Header: "ROT", Field: "rot_days"},
	{Header: "ARCHIVED", Field: "archived_at"},
}

type dealAddOptions struct {
	pipeline string
	stage    string
	org      string
	contact  string
	format   string
}

type dealShowOptions struct {
	format string
}

type dealListOptions struct {
	pipeline string
	stage    string
	status   string
	rotting  bool
	all      bool
	limit    int
	format   string
}

type dealEditOptions struct {
	title   string
	org     string
	contact string
	format  string
}

type dealMoveOptions struct {
	note   string
	format string
}

type dealCloseOptions struct {
	reason string
	format string
}

func newDealCmd(root *rootOptions) *cobra.Command {
	command := &cobra.Command{
		Use:   "deal",
		Short: "Manage stage-only opportunities",
		Args:  cobra.NoArgs,
		Example: `  crm deal add "Kima seed ticket" --pipeline "Seed raise" --org kima
  crm deal move d1 pitched --note "deck sent"`,
	}
	command.AddCommand(newDealAddCmd(root))
	command.AddCommand(newDealShowCmd(root))
	command.AddCommand(newDealListCmd(root))
	command.AddCommand(newDealEditCmd(root))
	command.AddCommand(newDealMoveCmd(root))
	command.AddCommand(newDealCloseCmd(root, "win"))
	command.AddCommand(newDealCloseCmd(root, "lose"))
	command.AddCommand(newDealReopenCmd(root))
	addLifecycleCommands(command, root, resolve.EntityDeal)

	return command
}

func newDealAddCmd(root *rootOptions) *cobra.Command {
	options := &dealAddOptions{}
	command := &cobra.Command{
		Use:   "add <title>",
		Short: "Add a deal in a pipeline",
		Args:  cobra.ExactArgs(1),
		Example: `  crm deal add "Kima seed ticket" --pipeline "Seed raise" --org kima
  crm deal add "Nick ticket" --pipeline p1 --contact nick --stage sourced`,
		RunE: func(command *cobra.Command, arguments []string) error {
			selected, terminal, err := resolveEntityFormat(command, options.format)
			if err != nil {
				return err
			}
			if strings.TrimSpace(options.pipeline) == "" {
				return model.NewExitError(model.ErrValidation, "--pipeline is required")
			}
			orgSupplied := command.Flags().Changed("org")
			contactSupplied := command.Flags().Changed("contact")
			if !orgSupplied && !contactSupplied {
				return model.NewExitError(
					model.ErrValidation,
					"deal add requires at least one of --org or --contact",
				)
			}
			if orgSupplied && strings.TrimSpace(options.org) == "" {
				return model.NewExitError(model.ErrValidation, "--org must not be empty")
			}
			if contactSupplied && strings.TrimSpace(options.contact) == "" {
				return model.NewExitError(model.ErrValidation, "--contact must not be empty")
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
				options.pipeline,
			)
			if err != nil {
				return err
			}
			stageID, err := resolveOpeningStage(
				command.Context(),
				database,
				pipeline,
				options.stage,
				command.Flags().Changed("stage"),
			)
			if err != nil {
				return err
			}
			var orgID *int64
			if orgSupplied {
				match, resolveErr := resolve.LinkRef(
					command.Context(),
					database,
					resolve.EntityOrg,
					options.org,
				)
				if resolveErr != nil {
					return resolveErr
				}
				orgID = &match.ID
			}
			var contactID *int64
			if contactSupplied {
				match, resolveErr := resolve.LinkRef(
					command.Context(),
					database,
					resolve.EntityContact,
					options.contact,
				)
				if resolveErr != nil {
					return resolveErr
				}
				contactID = &match.ID
			}

			deal, err := repo.NewDealRepo(database).Create(
				command.Context(),
				model.CreateDealInput{
					Title:      arguments[0],
					OrgID:      orgID,
					ContactID:  contactID,
					PipelineID: pipeline.ID,
					StageID:    stageID,
				},
			)
			if err != nil {
				return err
			}

			return writeDeals(command, []model.Deal{*deal}, selected, terminal)
		},
	}
	markPostWrite(command, string(resolve.EntityDeal))
	command.Flags().StringVar(&options.pipeline, "pipeline", "", "pipeline ref (required)")
	command.Flags().StringVar(&options.stage, "stage", "", "opening stage ref (default first)")
	command.Flags().StringVar(&options.org, "org", "", "organization ref")
	command.Flags().StringVar(&options.contact, "contact", "", "contact ref")
	addEntityFormatFlag(command, &options.format)

	return command
}

func resolveOpeningStage(
	ctx context.Context,
	database *sql.DB,
	pipeline resolve.Match,
	rawStage string,
	stageSupplied bool,
) (int64, error) {
	if stageSupplied {
		if strings.TrimSpace(rawStage) == "" {
			return 0, model.NewExitError(model.ErrValidation, "--stage must not be empty")
		}
		stage, err := resolve.StageRef(ctx, database, pipeline.ID, rawStage)
		if err != nil {
			return 0, err
		}

		return stage.ID, nil
	}

	stages, err := repo.NewStageRepo(database).ListByPipeline(ctx, pipeline.ID, false)
	if err != nil {
		return 0, err
	}
	if len(stages) == 0 {
		return 0, model.NewExitError(
			model.ErrValidation,
			"pipeline %s has no live stages — add one with: crm stage add %s <name>",
			pipeline.Ref,
			pipeline.Ref,
		)
	}

	return stages[0].ID, nil
}

func newDealShowCmd(root *rootOptions) *cobra.Command {
	options := &dealShowOptions{}
	command := &cobra.Command{
		Use:   "show <ref>",
		Short: "Show a deal with stage history and timeline",
		Args:  cobra.ExactArgs(1),
		Example: `  crm deal show d3
  crm d show "Kima seed" --format json`,
		RunE: func(command *cobra.Command, arguments []string) error {
			return showDeal(command, root, arguments[0], options.format)
		},
	}
	addEntityFormatFlag(command, &options.format)

	return command
}

func showDeal(
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

	match, err := resolve.Ref(
		command.Context(),
		database,
		resolve.EntityDeal,
		ref,
	)
	if err != nil {
		return err
	}
	detail, err := repo.NewDealRepo(database).DetailByID(command.Context(), match.ID)
	if err != nil {
		return err
	}

	return writeDealDetail(command, detail, selected, terminal)
}

func newDealListCmd(root *rootOptions) *cobra.Command {
	options := &dealListOptions{}
	command := &cobra.Command{
		Use:   "ls",
		Short: "List and filter deals",
		Args:  cobra.NoArgs,
		Example: `  crm deal ls --pipeline p1 --stage pitched
  crm deal ls --rotting --format ids`,
		RunE: func(command *cobra.Command, _ []string) error {
			selected, terminal, err := resolveEntityFormat(command, options.format)
			if err != nil {
				return err
			}
			if options.limit < 0 {
				return model.NewExitError(model.ErrValidation, "limit must not be negative")
			}
			pipelineSupplied := command.Flags().Changed("pipeline")
			stageSupplied := command.Flags().Changed("stage")
			if stageSupplied && !pipelineSupplied {
				return model.NewExitError(
					model.ErrValidation,
					"--stage requires --pipeline because stage names are pipeline-scoped",
				)
			}
			if pipelineSupplied && strings.TrimSpace(options.pipeline) == "" {
				return model.NewExitError(model.ErrValidation, "--pipeline filter must not be empty")
			}
			if stageSupplied && strings.TrimSpace(options.stage) == "" {
				return model.NewExitError(model.ErrValidation, "--stage filter must not be empty")
			}
			if command.Flags().Changed("status") && strings.TrimSpace(options.status) == "" {
				return model.NewExitError(model.ErrValidation, "--status filter must not be empty")
			}
			status, err := normalizeDealStatus(options.status, false)
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

			filters := model.DealFilters{
				Rotting: options.rotting,
				All:     options.all,
				Limit:   options.limit,
			}
			if status != "" {
				filters.Status = &status
			}
			if pipelineSupplied {
				pipeline, resolveErr := resolve.Ref(
					command.Context(),
					database,
					resolve.EntityPipeline,
					options.pipeline,
				)
				if resolveErr != nil {
					return resolveErr
				}
				filters.PipelineID = &pipeline.ID
				if stageSupplied {
					stage, stageErr := resolve.StageRef(
						command.Context(),
						database,
						pipeline.ID,
						options.stage,
					)
					if stageErr != nil {
						return stageErr
					}
					filters.StageID = &stage.ID
				}
			}

			deals, err := repo.NewDealRepo(database).List(command.Context(), filters)
			if err != nil {
				return err
			}

			return writeDeals(command, deals, selected, terminal)
		},
	}
	command.Flags().StringVar(&options.pipeline, "pipeline", "", "filter by pipeline ref")
	command.Flags().StringVar(&options.stage, "stage", "", "filter by stage within --pipeline")
	command.Flags().StringVar(
		&options.status,
		"status",
		"",
		"filter by status ("+strings.Join(model.DealStatuses, ",")+")",
	)
	command.Flags().BoolVar(&options.rotting, "rotting", false, "list open deals past their stage threshold")
	command.Flags().BoolVar(&options.all, "all", false, "include archived deals")
	command.Flags().IntVar(&options.limit, "limit", 0, "maximum deals to return (0 means all)")
	addEntityFormatFlag(command, &options.format)
	mustRegisterDealStatusCompletion(command)

	return command
}

func newDealEditCmd(root *rootOptions) *cobra.Command {
	options := &dealEditOptions{}
	command := &cobra.Command{
		Use:   "edit <ref>",
		Short: "Edit deal identity and anchors",
		Args:  cobra.ExactArgs(1),
		Example: `  crm deal edit d3 --title "Kima seed"
  crm deal edit d3 --contact nick --org ""`,
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
				resolve.EntityDeal,
				arguments[0],
			)
			if err != nil {
				return err
			}
			input := model.UpdateDealInput{}
			if command.Flags().Changed("title") {
				input.Title = &options.title
			}
			if command.Flags().Changed("org") {
				var orgID *int64
				if strings.TrimSpace(options.org) != "" {
					org, resolveErr := resolve.LinkRef(
						command.Context(),
						database,
						resolve.EntityOrg,
						options.org,
					)
					if resolveErr != nil {
						return resolveErr
					}
					orgID = &org.ID
				}
				input.OrgID = &orgID
			}
			if command.Flags().Changed("contact") {
				var contactID *int64
				if strings.TrimSpace(options.contact) != "" {
					contact, resolveErr := resolve.LinkRef(
						command.Context(),
						database,
						resolve.EntityContact,
						options.contact,
					)
					if resolveErr != nil {
						return resolveErr
					}
					contactID = &contact.ID
				}
				input.ContactID = &contactID
			}

			deal, err := repo.NewDealRepo(database).Update(command.Context(), match.ID, input)
			if err != nil {
				return err
			}

			return writeDeals(command, []model.Deal{*deal}, selected, terminal)
		},
	}
	markPostWrite(command, string(resolve.EntityDeal))
	command.Flags().StringVar(&options.title, "title", "", "replacement deal title")
	command.Flags().StringVar(&options.org, "org", "", "organization ref (empty clears)")
	command.Flags().StringVar(&options.contact, "contact", "", "contact ref (empty clears)")
	addEntityFormatFlag(command, &options.format)

	return command
}

func newDealMoveCmd(root *rootOptions) *cobra.Command {
	options := &dealMoveOptions{}
	command := &cobra.Command{
		Use:   "move <deal-ref> <stage-ref>",
		Short: "Move a deal to another stage",
		Args:  cobra.ExactArgs(2),
		Example: `  crm deal move d3 pitched
  crm deal move d3 pitched --note "deck sent"`,
		RunE: func(command *cobra.Command, arguments []string) error {
			selected, terminal, database, deal, err := resolveDealCommand(
				command,
				root,
				arguments[0],
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
			stage, err := resolve.StageRef(
				command.Context(),
				database,
				deal.PipelineID,
				arguments[1],
			)
			if err != nil && errors.Is(err, model.ErrNotFound) {
				archivedStage, archivedErr := resolve.ArchivedStageRefForConflict(
					command.Context(),
					database,
					deal.PipelineID,
					arguments[1],
				)
				switch {
				case archivedErr == nil:
					stage = archivedStage
					err = nil
				case errors.Is(archivedErr, model.ErrAmbiguous):
					return archivedErr
				}
			}
			if err != nil {
				return err
			}
			moved, err := repo.NewDealRepo(database).Move(
				command.Context(),
				deal.ID,
				stage.ID,
				options.note,
			)
			if err != nil {
				return err
			}

			return writeDeals(command, []model.Deal{*moved}, selected, terminal)
		},
	}
	markPostWrite(command, string(resolve.EntityDeal))
	command.Flags().StringVar(&options.note, "note", "", "stage transition note")
	addEntityFormatFlag(command, &options.format)

	return command
}

func newDealCloseCmd(root *rootOptions, verb string) *cobra.Command {
	options := &dealCloseOptions{}
	status := "won"
	short := "Win a deal"
	exampleReason := "led the round"
	if verb == "lose" {
		status = "lost"
		short = "Lose a deal"
		exampleReason = "passed — too early"
	}
	command := &cobra.Command{
		Use:     verb + " <ref>",
		Short:   short,
		Args:    cobra.ExactArgs(1),
		Example: fmt.Sprintf("  crm deal %s d3 --reason %q", verb, exampleReason),
		RunE: func(command *cobra.Command, arguments []string) error {
			selected, terminal, database, deal, err := resolveDealCommand(
				command,
				root,
				arguments[0],
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
			closed, err := repo.NewDealRepo(database).Close(
				command.Context(),
				deal.ID,
				status,
				options.reason,
			)
			if err != nil {
				return err
			}

			return writeDeals(command, []model.Deal{*closed}, selected, terminal)
		},
	}
	markPostWrite(command, string(resolve.EntityDeal))
	command.Flags().StringVar(&options.reason, "reason", "", "outcome reason")
	addEntityFormatFlag(command, &options.format)

	return command
}

func newDealReopenCmd(root *rootOptions) *cobra.Command {
	options := &dealShowOptions{}
	command := &cobra.Command{
		Use:     "reopen <ref>",
		Short:   "Return a closed deal to open",
		Args:    cobra.ExactArgs(1),
		Example: `  crm deal reopen d3`,
		RunE: func(command *cobra.Command, arguments []string) error {
			selected, terminal, database, deal, err := resolveDealCommand(
				command,
				root,
				arguments[0],
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
			reopened, err := repo.NewDealRepo(database).Reopen(command.Context(), deal.ID)
			if err != nil {
				return err
			}

			return writeDeals(command, []model.Deal{*reopened}, selected, terminal)
		},
	}
	markPostWrite(command, string(resolve.EntityDeal))
	addEntityFormatFlag(command, &options.format)

	return command
}

func resolveDealCommand(
	command *cobra.Command,
	root *rootOptions,
	dealRef string,
	requestedFormat string,
) (crmformat.Format, bool, *sql.DB, *model.Deal, error) {
	selected, terminal, err := resolveEntityFormat(command, requestedFormat)
	if err != nil {
		return "", false, nil, nil, err
	}
	paths, err := root.resolvePaths()
	if err != nil {
		return "", false, nil, nil, err
	}
	database, err := db.Open(paths.database)
	if err != nil {
		return "", false, nil, nil, err
	}
	match, err := resolve.Ref(command.Context(), database, resolve.EntityDeal, dealRef)
	if err != nil {
		return "", false, database, nil, err
	}
	deal, err := repo.NewDealRepo(database).FindByID(command.Context(), match.ID)
	if err != nil {
		return "", false, database, nil, err
	}

	return selected, terminal, database, deal, nil
}

func normalizeDealStatus(raw string, required bool) (string, error) {
	status := strings.TrimSpace(raw)
	if status == "" && required {
		return "", model.NewExitError(
			model.ErrValidation,
			"deal status is required (accepted: %s)",
			strings.Join(model.DealStatuses, ","),
		)
	}
	if status != "" && !model.ValidDealStatus(status) {
		return "", model.NewExitError(
			model.ErrValidation,
			"invalid deal status %q (accepted: %s)",
			status,
			strings.Join(model.DealStatuses, ","),
		)
	}

	return status, nil
}

func mustRegisterDealStatusCompletion(command *cobra.Command) {
	if err := command.RegisterFlagCompletionFunc(
		"status",
		func(_ *cobra.Command, _ []string, toComplete string) ([]string, cobra.ShellCompDirective) {
			matches := make([]string, 0, len(model.DealStatuses))
			for _, status := range model.DealStatuses {
				if strings.HasPrefix(status, toComplete) {
					matches = append(matches, status)
				}
			}

			return matches, cobra.ShellCompDirectiveNoFileComp
		},
	); err != nil {
		panic(fmt.Sprintf("register deal status completion: %v", err))
	}
}

func writeDeals(
	command *cobra.Command,
	deals []model.Deal,
	selected crmformat.Format,
	terminal bool,
) error {
	rows := make([]crmformat.Row, 0, len(deals))
	for _, deal := range deals {
		rows = append(rows, dealRow(deal, deal))
	}

	err := crmformat.WriteRecords(
		command.OutOrStdout(),
		rows,
		crmformat.Options{Format: selected, Terminal: terminal, Columns: dealColumns},
	)
	if err != nil {
		return err
	}
	recordPostWriteRows(command, rows)

	return nil
}

func writeDealDetail(
	command *cobra.Command,
	detail *model.DealDetail,
	selected crmformat.Format,
	terminal bool,
) error {
	return crmformat.WriteDealDetail(
		command.OutOrStdout(),
		dealRow(detail.Deal, *detail),
		dealColumns,
		detail,
		selected,
		terminal,
	)
}

func dealRow(deal model.Deal, jsonValue any) crmformat.Row {
	rotDays := ""
	if deal.RotDays != nil {
		rotDays = strconv.Itoa(*deal.RotDays)
	}

	return crmformat.Row{
		JSON: jsonValue,
		Ref:  deal.Reference(),
		Cells: map[string]string{
			"ref":            deal.Reference(),
			"title":          deal.Title,
			"org_id":         prefixedOptionalID("o", deal.OrgID),
			"contact_id":     prefixedOptionalID("c", deal.ContactID),
			"pipeline":       fmt.Sprintf("%s (p%d)", deal.Pipeline, deal.PipelineID),
			"stage":          deal.Stage,
			"status":         deal.Status,
			"outcome_reason": stringValue(deal.OutcomeReason),
			"closed_at":      stringValue(deal.ClosedAt),
			"days_in_stage":  strconv.Itoa(deal.DaysInStage),
			"rot_days":       rotDays,
			"archived_at":    stringValue(deal.ArchivedAt),
		},
	}
}
