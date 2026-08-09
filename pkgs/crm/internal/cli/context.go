package cli

import (
	"context"
	"database/sql"
	"strings"

	"github.com/mecattaf/crm/internal/db"
	"github.com/mecattaf/crm/internal/db/repo"
	crmformat "github.com/mecattaf/crm/internal/format"
	"github.com/mecattaf/crm/internal/model"
	"github.com/mecattaf/crm/internal/resolve"
	"github.com/spf13/cobra"
)

type contextOptions struct {
	limit  int
	all    bool
	format string
}

func newContextCmd(root *rootOptions) *cobra.Command {
	options := &contextOptions{}
	command := &cobra.Command{
		Use:   "context <contact-or-org-ref>",
		Short: "Build a complete contact or organization briefing",
		Args: func(command *cobra.Command, arguments []string) error {
			if err := cobra.ExactArgs(1)(command, arguments); err != nil {
				return err
			}
			if strings.TrimSpace(arguments[0]) == "" {
				return model.NewExitError(model.ErrValidation, "context ref must not be empty")
			}
			if options.limit <= 0 {
				return model.NewExitError(model.ErrValidation, "limit must be positive")
			}

			return nil
		},
		Example: `  crm context nick
  crm context kima --limit 10
  crm context o1 --all --format json`,
		RunE: func(command *cobra.Command, arguments []string) error {
			terminal := crmformat.IsTerminal(command.OutOrStdout())
			selected, err := crmformat.Resolve(
				options.format,
				terminal,
				crmformat.ContextFormats(),
			)
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

			target, err := resolveContextTarget(command.Context(), database, arguments[0])
			if err != nil {
				return err
			}
			limit := options.limit
			if options.all {
				limit = 0
			}
			briefing, err := repo.NewContextRepo(database).Assemble(
				command.Context(),
				target,
				limit,
			)
			if err != nil {
				return err
			}

			return crmformat.WriteBriefing(
				command.OutOrStdout(),
				briefing,
				selected,
				terminal,
			)
		},
	}
	command.Flags().IntVar(&options.limit, "limit", 20, "maximum timeline entries to return")
	command.Flags().BoolVar(&options.all, "all", false, "return the complete timeline")
	command.Flags().StringVar(
		&options.format,
		"format",
		"",
		"output format ("+crmformat.AcceptedList(crmformat.ContextFormats())+")",
	)
	command.MarkFlagsMutuallyExclusive("limit", "all")

	return command
}

func resolveContextTarget(
	ctx context.Context,
	database *sql.DB,
	rawRef string,
) (model.ContextTarget, error) {
	match, err := resolve.ContactOrOrgRef(ctx, database, rawRef)
	if err != nil {
		return model.ContextTarget{}, err
	}

	entity := model.ContextContact
	if match.Entity == resolve.EntityOrg {
		entity = model.ContextOrg
	}

	return model.ContextTarget{Entity: entity, ID: match.ID}, nil
}
