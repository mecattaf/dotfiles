package cli

import (
	"context"
	"database/sql"
	"fmt"
	"sort"
	"strings"
	"time"

	"github.com/mecattaf/crm/internal/db"
	"github.com/mecattaf/crm/internal/db/repo"
	crmformat "github.com/mecattaf/crm/internal/format"
	"github.com/mecattaf/crm/internal/model"
	"github.com/mecattaf/crm/internal/resolve"
	"github.com/spf13/cobra"
)

type logOptions struct {
	with       []string
	kind       string
	summary    string
	date       string
	bodyFile   string
	transcript string
	org        string
	deal       string
	format     string
}

func newLogCmd(root *rootOptions) *cobra.Command {
	options := &logOptions{}
	command := &cobra.Command{
		Use:   "log [kind contact summary]",
		Short: "Log an interaction",
		Args: func(_ *cobra.Command, arguments []string) error {
			if len(arguments) == 0 || len(arguments) == 3 {
				return nil
			}

			return model.NewExitError(
				model.ErrValidation,
				"log accepts either canonical flags or positional sugar: log <kind> <contact> <summary>",
			)
		},
		Example: `  crm log --with nick --kind call --summary "quick sync"
  crm log call nick "quick sync"`,
		RunE: func(command *cobra.Command, arguments []string) error {
			if err := applyLogSugar(command, options, arguments); err != nil {
				return err
			}
			selected, terminal, err := resolveEntityFormat(command, options.format)
			if err != nil {
				return err
			}
			kind, err := normalizeInteractionKind(options.kind, true)
			if err != nil {
				return err
			}
			summary := strings.TrimSpace(options.summary)
			if summary == "" {
				return model.NewExitError(model.ErrValidation, "--summary is required")
			}
			occurredOn := options.date
			if strings.TrimSpace(occurredOn) == "" {
				occurredOn = time.Now().Format("2006-01-02")
			}
			occurredOn, err = model.NormalizeDate(occurredOn)
			if err != nil {
				return err
			}

			if command.Flags().Changed("org") && strings.TrimSpace(options.org) == "" {
				return model.NewExitError(model.ErrValidation, "--org must not be empty")
			}
			if command.Flags().Changed("deal") && strings.TrimSpace(options.deal) == "" {
				return model.NewExitError(model.ErrValidation, "--deal must not be empty")
			}
			if len(options.with) == 0 && !command.Flags().Changed("org") &&
				!command.Flags().Changed("deal") {
				return model.NewExitError(
					model.ErrValidation,
					"log requires at least one of --with, --org, or --deal",
				)
			}

			paths, err := root.resolvePaths()
			if err != nil {
				return err
			}
			var transcriptPath *string
			if command.Flags().Changed("transcript") {
				stored, pathErr := resolveTranscriptPath(paths.base, options.transcript)
				if pathErr != nil {
					return pathErr
				}
				if stored != "" {
					transcriptPath = &stored
				}
			}
			var body *string
			if command.Flags().Changed("body-file") {
				body, err = readBodyFile(command.InOrStdin(), options.bodyFile)
				if err != nil {
					return err
				}
			}

			database, err := db.Open(paths.database)
			if err != nil {
				return err
			}
			defer func() {
				_ = database.Close()
			}()

			contactIDs, err := resolveContactLinkIDs(
				command.Context(),
				database,
				options.with,
				"--with",
			)
			if err != nil {
				return err
			}
			var orgID *int64
			if command.Flags().Changed("org") {
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
			var dealID *int64
			if command.Flags().Changed("deal") {
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

			interaction, err := repo.NewInteractionRepo(database).Create(
				command.Context(),
				model.CreateInteractionInput{
					Kind:           kind,
					OccurredOn:     occurredOn,
					Summary:        summary,
					Body:           body,
					TranscriptPath: transcriptPath,
					OrgID:          orgID,
					DealID:         dealID,
					ContactIDs:     contactIDs,
				},
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

	command.Flags().StringArrayVar(&options.with, "with", nil, "contact ref (repeatable)")
	command.Flags().StringVar(
		&options.kind,
		"kind",
		"",
		"interaction kind ("+strings.Join(model.InteractionKinds, ",")+")",
	)
	command.Flags().StringVar(&options.summary, "summary", "", "interaction summary")
	command.Flags().StringVar(&options.date, "date", "", "interaction date (YYYY-MM-DD; default today)")
	command.Flags().StringVar(&options.bodyFile, "body-file", "", "read interaction body from path or - for stdin")
	command.Flags().StringVar(&options.transcript, "transcript", "", "transcript path relative to the database directory")
	command.Flags().StringVar(&options.org, "org", "", "organization ref")
	command.Flags().StringVar(&options.deal, "deal", "", "deal ref")
	command.Flags().StringVar(
		&options.format,
		"format",
		"",
		"output format ("+crmformat.AcceptedList(crmformat.EntityFormats())+")",
	)
	mustRegisterInteractionKindCompletion(command)

	return command
}

func applyLogSugar(command *cobra.Command, options *logOptions, arguments []string) error {
	if len(arguments) == 0 {
		return nil
	}
	for _, flagName := range []string{"kind", "with", "summary"} {
		if command.Flags().Changed(flagName) {
			return model.NewExitError(
				model.ErrValidation,
				"positional log sugar cannot be combined with --%s",
				flagName,
			)
		}
	}
	options.kind = arguments[0]
	options.with = append(options.with, arguments[1])
	options.summary = arguments[2]

	return nil
}

func normalizeInteractionKind(raw string, required bool) (string, error) {
	kind := strings.TrimSpace(raw)
	if kind == "" && required {
		return "", model.NewExitError(
			model.ErrValidation,
			"--kind is required (accepted: %s)",
			strings.Join(model.InteractionKinds, ","),
		)
	}
	if kind != "" && !model.ValidInteractionKind(kind) {
		return "", model.NewExitError(
			model.ErrValidation,
			"invalid interaction kind %q (accepted: %s)",
			kind,
			strings.Join(model.InteractionKinds, ","),
		)
	}

	return kind, nil
}

func resolveContactLinkIDs(
	ctx context.Context,
	database *sql.DB,
	references []string,
	flagName string,
) ([]int64, error) {
	byID := make(map[int64]struct{}, len(references))
	for _, reference := range references {
		if strings.TrimSpace(reference) == "" {
			return nil, model.NewExitError(
				model.ErrValidation,
				"%s must not be empty",
				flagName,
			)
		}
		match, err := resolve.LinkRef(ctx, database, resolve.EntityContact, reference)
		if err != nil {
			return nil, err
		}
		byID[match.ID] = struct{}{}
	}
	result := make([]int64, 0, len(byID))
	for id := range byID {
		result = append(result, id)
	}
	sort.Slice(result, func(left, right int) bool {
		return result[left] < result[right]
	})

	return result, nil
}

func mustRegisterInteractionKindCompletion(command *cobra.Command) {
	err := command.RegisterFlagCompletionFunc(
		"kind",
		func(
			_ *cobra.Command,
			_ []string,
			toComplete string,
		) ([]string, cobra.ShellCompDirective) {
			matches := make([]string, 0, len(model.InteractionKinds))
			for _, kind := range model.InteractionKinds {
				if strings.HasPrefix(kind, toComplete) {
					matches = append(matches, kind)
				}
			}

			return matches, cobra.ShellCompDirectiveNoFileComp
		},
	)
	if err != nil {
		panic(fmt.Sprintf("register interaction kind completion: %v", err))
	}
}
