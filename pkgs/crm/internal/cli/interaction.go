package cli

import (
	"fmt"
	"strings"

	"github.com/mecattaf/crm/internal/db"
	"github.com/mecattaf/crm/internal/db/repo"
	crmformat "github.com/mecattaf/crm/internal/format"
	"github.com/mecattaf/crm/internal/model"
	"github.com/mecattaf/crm/internal/resolve"
	"github.com/spf13/cobra"
)

var interactionTableColumns = []crmformat.ColumnDef{
	{Header: "REF", Field: "ref"},
	{Header: "DATE", Field: "occurred_on"},
	{Header: "KIND", Field: "kind"},
	{Header: "SUMMARY", Field: "summary"},
	{Header: "WITH", Field: "contact_ids"},
	{Header: "ORG", Field: "org_id"},
	{Header: "DEAL", Field: "deal_id"},
	{Header: "TRANSCRIPT", Field: "transcript_path"},
	{Header: "ARCHIVED", Field: "archived_at"},
}

type interactionShowOptions struct {
	format string
}

type interactionListOptions struct {
	with   string
	org    string
	deal   string
	kind   string
	all    bool
	limit  int
	format string
}

type interactionEditOptions struct {
	summary    string
	date       string
	kind       string
	transcript string
	bodyFile   string
	addWith    []string
	removeWith []string
	org        string
	deal       string
	format     string
}

func newInteractionCmd(root *rootOptions) *cobra.Command {
	command := &cobra.Command{
		Use:   "interaction",
		Short: "Read and repair interactions",
		Args:  cobra.NoArgs,
		Example: `  crm interaction show i43
  crm interaction ls --with nick --kind call`,
	}
	command.AddCommand(newInteractionShowCmd(root))
	command.AddCommand(newInteractionListCmd(root))
	command.AddCommand(newInteractionEditCmd(root))
	addLifecycleCommands(command, root, resolve.EntityInteraction)

	return command
}

func newInteractionShowCmd(root *rootOptions) *cobra.Command {
	options := &interactionShowOptions{}
	command := &cobra.Command{
		Use:   "show <ref>",
		Short: "Show an interaction",
		Args:  cobra.ExactArgs(1),
		Example: `  crm interaction show i43
  crm i show i43 --format json`,
		RunE: func(command *cobra.Command, arguments []string) error {
			return showInteraction(command, root, arguments[0], options.format)
		},
	}
	command.Flags().StringVar(
		&options.format,
		"format",
		"",
		"output format ("+crmformat.AcceptedList(crmformat.EntityFormats())+")",
	)

	return command
}

func showInteraction(
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
		resolve.EntityInteraction,
		ref,
	)
	if err != nil {
		return err
	}
	interaction, err := repo.NewInteractionRepo(database).FindByID(
		command.Context(),
		match.ID,
	)
	if err != nil {
		return err
	}

	return writeInteractions(
		command,
		[]model.Interaction{*interaction},
		selected,
		terminal,
	)
}

func newInteractionListCmd(root *rootOptions) *cobra.Command {
	options := &interactionListOptions{}
	command := &cobra.Command{
		Use:   "ls",
		Short: "List interactions",
		Args:  cobra.NoArgs,
		Example: `  crm interaction ls --with nick --kind call
  crm interaction ls --org kima --limit 20 --format json`,
		RunE: func(command *cobra.Command, _ []string) error {
			selected, terminal, err := resolveEntityFormat(command, options.format)
			if err != nil {
				return err
			}
			if options.limit < 0 {
				return model.NewExitError(model.ErrValidation, "limit must not be negative")
			}
			kind, err := normalizeInteractionKind(options.kind, false)
			if err != nil {
				return err
			}
			for _, filter := range []struct {
				name  string
				value string
			}{
				{name: "with", value: options.with},
				{name: "org", value: options.org},
				{name: "deal", value: options.deal},
			} {
				if command.Flags().Changed(filter.name) && strings.TrimSpace(filter.value) == "" {
					return model.NewExitError(
						model.ErrValidation,
						"--%s filter must not be empty",
						filter.name,
					)
				}
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

			filters := model.InteractionFilters{All: options.all, Limit: options.limit}
			if kind != "" {
				filters.Kind = &kind
			}
			if command.Flags().Changed("with") {
				match, resolveErr := resolve.Ref(
					command.Context(),
					database,
					resolve.EntityContact,
					options.with,
				)
				if resolveErr != nil {
					return resolveErr
				}
				filters.ContactID = &match.ID
			}
			if command.Flags().Changed("org") {
				match, resolveErr := resolve.Ref(
					command.Context(),
					database,
					resolve.EntityOrg,
					options.org,
				)
				if resolveErr != nil {
					return resolveErr
				}
				filters.OrgID = &match.ID
			}
			if command.Flags().Changed("deal") {
				match, resolveErr := resolve.Ref(
					command.Context(),
					database,
					resolve.EntityDeal,
					options.deal,
				)
				if resolveErr != nil {
					return resolveErr
				}
				filters.DealID = &match.ID
			}

			interactions, err := repo.NewInteractionRepo(database).List(
				command.Context(),
				filters,
			)
			if err != nil {
				return err
			}

			return writeInteractions(command, interactions, selected, terminal)
		},
	}

	command.Flags().StringVar(&options.with, "with", "", "filter by contact ref")
	command.Flags().StringVar(&options.org, "org", "", "filter by organization ref")
	command.Flags().StringVar(&options.deal, "deal", "", "filter by deal ref")
	command.Flags().StringVar(
		&options.kind,
		"kind",
		"",
		"filter by interaction kind ("+strings.Join(model.InteractionKinds, ",")+")",
	)
	command.Flags().BoolVar(&options.all, "all", false, "include archived interactions")
	command.Flags().IntVar(&options.limit, "limit", 0, "maximum interactions to return (0 means all)")
	command.Flags().StringVar(
		&options.format,
		"format",
		"",
		"output format ("+crmformat.AcceptedList(crmformat.EntityFormats())+")",
	)
	mustRegisterInteractionKindCompletion(command)

	return command
}

func newInteractionEditCmd(root *rootOptions) *cobra.Command {
	options := &interactionEditOptions{}
	command := &cobra.Command{
		Use:   "edit <ref>",
		Short: "Repair an interaction",
		Args:  cobra.ExactArgs(1),
		Example: `  crm interaction edit i43 --summary "corrected summary"
  crm interaction edit i43 --add-with jean --rm-with nick`,
		RunE: func(command *cobra.Command, arguments []string) error {
			selected, terminal, err := resolveEntityFormat(command, options.format)
			if err != nil {
				return err
			}
			input := model.UpdateInteractionInput{}
			if command.Flags().Changed("summary") {
				summary := strings.TrimSpace(options.summary)
				if summary == "" {
					return model.NewExitError(
						model.ErrValidation,
						"interaction summary must not be empty",
					)
				}
				input.Summary = &summary
			}
			if command.Flags().Changed("kind") {
				kind, kindErr := normalizeInteractionKind(options.kind, true)
				if kindErr != nil {
					return kindErr
				}
				input.Kind = &kind
			}
			if command.Flags().Changed("date") {
				occurredOn, dateErr := model.NormalizeDate(options.date)
				if dateErr != nil {
					return dateErr
				}
				input.OccurredOn = &occurredOn
			}

			paths, err := root.resolvePaths()
			if err != nil {
				return err
			}
			if command.Flags().Changed("transcript") {
				var transcriptPath *string
				if strings.TrimSpace(options.transcript) != "" {
					stored, pathErr := resolveTranscriptPath(paths.base, options.transcript)
					if pathErr != nil {
						return pathErr
					}
					transcriptPath = &stored
				}
				input.TranscriptPath = &transcriptPath
			}
			if command.Flags().Changed("body-file") {
				body, bodyErr := readBodyFile(command.InOrStdin(), options.bodyFile)
				if bodyErr != nil {
					return bodyErr
				}
				input.Body = &body
			}

			database, err := db.Open(paths.database)
			if err != nil {
				return err
			}
			defer func() {
				_ = database.Close()
			}()

			interactionMatch, err := resolve.Ref(
				command.Context(),
				database,
				resolve.EntityInteraction,
				arguments[0],
			)
			if err != nil {
				return err
			}
			input.AddContactIDs, err = resolveContactLinkIDs(
				command.Context(),
				database,
				options.addWith,
				"--add-with",
			)
			if err != nil {
				return err
			}
			input.RemoveContactIDs, err = resolveContactLinkIDs(
				command.Context(),
				database,
				options.removeWith,
				"--rm-with",
			)
			if err != nil {
				return err
			}
			if command.Flags().Changed("org") {
				var orgID *int64
				if strings.TrimSpace(options.org) != "" {
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
				input.OrgID = &orgID
			}
			if command.Flags().Changed("deal") {
				var dealID *int64
				if strings.TrimSpace(options.deal) != "" {
					match, resolveErr := resolve.LinkRef(
						command.Context(),
						database,
						resolve.EntityDeal,
						options.deal,
					)
					if resolveErr != nil {
						return resolveErr
					}
					dealID = &match.ID
				}
				input.DealID = &dealID
			}

			interaction, err := repo.NewInteractionRepo(database).Update(
				command.Context(),
				interactionMatch.ID,
				input,
			)
			if err != nil {
				return err
			}

			return writeInteractions(
				command,
				[]model.Interaction{*interaction},
				selected,
				terminal,
			)
		},
	}
	markPostWrite(command, string(resolve.EntityInteraction))

	command.Flags().StringVar(&options.summary, "summary", "", "replacement interaction summary")
	command.Flags().StringVar(&options.date, "date", "", "replacement interaction date (YYYY-MM-DD)")
	command.Flags().StringVar(
		&options.kind,
		"kind",
		"",
		"replacement interaction kind ("+strings.Join(model.InteractionKinds, ",")+")",
	)
	command.Flags().StringVar(&options.transcript, "transcript", "", "replacement transcript path (empty clears)")
	command.Flags().StringVar(&options.bodyFile, "body-file", "", "replace body from path or - for stdin")
	command.Flags().StringArrayVar(&options.addWith, "add-with", nil, "add a contact ref (repeatable)")
	command.Flags().StringArrayVar(&options.removeWith, "rm-with", nil, "remove a contact ref (repeatable)")
	command.Flags().StringVar(&options.org, "org", "", "organization ref (empty clears)")
	command.Flags().StringVar(&options.deal, "deal", "", "deal ref (empty clears)")
	command.Flags().StringVar(
		&options.format,
		"format",
		"",
		"output format ("+crmformat.AcceptedList(crmformat.EntityFormats())+")",
	)
	mustRegisterInteractionKindCompletion(command)

	return command
}

func writeInteractions(
	command *cobra.Command,
	interactions []model.Interaction,
	selected crmformat.Format,
	terminal bool,
) error {
	rows := make([]crmformat.Row, 0, len(interactions))
	for _, interaction := range interactions {
		rows = append(rows, interactionRow(interaction))
	}

	err := crmformat.WriteRecords(
		command.OutOrStdout(),
		rows,
		crmformat.Options{
			Format:   selected,
			Terminal: terminal,
			Columns:  interactionTableColumns,
		},
	)
	if err != nil {
		return err
	}
	recordPostWriteRows(command, rows)

	return nil
}

func interactionRow(interaction model.Interaction) crmformat.Row {
	contactRefs := make([]string, len(interaction.ContactIDs))
	for index, contactID := range interaction.ContactIDs {
		contactRefs[index] = fmt.Sprintf("c%d", contactID)
	}

	return crmformat.Row{
		JSON: interaction,
		Ref:  interaction.Reference(),
		Cells: map[string]string{
			"ref":             interaction.Reference(),
			"occurred_on":     interaction.OccurredOn,
			"kind":            interaction.Kind,
			"summary":         interaction.Summary,
			"contact_ids":     strings.Join(contactRefs, ","),
			"org_id":          prefixedOptionalID("o", interaction.OrgID),
			"deal_id":         prefixedOptionalID("d", interaction.DealID),
			"transcript_path": stringValue(interaction.TranscriptPath),
			"archived_at":     stringValue(interaction.ArchivedAt),
		},
	}
}

func prefixedOptionalID(prefix string, id *int64) string {
	if id == nil {
		return ""
	}

	return fmt.Sprintf("%s%d", prefix, *id)
}
