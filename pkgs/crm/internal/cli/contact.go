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

var contactColumns = []crmformat.ColumnDef{
	{Header: "REF", Field: "ref"},
	{Header: "NAME", Field: "name"},
	{Header: "ORG", Field: "org_id"},
	{Header: "TITLE", Field: "job_title"},
	{Header: "EMAIL", Field: "email"},
	{Header: "PHONE", Field: "phone"},
	{Header: "LINKEDIN", Field: "linkedin"},
	{Header: "LOCATION", Field: "location"},
	{Header: "HINT", Field: "relationship_hint"},
	{Header: "LINKS", Field: "links"},
	{Header: "ARCHIVED", Field: "archived_at"},
}

type contactAddOptions struct {
	org      string
	title    string
	email    string
	phone    string
	linkedIn string
	location string
	context  string
	hint     string
	sources  []string
	details  []string
	format   string
}

type contactShowOptions struct {
	format string
}

type contactListOptions struct {
	org    string
	all    bool
	limit  int
	format string
}

type contactEditOptions struct {
	org           string
	title         string
	email         string
	phone         string
	linkedIn      string
	location      string
	context       string
	contextAppend string
	hint          string
	sources       []string
	details       []string
	format        string
}

func newContactCmd(options *rootOptions) *cobra.Command {
	command := &cobra.Command{
		Use:   "contact",
		Short: "Manage contacts",
		Args:  cobra.NoArgs,
		Example: `  crm contact add "Nick Dupont" --org kima --email nick@kima.vc
  crm contact show nick`,
	}
	command.AddCommand(newContactAddCmd(options))
	command.AddCommand(newContactListCmd(options))
	command.AddCommand(newContactShowCmd(options))
	command.AddCommand(newContactEditCmd(options))
	command.AddCommand(newContactMergeCmd(options))
	command.AddCommand(newContactRelateCmd(options))
	command.AddCommand(newContactUnrelateCmd(options))
	addLifecycleCommands(command, options, resolve.EntityContact)

	return command
}

func newContactAddCmd(root *rootOptions) *cobra.Command {
	options := &contactAddOptions{}
	command := &cobra.Command{
		Use:   "add <name>",
		Short: "Add a contact",
		Args:  cobra.ExactArgs(1),
		Example: `  crm contact add "Nick Dupont" --org kima --title Partner \
    --email nick@kima.vc --linkedin nickdupont`,
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

			var orgID *int64
			if command.Flags().Changed("org") && strings.TrimSpace(options.org) != "" {
				match, resolveErr := resolve.LinkRef(
					command.Context(),
					database,
					resolve.EntityOrg,
					options.org,
				)
				if resolveErr != nil {
					return resolveErr
				}
				resolvedID := match.ID
				orgID = &resolvedID
			}

			contact, err := repo.NewContactRepo(database).Create(
				command.Context(),
				model.CreateContactInput{
					Name:              arguments[0],
					OrgID:             orgID,
					JobTitle:          options.title,
					Email:             options.email,
					Phone:             options.phone,
					LinkedIn:          options.linkedIn,
					Location:          options.location,
					Context:           options.context,
					RelationshipHint:  options.hint,
					ProvenanceSources: options.sources,
					ProvenanceDetails: options.details,
				},
			)
			if err != nil {
				return err
			}

			return writeContacts(command, []model.Contact{*contact}, selected, terminal)
		},
	}
	markPostWrite(command, string(resolve.EntityContact))

	addContactFlags(command, options)
	command.Flags().StringVar(
		&options.format,
		"format",
		"",
		"output format ("+crmformat.AcceptedList(crmformat.EntityFormats())+")",
	)

	return command
}

func addContactFlags(command *cobra.Command, options *contactAddOptions) {
	command.Flags().StringVar(&options.org, "org", "", "organization ref")
	command.Flags().StringVar(&options.title, "title", "", "job title")
	command.Flags().StringVar(&options.email, "email", "", "email address")
	command.Flags().StringVar(&options.phone, "phone", "", "phone number")
	command.Flags().StringVar(&options.linkedIn, "linkedin", "", "LinkedIn handle or URL")
	command.Flags().StringVar(&options.location, "location", "", "contact location")
	command.Flags().StringVar(&options.context, "context", "", "rolling contact dossier")
	command.Flags().StringVar(&options.hint, "hint", "", "relationship hint")
	command.Flags().StringArrayVar(&options.sources, "source", nil, "provenance source (repeatable)")
	command.Flags().StringArrayVar(&options.details, "detail", nil, "provenance detail (repeatable)")
}

func newContactShowCmd(root *rootOptions) *cobra.Command {
	options := &contactShowOptions{}
	command := &cobra.Command{
		Use:   "show <ref>",
		Short: "Show a contact",
		Args:  cobra.ExactArgs(1),
		Example: `  crm contact show nick
  crm contact show nick@kima.vc --format json`,
		RunE: func(command *cobra.Command, arguments []string) error {
			return showContact(command, root, arguments[0], options.format)
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

func showContact(
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

	match, err := resolve.Ref(command.Context(), database, resolve.EntityContact, ref)
	if err != nil {
		return err
	}
	contact, err := repo.NewContactRepo(database).FindByID(command.Context(), match.ID)
	if err != nil {
		return err
	}

	return writeContacts(command, []model.Contact{*contact}, selected, terminal)
}

func newContactListCmd(root *rootOptions) *cobra.Command {
	options := &contactListOptions{}
	command := &cobra.Command{
		Use:   "ls",
		Short: "List contacts",
		Args:  cobra.NoArgs,
		Example: `  crm contact ls
  crm contact ls --org kima --format ids
  crm contact ls --all --limit 20`,
		RunE: func(command *cobra.Command, _ []string) error {
			selected, terminal, err := resolveEntityFormat(command, options.format)
			if err != nil {
				return err
			}
			if options.limit < 0 {
				return model.NewExitError(model.ErrValidation, "limit must not be negative")
			}
			if command.Flags().Changed("org") && strings.TrimSpace(options.org) == "" {
				return model.NewExitError(model.ErrValidation, "org filter must not be empty")
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

			var orgID *int64
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
				resolvedID := match.ID
				orgID = &resolvedID
			}

			contacts, err := repo.NewContactRepo(database).List(
				command.Context(),
				model.ContactFilters{OrgID: orgID, All: options.all, Limit: options.limit},
			)
			if err != nil {
				return err
			}

			return writeContacts(command, contacts, selected, terminal)
		},
	}

	command.Flags().StringVar(&options.org, "org", "", "filter by organization ref")
	command.Flags().BoolVar(&options.all, "all", false, "include archived contacts")
	command.Flags().IntVar(&options.limit, "limit", 0, "maximum contacts to return (0 means all)")
	command.Flags().StringVar(
		&options.format,
		"format",
		"",
		"output format ("+crmformat.AcceptedList(crmformat.EntityFormats())+")",
	)

	return command
}

func newContactEditCmd(root *rootOptions) *cobra.Command {
	options := &contactEditOptions{}
	command := &cobra.Command{
		Use:   "edit <ref>",
		Short: "Edit a contact",
		Args:  cobra.ExactArgs(1),
		Example: `  crm contact edit nick --phone +33612345678
  crm contact edit c12 --context-append "prefers WhatsApp"`,
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

			contactMatch, err := resolve.Ref(
				command.Context(),
				database,
				resolve.EntityContact,
				arguments[0],
			)
			if err != nil {
				return err
			}

			input := model.UpdateContactInput{}
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
					resolvedID := match.ID
					orgID = &resolvedID
				}
				input.OrgID = &orgID
			}
			if command.Flags().Changed("title") {
				input.JobTitle = &options.title
			}
			if command.Flags().Changed("email") {
				input.Email = &options.email
			}
			if command.Flags().Changed("phone") {
				input.Phone = &options.phone
			}
			if command.Flags().Changed("linkedin") {
				input.LinkedIn = &options.linkedIn
			}
			if command.Flags().Changed("location") {
				input.Location = &options.location
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

			contact, err := repo.NewContactRepo(database).Update(
				command.Context(),
				contactMatch.ID,
				input,
			)
			if err != nil {
				return err
			}

			return writeContacts(command, []model.Contact{*contact}, selected, terminal)
		},
	}
	markPostWrite(command, string(resolve.EntityContact))

	command.Flags().StringVar(&options.org, "org", "", "organization ref (empty clears)")
	command.Flags().StringVar(&options.title, "title", "", "job title")
	command.Flags().StringVar(&options.email, "email", "", "email address")
	command.Flags().StringVar(&options.phone, "phone", "", "phone number")
	command.Flags().StringVar(&options.linkedIn, "linkedin", "", "LinkedIn handle or URL")
	command.Flags().StringVar(&options.location, "location", "", "contact location")
	command.Flags().StringVar(&options.context, "context", "", "replace the rolling contact dossier")
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

func writeContacts(
	command *cobra.Command,
	contacts []model.Contact,
	selected crmformat.Format,
	terminal bool,
) error {
	rows := make([]crmformat.Row, 0, len(contacts))
	for _, contact := range contacts {
		rows = append(rows, contactRow(contact))
	}

	err := crmformat.WriteRecords(
		command.OutOrStdout(),
		rows,
		crmformat.Options{
			Format:   selected,
			Terminal: terminal,
			Columns:  contactColumns,
		},
	)
	if err != nil {
		return err
	}
	recordPostWriteRows(command, rows)

	return nil
}

func contactRow(contact model.Contact) crmformat.Row {
	return crmformat.Row{
		JSON: contact,
		Ref:  contact.Reference(),
		Cells: map[string]string{
			"ref":               contact.Reference(),
			"name":              contact.Name,
			"org_id":            contactOrgRef(contact.OrgID),
			"job_title":         stringValue(contact.JobTitle),
			"email":             stringValue(contact.Email),
			"phone":             stringValue(contact.Phone),
			"linkedin":          contactLinkedInURL(contact.LinkedIn),
			"location":          stringValue(contact.Location),
			"relationship_hint": stringValue(contact.RelationshipHint),
			"links":             contactLinksCell(contact.Links),
			"archived_at":       stringValue(contact.ArchivedAt),
		},
	}
}

func contactLinksCell(links []model.ContextLink) string {
	values := make([]string, 0, len(links))
	for _, link := range links {
		value := fmt.Sprintf(
			"%s %s %s %s",
			link.Contact.Reference(),
			link.Contact.Name,
			link.Direction,
			link.Type,
		)
		if link.Note != nil {
			value += " — " + *link.Note
		}
		values = append(values, value)
	}

	return strings.Join(values, " | ")
}

func contactOrgRef(orgID *int64) string {
	if orgID == nil {
		return ""
	}

	return fmt.Sprintf("o%d", *orgID)
}

func contactLinkedInURL(handle *string) string {
	if handle == nil || *handle == "" {
		return ""
	}

	return fmt.Sprintf("https://www.linkedin.com/in/%s", *handle)
}
