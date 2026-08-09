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

var orgColumns = []crmformat.ColumnDef{
	{Header: "REF", Field: "ref"},
	{Header: "NAME", Field: "name"},
	{Header: "CATEGORY", Field: "category"},
	{Header: "WEBSITE", Field: "website"},
	{Header: "LINKEDIN", Field: "linkedin"},
	{Header: "LOCATION", Field: "location"},
	{Header: "FOCUS", Field: "focus"},
	{Header: "HINT", Field: "relationship_hint"},
	{Header: "ARCHIVED", Field: "archived_at"},
}

type orgAddOptions struct {
	category string
	website  string
	linkedIn string
	location string
	focus    string
	context  string
	hint     string
	sources  []string
	details  []string
	format   string
}

type orgListOptions struct {
	category string
	all      bool
	limit    int
	format   string
}

type orgShowOptions struct {
	format string
}

type orgEditOptions struct {
	category      string
	website       string
	linkedIn      string
	location      string
	focus         string
	context       string
	contextAppend string
	hint          string
	sources       []string
	details       []string
	format        string
}

func newOrgCmd(options *rootOptions) *cobra.Command {
	command := &cobra.Command{
		Use:   "org",
		Short: "Manage organizations",
		Args:  cobra.NoArgs,
		Example: `  crm org add "Kima Ventures" --category vc
  crm org ls --category vc`,
	}
	command.AddCommand(newOrgAddCmd(options))
	command.AddCommand(newOrgListCmd(options))
	command.AddCommand(newOrgShowCmd(options))
	command.AddCommand(newOrgEditCmd(options))
	command.AddCommand(newOrgMergeCmd(options))
	addLifecycleCommands(command, options, resolve.EntityOrg)

	return command
}

func newOrgShowCmd(root *rootOptions) *cobra.Command {
	options := &orgShowOptions{}
	command := &cobra.Command{
		Use:   "show <ref>",
		Short: "Show an organization",
		Args:  cobra.ExactArgs(1),
		Example: `  crm org show kima
  crm org show o4 --format json`,
		RunE: func(command *cobra.Command, arguments []string) error {
			return showOrganization(command, root, arguments[0], options.format)
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

func showOrganization(
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

	match, err := resolve.Ref(command.Context(), database, resolve.EntityOrg, ref)
	if err != nil {
		return err
	}
	organization, err := repo.NewOrgRepo(database).FindByID(command.Context(), match.ID)
	if err != nil {
		return err
	}

	return writeOrganizations(
		command,
		[]model.Org{*organization},
		selected,
		terminal,
	)
}

func newOrgEditCmd(root *rootOptions) *cobra.Command {
	options := &orgEditOptions{}
	command := &cobra.Command{
		Use:   "edit <ref>",
		Short: "Edit an organization",
		Args:  cobra.ExactArgs(1),
		Example: `  crm org edit kima --focus "pre-seed, 2/week pace"
  crm org edit o4 --context-append "Partner meeting booked" --source notes/call.md`,
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
				resolve.EntityOrg,
				arguments[0],
			)
			if err != nil {
				return err
			}

			input := model.UpdateOrgInput{}
			if command.Flags().Changed("category") {
				input.Category = &options.category
			}
			if command.Flags().Changed("website") {
				input.Website = &options.website
			}
			if command.Flags().Changed("linkedin") {
				input.LinkedIn = &options.linkedIn
			}
			if command.Flags().Changed("location") {
				input.Location = &options.location
			}
			if command.Flags().Changed("focus") {
				input.Focus = &options.focus
			}
			if command.Flags().Changed("context") {
				input.Context = &options.context
			}
			if command.Flags().Changed("context-append") {
				input.ContextAppend = &options.contextAppend
			}
			if command.Flags().Changed("hint") {
				input.RelationshipHint = &options.hint
			}
			if command.Flags().Changed("source") {
				input.ProvenanceSources = options.sources
			}
			if command.Flags().Changed("detail") {
				input.ProvenanceDetails = options.details
			}

			organization, err := repo.NewOrgRepo(database).Update(
				command.Context(),
				match.ID,
				input,
			)
			if err != nil {
				return err
			}

			return writeOrganizations(
				command,
				[]model.Org{*organization},
				selected,
				terminal,
			)
		},
	}
	markPostWrite(command, string(resolve.EntityOrg))

	command.Flags().StringVar(&options.category, "category", "", "organization category")
	command.Flags().StringVar(&options.website, "website", "", "organization website")
	command.Flags().StringVar(&options.linkedIn, "linkedin", "", "LinkedIn handle or URL")
	command.Flags().StringVar(&options.location, "location", "", "organization location")
	command.Flags().StringVar(&options.focus, "focus", "", "organization focus")
	command.Flags().StringVar(&options.context, "context", "", "replace the rolling organization dossier")
	command.Flags().StringVar(
		&options.contextAppend,
		"context-append",
		"",
		"append to the rolling dossier with a blank-line separator",
	)
	command.Flags().StringVar(&options.hint, "hint", "", "relationship hint")
	command.Flags().StringArrayVar(&options.sources, "source", nil, "provenance source to append (repeatable)")
	command.Flags().StringArrayVar(&options.details, "detail", nil, "provenance detail to append (repeatable)")
	command.Flags().StringVar(
		&options.format,
		"format",
		"",
		"output format ("+crmformat.AcceptedList(crmformat.EntityFormats())+")",
	)

	return command
}

func newOrgAddCmd(root *rootOptions) *cobra.Command {
	options := &orgAddOptions{}
	command := &cobra.Command{
		Use:   "add <name>",
		Short: "Add an organization",
		Args:  cobra.ExactArgs(1),
		Example: `  crm org add "Kima Ventures" --category vc --website kima.vc \
    --location Paris --hint "met at DLD" --source notes/2026-07-12.md`,
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

			organization, err := repo.NewOrgRepo(database).Create(
				command.Context(),
				model.CreateOrgInput{
					Name:              arguments[0],
					Category:          options.category,
					Website:           options.website,
					LinkedIn:          options.linkedIn,
					Location:          options.location,
					Focus:             options.focus,
					Context:           options.context,
					RelationshipHint:  options.hint,
					ProvenanceSources: options.sources,
					ProvenanceDetails: options.details,
				},
			)
			if err != nil {
				return err
			}

			return writeOrganizations(
				command,
				[]model.Org{*organization},
				selected,
				terminal,
			)
		},
	}
	markPostWrite(command, string(resolve.EntityOrg))

	command.Flags().StringVar(&options.category, "category", "", "organization category")
	command.Flags().StringVar(&options.website, "website", "", "organization website")
	command.Flags().StringVar(&options.linkedIn, "linkedin", "", "LinkedIn handle or URL")
	command.Flags().StringVar(&options.location, "location", "", "organization location")
	command.Flags().StringVar(&options.focus, "focus", "", "organization focus")
	command.Flags().StringVar(&options.context, "context", "", "rolling organization dossier")
	command.Flags().StringVar(&options.hint, "hint", "", "relationship hint")
	command.Flags().StringArrayVar(&options.sources, "source", nil, "provenance source (repeatable)")
	command.Flags().StringArrayVar(&options.details, "detail", nil, "provenance detail (repeatable)")
	command.Flags().StringVar(
		&options.format,
		"format",
		"",
		"output format ("+crmformat.AcceptedList(crmformat.EntityFormats())+")",
	)

	return command
}

func newOrgListCmd(root *rootOptions) *cobra.Command {
	options := &orgListOptions{}
	command := &cobra.Command{
		Use:   "ls",
		Short: "List organizations",
		Args:  cobra.NoArgs,
		Example: `  crm org ls
  crm org ls --category vc --limit 20
  crm org ls --all --format json`,
		RunE: func(command *cobra.Command, _ []string) error {
			selected, terminal, err := resolveEntityFormat(command, options.format)
			if err != nil {
				return err
			}
			if options.limit < 0 {
				return model.NewExitError(model.ErrValidation, "limit must not be negative")
			}

			var category *string
			if command.Flags().Changed("category") {
				trimmed := strings.TrimSpace(options.category)
				if trimmed == "" {
					return model.NewExitError(model.ErrValidation, "category must not be empty")
				}
				category = &trimmed
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

			organizations, err := repo.NewOrgRepo(database).List(
				command.Context(),
				model.OrgFilters{
					Category: category,
					All:      options.all,
					Limit:    options.limit,
				},
			)
			if err != nil {
				return err
			}

			return writeOrganizations(command, organizations, selected, terminal)
		},
	}

	command.Flags().StringVar(&options.category, "category", "", "filter by exact category")
	command.Flags().BoolVar(&options.all, "all", false, "include archived organizations")
	command.Flags().IntVar(&options.limit, "limit", 0, "maximum organizations to return (0 means all)")
	command.Flags().StringVar(
		&options.format,
		"format",
		"",
		"output format ("+crmformat.AcceptedList(crmformat.EntityFormats())+")",
	)

	return command
}

func resolveEntityFormat(
	command *cobra.Command,
	requested string,
) (crmformat.Format, bool, error) {
	terminal := crmformat.IsTerminal(command.OutOrStdout())
	selected, err := crmformat.Resolve(requested, terminal, crmformat.EntityFormats())
	return selected, terminal, err
}

func writeOrganizations(
	command *cobra.Command,
	organizations []model.Org,
	selected crmformat.Format,
	terminal bool,
) error {
	rows := make([]crmformat.Row, 0, len(organizations))
	for _, organization := range organizations {
		rows = append(rows, organizationRow(organization))
	}

	err := crmformat.WriteRecords(
		command.OutOrStdout(),
		rows,
		crmformat.Options{
			Format:   selected,
			Terminal: terminal,
			Columns:  orgColumns,
		},
	)
	if err != nil {
		return err
	}
	recordPostWriteRows(command, rows)

	return nil
}

func organizationRow(organization model.Org) crmformat.Row {
	return crmformat.Row{
		JSON: organization,
		Ref:  organization.Reference(),
		Cells: map[string]string{
			"ref":               organization.Reference(),
			"name":              organization.Name,
			"category":          stringValue(organization.Category),
			"website":           stringValue(organization.Website),
			"linkedin":          orgLinkedInURL(organization.LinkedIn),
			"location":          stringValue(organization.Location),
			"focus":             stringValue(organization.Focus),
			"relationship_hint": stringValue(organization.RelationshipHint),
			"archived_at":       stringValue(organization.ArchivedAt),
		},
	}
}

func stringValue(value *string) string {
	if value == nil {
		return ""
	}

	return *value
}

func orgLinkedInURL(handle *string) string {
	if handle == nil || *handle == "" {
		return ""
	}

	return fmt.Sprintf("https://www.linkedin.com/company/%s", *handle)
}
