package cli

import (
	"context"
	"database/sql"
	"fmt"
	"path/filepath"
	"strings"

	"github.com/mecattaf/crm/internal/db"
	"github.com/mecattaf/crm/internal/db/repo"
	"github.com/mecattaf/crm/internal/exporttree"
	crmformat "github.com/mecattaf/crm/internal/format"
	"github.com/mecattaf/crm/internal/model"
	"github.com/spf13/cobra"
)

func newExportTreeCmd(root *rootOptions) *cobra.Command {
	return &cobra.Command{
		Use:   "tree [dir]",
		Short: "Regenerate the live CRM Markdown tree",
		Args: func(command *cobra.Command, arguments []string) error {
			if err := cobra.MaximumNArgs(1)(command, arguments); err != nil {
				return err
			}
			if len(arguments) == 1 && strings.TrimSpace(arguments[0]) == "" {
				return model.NewExitError(
					model.ErrValidation,
					"export tree destination must not be empty",
				)
			}

			return nil
		},
		Example: `  crm export tree
  crm export tree ~/mecattaf/notes/crm/tree`,
		RunE: func(command *cobra.Command, arguments []string) error {
			paths, err := root.resolvePaths()
			if err != nil {
				return err
			}
			destination := filepath.Join(paths.base, "tree")
			if len(arguments) == 1 {
				destination = arguments[0]
			}

			database, err := db.Open(paths.database)
			if err != nil {
				return err
			}
			defer func() {
				_ = database.Close()
			}()

			snapshot, err := loadTreeSnapshot(command.Context(), database)
			if err != nil {
				return err
			}
			resolvedDestination, err := exporttree.Write(destination, paths.base, snapshot)
			if err != nil {
				return err
			}

			return crmformat.WritePath(command.OutOrStdout(), resolvedDestination)
		},
	}
}

func loadTreeSnapshot(ctx context.Context, database *sql.DB) (exporttree.Snapshot, error) {
	exported, err := loadAllExport(ctx, database, false)
	if err != nil {
		return exporttree.Snapshot{}, err
	}

	snapshot := exporttree.Snapshot{
		Orgs:         make([]exporttree.OrgDocument, 0, len(exported.Orgs)),
		Contacts:     make([]exporttree.ContactDocument, 0, len(exported.Contacts)),
		Deals:        make([]exporttree.DealDocument, 0, len(exported.Deals)),
		Interactions: exported.Interactions,
	}
	contextRepository := repo.NewContextRepo(database)
	for _, organization := range exported.Orgs {
		briefing, assembleErr := contextRepository.Assemble(
			ctx,
			model.ContextTarget{Entity: model.ContextOrg, ID: organization.ID},
			0,
		)
		if assembleErr != nil {
			return exporttree.Snapshot{}, fmt.Errorf(
				"assemble export tree organization %s: %w",
				organization.Reference(),
				assembleErr,
			)
		}
		snapshot.Orgs = append(snapshot.Orgs, exporttree.OrgDocument{
			Org: organization, Timeline: briefing.Timeline,
		})
	}
	for _, contact := range exported.Contacts {
		briefing, assembleErr := contextRepository.Assemble(
			ctx,
			model.ContextTarget{Entity: model.ContextContact, ID: contact.ID},
			0,
		)
		if assembleErr != nil {
			return exporttree.Snapshot{}, fmt.Errorf(
				"assemble export tree contact %s: %w",
				contact.Reference(),
				assembleErr,
			)
		}
		snapshot.Contacts = append(snapshot.Contacts, exporttree.ContactDocument{
			Contact:  contact,
			Org:      briefing.Org,
			Timeline: briefing.Timeline,
		})
	}
	dealRepository := repo.NewDealRepo(database)
	for _, deal := range exported.Deals {
		detail, detailErr := dealRepository.DetailByID(ctx, deal.ID)
		if detailErr != nil {
			return exporttree.Snapshot{}, fmt.Errorf(
				"assemble export tree deal %s: %w",
				deal.Reference(),
				detailErr,
			)
		}
		snapshot.Deals = append(snapshot.Deals, exporttree.DealDocument{Detail: *detail})
	}

	return snapshot, nil
}
