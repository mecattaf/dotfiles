package cli

import (
	"strings"

	"github.com/mecattaf/crm/internal/db"
	"github.com/mecattaf/crm/internal/db/repo"
	crmformat "github.com/mecattaf/crm/internal/format"
	"github.com/mecattaf/crm/internal/model"
	"github.com/mecattaf/crm/internal/resolve"
	"github.com/spf13/cobra"
)

type contactRelateOptions struct {
	linkType string
	note     string
	format   string
}

type contactUnrelateOptions struct {
	linkType string
	format   string
}

func newContactRelateCmd(root *rootOptions) *cobra.Command {
	options := &contactRelateOptions{}
	command := &cobra.Command{
		Use:   "relate <contact> <related-contact>",
		Short: "Relate one contact to another",
		Args: func(command *cobra.Command, arguments []string) error {
			if err := cobra.ExactArgs(2)(command, arguments); err != nil {
				return err
			}
			if !command.Flags().Changed("type") {
				return model.NewExitError(model.ErrValidation, "--type is required")
			}
			if strings.TrimSpace(options.linkType) == "" {
				return model.NewExitError(model.ErrValidation, "--type must not be empty")
			}

			return nil
		},
		Example: `  crm contact relate nick jean --type "referred by" \
    --note "Jean made the intro"`,
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

			contact, err := resolve.LinkRef(
				command.Context(), database, resolve.EntityContact, arguments[0],
			)
			if err != nil {
				return err
			}
			relatedContact, err := resolve.LinkRef(
				command.Context(), database, resolve.EntityContact, arguments[1],
			)
			if err != nil {
				return err
			}
			if contact.ID == relatedContact.ID {
				return model.NewExitError(
					model.ErrValidation,
					"cannot relate a contact to itself",
				)
			}

			result, err := repo.NewContactLinkRepo(database).Relate(
				command.Context(),
				contact.ID,
				relatedContact.ID,
				options.linkType,
				options.note,
			)
			if err != nil {
				return err
			}

			return writeContacts(command, []model.Contact{*result}, selected, terminal)
		},
	}
	markPostWrite(command, string(resolve.EntityContact))
	command.Flags().StringVar(&options.linkType, "type", "", "free-text relationship type")
	command.Flags().StringVar(&options.note, "note", "", "optional relationship note")
	command.Flags().StringVar(
		&options.format,
		"format",
		"",
		"output format ("+crmformat.AcceptedList(crmformat.EntityFormats())+")",
	)

	return command
}

func newContactUnrelateCmd(root *rootOptions) *cobra.Command {
	options := &contactUnrelateOptions{}
	command := &cobra.Command{
		Use:   "unrelate <contact> <related-contact>",
		Short: "Remove links between two contacts",
		Args: func(command *cobra.Command, arguments []string) error {
			if err := cobra.ExactArgs(2)(command, arguments); err != nil {
				return err
			}
			if command.Flags().Changed("type") && strings.TrimSpace(options.linkType) == "" {
				return model.NewExitError(model.ErrValidation, "--type must not be empty")
			}

			return nil
		},
		Example: `  crm contact unrelate nick jean
  crm contact unrelate nick jean --type "referred by"`,
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

			contact, err := resolve.LinkRef(
				command.Context(), database, resolve.EntityContact, arguments[0],
			)
			if err != nil {
				return err
			}
			relatedContact, err := resolve.LinkRef(
				command.Context(), database, resolve.EntityContact, arguments[1],
			)
			if err != nil {
				return err
			}

			var linkType *string
			if command.Flags().Changed("type") {
				linkType = &options.linkType
			}
			result, err := repo.NewContactLinkRepo(database).Unrelate(
				command.Context(), contact.ID, relatedContact.ID, linkType,
			)
			if err != nil {
				return err
			}

			return writeContacts(command, []model.Contact{*result}, selected, terminal)
		},
	}
	markPostWrite(command, string(resolve.EntityContact))
	command.Flags().StringVar(&options.linkType, "type", "", "remove only this directed relationship type")
	command.Flags().StringVar(
		&options.format,
		"format",
		"",
		"output format ("+crmformat.AcceptedList(crmformat.EntityFormats())+")",
	)

	return command
}
