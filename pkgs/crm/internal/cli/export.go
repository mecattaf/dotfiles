package cli

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"strconv"

	"github.com/mecattaf/crm/internal/db"
	"github.com/mecattaf/crm/internal/db/repo"
	crmformat "github.com/mecattaf/crm/internal/format"
	"github.com/mecattaf/crm/internal/model"
	"github.com/spf13/cobra"
)

type exportOptions struct {
	format string
}

type allExport struct {
	Contacts     []model.Contact     `json:"contacts"`
	Deals        []model.Deal        `json:"deals"`
	Interactions []model.Interaction `json:"interactions"`
	Orgs         []model.Org         `json:"orgs"`
}

var exportOrgColumns = exportColumns(
	"ref",
	"id",
	"name",
	"name_norm",
	"category",
	"website",
	"linkedin",
	"location",
	"focus",
	"context",
	"relationship_hint",
	"provenance_sources",
	"provenance_details",
	"created_at",
	"updated_at",
	"archived_at",
)

var exportContactColumns = exportColumns(
	"ref",
	"id",
	"name",
	"name_norm",
	"org_id",
	"job_title",
	"email",
	"phone",
	"linkedin",
	"location",
	"context",
	"relationship_hint",
	"provenance_sources",
	"provenance_details",
	"created_at",
	"updated_at",
	"archived_at",
	"links",
)

var exportDealColumns = exportColumns(
	"ref",
	"id",
	"title",
	"title_norm",
	"org_id",
	"contact_id",
	"pipeline_id",
	"pipeline",
	"stage_id",
	"stage",
	"status",
	"outcome_reason",
	"closed_at",
	"stage_changed_at",
	"days_in_stage",
	"rot_days",
	"created_at",
	"updated_at",
	"archived_at",
)

var exportInteractionColumns = exportColumns(
	"ref",
	"id",
	"kind",
	"occurred_on",
	"summary",
	"body",
	"transcript_path",
	"org_id",
	"deal_id",
	"contact_ids",
	"created_at",
	"updated_at",
	"archived_at",
)

func newExportCmd(root *rootOptions) *cobra.Command {
	command := &cobra.Command{
		Use:   "export",
		Short: "Export CRM records or a Markdown tree",
		Args:  cobra.NoArgs,
		Example: `  crm export contacts --format json
  crm export tree`,
	}
	command.AddCommand(newFlatExportCmd(root, "orgs"))
	command.AddCommand(newFlatExportCmd(root, "contacts"))
	command.AddCommand(newFlatExportCmd(root, "deals"))
	command.AddCommand(newFlatExportCmd(root, "interactions"))
	command.AddCommand(newExportAllCmd(root))
	command.AddCommand(newExportTreeCmd(root))

	return command
}

func newFlatExportCmd(root *rootOptions, entity string) *cobra.Command {
	options := &exportOptions{}
	command := &cobra.Command{
		Use:   entity,
		Short: "Export complete " + entity + " records",
		Args: func(command *cobra.Command, arguments []string) error {
			if err := cobra.NoArgs(command, arguments); err != nil {
				return err
			}

			_, _, err := resolveExportFormat(command, options.format, crmformat.ExportFormats())
			return err
		},
		Example: fmt.Sprintf("  crm export %s --format json\n  crm export %s --format csv", entity, entity),
		RunE: func(command *cobra.Command, _ []string) error {
			selected, terminal, err := resolveExportFormat(
				command,
				options.format,
				crmformat.ExportFormats(),
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

			rows, columns, err := loadFlatExport(command.Context(), database, entity)
			if err != nil {
				return err
			}

			return crmformat.WriteRecords(
				command.OutOrStdout(),
				rows,
				crmformat.Options{Format: selected, Terminal: terminal, Columns: columns},
			)
		},
	}
	command.Flags().StringVar(
		&options.format,
		"format",
		"",
		"output format ("+crmformat.AcceptedList(crmformat.ExportFormats())+")",
	)

	return command
}

func newExportAllCmd(root *rootOptions) *cobra.Command {
	options := &exportOptions{}
	command := &cobra.Command{
		Use:   "all",
		Short: "Export all flat entity collections as one JSON object",
		Args: func(command *cobra.Command, arguments []string) error {
			if err := cobra.NoArgs(command, arguments); err != nil {
				return err
			}

			_, _, err := resolveExportFormat(command, options.format, crmformat.ExportAllFormats())
			return err
		},
		Example: `  crm export all --format json > backup.json`,
		RunE: func(command *cobra.Command, _ []string) error {
			_, terminal, err := resolveExportFormat(
				command,
				options.format,
				crmformat.ExportAllFormats(),
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

			exported, err := loadAllExport(command.Context(), database, true)
			if err != nil {
				return err
			}

			return crmformat.WriteJSONValue(command.OutOrStdout(), exported, terminal)
		},
	}
	command.Flags().StringVar(
		&options.format,
		"format",
		"",
		"output format ("+crmformat.AcceptedList(crmformat.ExportAllFormats())+")",
	)

	return command
}

func resolveExportFormat(
	command *cobra.Command,
	requested string,
	accepted []crmformat.Format,
) (crmformat.Format, bool, error) {
	terminal := crmformat.IsTerminal(command.OutOrStdout())
	selected, err := crmformat.Resolve(requested, terminal, accepted)

	return selected, terminal, err
}

func exportColumns(fields ...string) []crmformat.ColumnDef {
	columns := make([]crmformat.ColumnDef, len(fields))
	for index, field := range fields {
		columns[index] = crmformat.ColumnDef{Header: field, Field: field}
	}

	return columns
}

func loadFlatExport(
	ctx context.Context,
	database *sql.DB,
	entity string,
) ([]crmformat.Row, []crmformat.ColumnDef, error) {
	switch entity {
	case "orgs":
		organizations, err := repo.NewOrgRepo(database).List(
			ctx,
			model.OrgFilters{All: true},
		)
		if err != nil {
			return nil, nil, err
		}

		return exportOrgRows(organizations), exportOrgColumns, nil
	case "contacts":
		contacts, err := repo.NewContactRepo(database).List(
			ctx,
			model.ContactFilters{All: true},
		)
		if err != nil {
			return nil, nil, err
		}
		rows, err := exportContactRows(contacts)
		if err != nil {
			return nil, nil, err
		}

		return rows, exportContactColumns, nil
	case "deals":
		deals, err := repo.NewDealRepo(database).List(ctx, model.DealFilters{All: true})
		if err != nil {
			return nil, nil, err
		}

		return exportDealRows(deals), exportDealColumns, nil
	case "interactions":
		interactions, err := repo.NewInteractionRepo(database).List(
			ctx,
			model.InteractionFilters{All: true},
		)
		if err != nil {
			return nil, nil, err
		}
		rows, err := exportInteractionRows(interactions)
		if err != nil {
			return nil, nil, err
		}

		return rows, exportInteractionColumns, nil
	default:
		return nil, nil, fmt.Errorf("load flat export: unsupported entity %q", entity)
	}
}

func loadAllExport(ctx context.Context, database *sql.DB, includeArchived bool) (allExport, error) {
	organizations, err := repo.NewOrgRepo(database).List(
		ctx,
		model.OrgFilters{All: includeArchived},
	)
	if err != nil {
		return allExport{}, err
	}
	contacts, err := repo.NewContactRepo(database).List(
		ctx,
		model.ContactFilters{All: includeArchived},
	)
	if err != nil {
		return allExport{}, err
	}
	deals, err := repo.NewDealRepo(database).List(
		ctx,
		model.DealFilters{All: includeArchived},
	)
	if err != nil {
		return allExport{}, err
	}
	interactions, err := repo.NewInteractionRepo(database).List(
		ctx,
		model.InteractionFilters{All: includeArchived},
	)
	if err != nil {
		return allExport{}, err
	}

	return allExport{
		Contacts:     contacts,
		Deals:        deals,
		Interactions: interactions,
		Orgs:         organizations,
	}, nil
}

func exportOrgRows(organizations []model.Org) []crmformat.Row {
	rows := make([]crmformat.Row, 0, len(organizations))
	for _, organization := range organizations {
		rows = append(rows, crmformat.Row{
			JSON: organization,
			Ref:  organization.Reference(),
			Cells: map[string]string{
				"ref":                organization.Reference(),
				"id":                 strconv.FormatInt(organization.ID, 10),
				"name":               organization.Name,
				"name_norm":          organization.NameNorm,
				"category":           stringValue(organization.Category),
				"website":            stringValue(organization.Website),
				"linkedin":           stringValue(organization.LinkedIn),
				"location":           stringValue(organization.Location),
				"focus":              stringValue(organization.Focus),
				"context":            stringValue(organization.Context),
				"relationship_hint":  stringValue(organization.RelationshipHint),
				"provenance_sources": stringValue(organization.ProvenanceSources),
				"provenance_details": stringValue(organization.ProvenanceDetails),
				"created_at":         organization.CreatedAt,
				"updated_at":         organization.UpdatedAt,
				"archived_at":        stringValue(organization.ArchivedAt),
			},
		})
	}

	return rows
}

func exportContactRows(contacts []model.Contact) ([]crmformat.Row, error) {
	rows := make([]crmformat.Row, 0, len(contacts))
	for _, contact := range contacts {
		links, err := marshalCSVCell(contact.Links)
		if err != nil {
			return nil, fmt.Errorf("encode contact %s links for CSV: %w", contact.Reference(), err)
		}
		rows = append(rows, crmformat.Row{
			JSON: contact,
			Ref:  contact.Reference(),
			Cells: map[string]string{
				"ref":                contact.Reference(),
				"id":                 strconv.FormatInt(contact.ID, 10),
				"name":               contact.Name,
				"name_norm":          contact.NameNorm,
				"org_id":             rawOptionalID(contact.OrgID),
				"job_title":          stringValue(contact.JobTitle),
				"email":              stringValue(contact.Email),
				"phone":              stringValue(contact.Phone),
				"linkedin":           stringValue(contact.LinkedIn),
				"location":           stringValue(contact.Location),
				"context":            stringValue(contact.Context),
				"relationship_hint":  stringValue(contact.RelationshipHint),
				"provenance_sources": stringValue(contact.ProvenanceSources),
				"provenance_details": stringValue(contact.ProvenanceDetails),
				"created_at":         contact.CreatedAt,
				"updated_at":         contact.UpdatedAt,
				"archived_at":        stringValue(contact.ArchivedAt),
				"links":              links,
			},
		})
	}

	return rows, nil
}

func exportDealRows(deals []model.Deal) []crmformat.Row {
	rows := make([]crmformat.Row, 0, len(deals))
	for _, deal := range deals {
		rows = append(rows, crmformat.Row{
			JSON: deal,
			Ref:  deal.Reference(),
			Cells: map[string]string{
				"ref":              deal.Reference(),
				"id":               strconv.FormatInt(deal.ID, 10),
				"title":            deal.Title,
				"title_norm":       deal.TitleNorm,
				"org_id":           rawOptionalID(deal.OrgID),
				"contact_id":       rawOptionalID(deal.ContactID),
				"pipeline_id":      strconv.FormatInt(deal.PipelineID, 10),
				"pipeline":         deal.Pipeline,
				"stage_id":         strconv.FormatInt(deal.StageID, 10),
				"stage":            deal.Stage,
				"status":           deal.Status,
				"outcome_reason":   stringValue(deal.OutcomeReason),
				"closed_at":        stringValue(deal.ClosedAt),
				"stage_changed_at": deal.StageChangedAt,
				"days_in_stage":    strconv.Itoa(deal.DaysInStage),
				"rot_days":         rawOptionalInt(deal.RotDays),
				"created_at":       deal.CreatedAt,
				"updated_at":       deal.UpdatedAt,
				"archived_at":      stringValue(deal.ArchivedAt),
			},
		})
	}

	return rows
}

func exportInteractionRows(interactions []model.Interaction) ([]crmformat.Row, error) {
	rows := make([]crmformat.Row, 0, len(interactions))
	for _, interaction := range interactions {
		contactIDs, err := marshalCSVCell(interaction.ContactIDs)
		if err != nil {
			return nil, fmt.Errorf(
				"encode interaction %s participants for CSV: %w",
				interaction.Reference(),
				err,
			)
		}
		rows = append(rows, crmformat.Row{
			JSON: interaction,
			Ref:  interaction.Reference(),
			Cells: map[string]string{
				"ref":             interaction.Reference(),
				"id":              strconv.FormatInt(interaction.ID, 10),
				"kind":            interaction.Kind,
				"occurred_on":     interaction.OccurredOn,
				"summary":         interaction.Summary,
				"body":            stringValue(interaction.Body),
				"transcript_path": stringValue(interaction.TranscriptPath),
				"org_id":          rawOptionalID(interaction.OrgID),
				"deal_id":         rawOptionalID(interaction.DealID),
				"contact_ids":     contactIDs,
				"created_at":      interaction.CreatedAt,
				"updated_at":      interaction.UpdatedAt,
				"archived_at":     stringValue(interaction.ArchivedAt),
			},
		})
	}

	return rows, nil
}

func rawOptionalID(value *int64) string {
	if value == nil {
		return ""
	}

	return strconv.FormatInt(*value, 10)
}

func rawOptionalInt(value *int) string {
	if value == nil {
		return ""
	}

	return strconv.Itoa(*value)
}

func marshalCSVCell(value any) (string, error) {
	encoded, err := json.Marshal(value)
	if err != nil {
		return "", err
	}

	return string(encoded), nil
}
