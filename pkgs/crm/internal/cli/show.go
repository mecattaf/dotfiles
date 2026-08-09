package cli

import (
	crmformat "github.com/mecattaf/crm/internal/format"
	"github.com/mecattaf/crm/internal/model"
	"github.com/mecattaf/crm/internal/resolve"
	"github.com/spf13/cobra"
)

type showOptions struct {
	format string
}

func newShowCmd(root *rootOptions) *cobra.Command {
	options := &showOptions{}
	command := &cobra.Command{
		Use:   "show <prefixed-ref>",
		Short: "Show an entity selected by its prefixed ref",
		Args: func(command *cobra.Command, arguments []string) error {
			if err := cobra.ExactArgs(1)(command, arguments); err != nil {
				return err
			}
			if _, ok := resolve.PrefixedEntity(arguments[0]); !ok {
				return model.NewExitError(
					model.ErrValidation,
					"show requires a prefixed ref (for example c12 or o4)",
				)
			}

			return nil
		},
		Example: `  crm show c12
  crm show o4 --format json`,
		RunE: func(command *cobra.Command, arguments []string) error {
			entity, _ := resolve.PrefixedEntity(arguments[0])
			switch entity {
			case resolve.EntityContact:
				return showContact(command, root, arguments[0], options.format)
			case resolve.EntityOrg:
				return showOrganization(command, root, arguments[0], options.format)
			case resolve.EntityInteraction:
				return showInteraction(command, root, arguments[0], options.format)
			case resolve.EntityPipeline:
				return showPipeline(command, root, arguments[0], options.format)
			case resolve.EntityDeal:
				return showDeal(command, root, arguments[0], options.format)
			default:
				return model.NewExitError(
					model.ErrValidation,
					"show does not support %s refs yet",
					entity,
				)
			}
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
