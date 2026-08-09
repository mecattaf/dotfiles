package cli

import (
	"github.com/mecattaf/crm/internal/db"
	"github.com/mecattaf/crm/internal/db/repo"
	crmformat "github.com/mecattaf/crm/internal/format"
	"github.com/mecattaf/crm/internal/model"
	"github.com/mecattaf/crm/internal/resolve"
	"github.com/spf13/cobra"
)

type mergeOptions struct {
	format string
}

func newContactMergeCmd(root *rootOptions) *cobra.Command {
	options := &mergeOptions{}
	command := &cobra.Command{
		Use:   "merge <winner> <loser>",
		Short: "Merge one contact into another",
		Args:  cobra.ExactArgs(2),
		Example: `  crm contact merge c12 c31
  crm contact merge nick nick-duplicate --format json`,
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

			winner, err := resolve.Ref(
				command.Context(),
				database,
				resolve.EntityContact,
				arguments[0],
			)
			if err != nil {
				return err
			}
			loser, err := resolve.Ref(
				command.Context(),
				database,
				resolve.EntityContact,
				arguments[1],
			)
			if err != nil {
				return err
			}

			contact, err := repo.NewContactRepo(database).Merge(
				command.Context(),
				winner.ID,
				loser.ID,
			)
			if err != nil {
				return err
			}

			return writeContacts(command, []model.Contact{*contact}, selected, terminal)
		},
	}
	markPostWrite(command, string(resolve.EntityContact))
	command.Flags().StringVar(
		&options.format,
		"format",
		"",
		"output format ("+crmformat.AcceptedList(crmformat.EntityFormats())+")",
	)

	return command
}

func newOrgMergeCmd(root *rootOptions) *cobra.Command {
	options := &mergeOptions{}
	command := &cobra.Command{
		Use:   "merge <winner> <loser>",
		Short: "Merge one organization into another",
		Args:  cobra.ExactArgs(2),
		Example: `  crm org merge o4 o17
  crm org merge "Kima Ventures" "Kima VC" --format json`,
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

			winner, err := resolve.Ref(
				command.Context(),
				database,
				resolve.EntityOrg,
				arguments[0],
			)
			if err != nil {
				return err
			}
			loser, err := resolve.Ref(
				command.Context(),
				database,
				resolve.EntityOrg,
				arguments[1],
			)
			if err != nil {
				return err
			}

			organization, err := repo.NewOrgRepo(database).Merge(
				command.Context(),
				winner.ID,
				loser.ID,
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
	command.Flags().StringVar(
		&options.format,
		"format",
		"",
		"output format ("+crmformat.AcceptedList(crmformat.EntityFormats())+")",
	)

	return command
}
