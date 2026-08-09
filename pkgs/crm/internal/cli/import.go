package cli

import (
	"database/sql"
	"encoding/csv"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"unicode"

	"github.com/mecattaf/crm/internal/db"
	"github.com/mecattaf/crm/internal/db/repo"
	crmformat "github.com/mecattaf/crm/internal/format"
	"github.com/mecattaf/crm/internal/model"
	"github.com/spf13/cobra"
)

type importOptions struct {
	source        string
	dryRun        bool
	skipErrors    bool
	update        bool
	rejectFile    string
	createMissing bool
}

type parsedImportFile struct {
	header []string
	rows   []parsedImportRow
}

type parsedImportRow struct {
	line   int
	values []string
	fields map[string]repo.ImportField
}

func newImportCmd(root *rootOptions) *cobra.Command {
	command := &cobra.Command{
		Use:   "import",
		Short: "Import organizations or contacts from CSV",
		Args:  cobra.NoArgs,
		Example: `  crm import orgs organizations.csv --source investor-crm
  crm import contacts contacts.csv --source investor-crm --dry-run`,
	}
	command.AddCommand(newImportEntityCmd(root, "orgs"))
	command.AddCommand(newImportEntityCmd(root, "contacts"))

	return command
}

func newImportEntityCmd(root *rootOptions, entity string) *cobra.Command {
	options := &importOptions{}
	command := &cobra.Command{
		Use:   entity + " <file.csv>",
		Short: "Import " + entity + " from a CSV file",
		Args: func(command *cobra.Command, arguments []string) error {
			if err := cobra.ExactArgs(1)(command, arguments); err != nil {
				return err
			}
			if !command.Flags().Changed("source") || strings.TrimSpace(options.source) == "" {
				return model.NewExitError(model.ErrValidation, "--source is required")
			}
			if command.Flags().Changed("reject-file") && strings.TrimSpace(options.rejectFile) == "" {
				return model.NewExitError(model.ErrValidation, "--reject-file must not be empty")
			}

			return nil
		},
		RunE: func(command *cobra.Command, arguments []string) error {
			return runImport(command, root, entity, arguments[0], *options)
		},
	}
	if entity == "orgs" {
		command.Example = `  crm import orgs organizations.csv --source investor-crm
  crm import orgs organizations.csv --source investor-crm --update`
		markPostWrite(command, "org")
	} else {
		command.Example = `  crm import contacts contacts.csv --source investor-crm --dry-run
  crm import contacts contacts.csv --source investor-crm --skip-errors --reject-file rejects.csv`
		markPostWrite(command, "contact")
		command.Flags().BoolVar(
			&options.createMissing,
			"create-missing",
			false,
			"auto-create unknown organizations as stamped stubs",
		)
	}

	command.Flags().StringVar(&options.source, "source", "", "required provenance source")
	command.Flags().BoolVar(&options.dryRun, "dry-run", false, "print the import plan and roll back")
	command.Flags().BoolVar(
		&options.skipErrors,
		"skip-errors",
		false,
		"roll back failed rows to savepoints and continue",
	)
	command.Flags().BoolVar(&options.update, "update", false, "patch matches and append provenance")
	command.Flags().StringVar(
		&options.rejectFile,
		"reject-file",
		"",
		"write failed rows with source line numbers",
	)

	return command
}

func runImport(
	command *cobra.Command,
	root *rootOptions,
	entity string,
	inputPath string,
	options importOptions,
) error {
	parsed, err := readImportCSV(inputPath)
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

	importOptions := repo.ImportOptions{
		Source:        strings.TrimSpace(options.source),
		Update:        options.update,
		DryRun:        options.dryRun,
		SkipErrors:    options.skipErrors,
		CreateMissing: options.createMissing,
	}
	importer := repo.NewImportRepo(database)
	var result repo.ImportResult
	switch entity {
	case "orgs":
		rows, parseErr := parseOrganizationImportRows(parsed)
		if parseErr != nil {
			return parseErr
		}
		result, err = importer.ImportOrganizations(command.Context(), rows, importOptions)
	case "contacts":
		rows, parseErr := parseContactImportRows(parsed)
		if parseErr != nil {
			return parseErr
		}
		result, err = importer.ImportContacts(command.Context(), rows, importOptions)
	default:
		return fmt.Errorf("run import: unsupported entity %q", entity)
	}
	if err != nil {
		return err
	}

	if options.rejectFile != "" && !options.dryRun {
		if err := writeImportRejectFile(options.rejectFile, parsed, result.Rejects); err != nil {
			return err
		}
	}
	if options.dryRun {
		if err := crmformat.WriteImportPlan(command.OutOrStdout(), result.Actions); err != nil {
			return err
		}
	} else {
		if err := writeImportedRefs(command.OutOrStdout(), result.Created); err != nil {
			return err
		}
		if err := recordImportMutation(command, database, entity, result.ChangedPrimaryIDs); err != nil {
			return err
		}
		for _, stub := range result.AutoCreated {
			if _, err := fmt.Fprintf(
				command.ErrOrStderr(),
				"Auto-created org %s %q\n",
				stub.Ref,
				stub.Name,
			); err != nil {
				return fmt.Errorf("write auto-created organization notice: %w", err)
			}
		}
	}
	if _, err := fmt.Fprintf(
		command.ErrOrStderr(),
		"Imported: %d, updated: %d, skipped: %d, errors: %d\n",
		result.Imported,
		result.Updated,
		result.Skipped,
		result.Errors,
	); err != nil {
		return fmt.Errorf("write import summary: %w", err)
	}

	return nil
}

func writeImportedRefs(output io.Writer, created []repo.ImportCreated) error {
	rows := make([]crmformat.Row, 0, len(created))
	for _, record := range created {
		rows = append(rows, crmformat.Row{Ref: record.Ref})
	}

	return crmformat.WriteRecords(
		output,
		rows,
		crmformat.Options{Format: crmformat.FormatIDs},
	)
}

func recordImportMutation(
	command *cobra.Command,
	database *sql.DB,
	entity string,
	ids []int64,
) error {
	if len(ids) == 0 {
		return nil
	}
	refs := make([]string, 0, len(ids))
	records := make([]any, 0, len(ids))
	for _, id := range ids {
		switch entity {
		case "orgs":
			organization, err := repo.NewOrgRepo(database).FindByID(command.Context(), id)
			if err != nil {
				return err
			}
			refs = append(refs, organization.Reference())
			records = append(records, *organization)
		case "contacts":
			contact, err := repo.NewContactRepo(database).FindByID(command.Context(), id)
			if err != nil {
				return err
			}
			refs = append(refs, contact.Reference())
			records = append(records, *contact)
		default:
			return fmt.Errorf("record import mutation: unsupported entity %q", entity)
		}
	}
	recordPostWrite(command, "import", strings.TrimSuffix(entity, "s"), refs, records)

	return nil
}

func readImportCSV(path string) (parsedImportFile, error) {
	file, err := os.Open(path)
	if errors.Is(err, os.ErrNotExist) {
		return parsedImportFile{}, model.NewExitError(
			model.ErrNotFound,
			"import file %q not found — check the path and retry",
			path,
		)
	}
	if err != nil {
		return parsedImportFile{}, fmt.Errorf("open import file %s: %w", path, err)
	}
	defer func() {
		_ = file.Close()
	}()
	info, err := file.Stat()
	if err != nil {
		return parsedImportFile{}, fmt.Errorf("inspect import file %s: %w", path, err)
	}
	if !info.Mode().IsRegular() {
		return parsedImportFile{}, model.NewExitError(
			model.ErrValidation,
			"import file %q is not a regular file",
			path,
		)
	}

	reader := csv.NewReader(file)
	header, err := reader.Read()
	if errors.Is(err, io.EOF) {
		return parsedImportFile{}, model.NewExitError(
			model.ErrValidation,
			"import file %q has no CSV header",
			path,
		)
	}
	if err != nil {
		return parsedImportFile{}, invalidCSVError(err)
	}
	if len(header) == 0 {
		return parsedImportFile{}, model.NewExitError(
			model.ErrValidation,
			"import file %q has no CSV header",
			path,
		)
	}
	header[0] = strings.TrimPrefix(header[0], "\ufeff")
	keys := make([]string, len(header))
	seen := make(map[string]struct{}, len(header))
	for index, value := range header {
		key := canonicalImportHeader(value)
		if key == "" {
			return parsedImportFile{}, model.NewExitError(
				model.ErrValidation,
				"CSV header column %d is empty",
				index+1,
			)
		}
		if _, found := seen[key]; found {
			return parsedImportFile{}, model.NewExitError(
				model.ErrValidation,
				"duplicate CSV header %q",
				value,
			)
		}
		seen[key] = struct{}{}
		keys[index] = key
	}

	parsed := parsedImportFile{header: header, rows: make([]parsedImportRow, 0)}
	for {
		values, readErr := reader.Read()
		if errors.Is(readErr, io.EOF) {
			break
		}
		if readErr != nil {
			return parsedImportFile{}, invalidCSVError(readErr)
		}
		line, _ := reader.FieldPos(0)
		fields := make(map[string]repo.ImportField, len(values))
		for index, value := range values {
			fields[keys[index]] = repo.ImportField{Value: value, Present: true}
		}
		parsed.rows = append(parsed.rows, parsedImportRow{
			line:   line,
			values: append([]string(nil), values...),
			fields: fields,
		})
	}

	return parsed, nil
}

func invalidCSVError(err error) error {
	var parseError *csv.ParseError
	if errors.As(err, &parseError) {
		return model.NewExitError(
			model.ErrValidation,
			"invalid CSV at line %d: %v",
			parseError.Line,
			parseError.Err,
		)
	}

	return model.NewExitError(model.ErrValidation, "invalid CSV: %v", err)
}

func canonicalImportHeader(value string) string {
	var normalized strings.Builder
	separator := false
	for _, current := range strings.TrimSpace(strings.ToLower(value)) {
		switch {
		case unicode.IsLetter(current) || unicode.IsDigit(current):
			normalized.WriteRune(current)
			separator = false
		case !separator && normalized.Len() > 0:
			normalized.WriteByte('_')
			separator = true
		}
	}

	return strings.Trim(normalized.String(), "_")
}

func parseOrganizationImportRows(parsed parsedImportFile) ([]repo.ImportOrgRow, error) {
	if !parsed.hasAnyHeader("name", "organization", "organization_name", "company", "company_name") {
		return nil, model.NewExitError(model.ErrValidation, "CSV header is missing organization name")
	}
	rows := make([]repo.ImportOrgRow, 0, len(parsed.rows))
	for _, row := range parsed.rows {
		rows = append(rows, repo.ImportOrgRow{
			Line:              row.line,
			ID:                row.field("id"),
			Name:              row.field("name", "organization", "organization_name", "company", "company_name").Value,
			Category:          row.field("category", "organization_type", "org_type", "type"),
			Website:           row.field("website", "website_url", "url", "web"),
			LinkedIn:          row.field("linkedin", "linkedin_url"),
			Location:          row.field("location", "city", "address"),
			Focus:             row.field("focus", "investment_focus", "thesis"),
			Context:           row.field("context", "notes", "description"),
			RelationshipHint:  row.field("relationship_hint", "hint", "relationship", "how_we_met"),
			ProvenanceSources: row.field("provenance_sources", "source", "sources"),
			ProvenanceDetails: row.field("provenance_details", "detail", "details"),
			CreatedAt:         row.field("created_at"),
			UpdatedAt:         row.field("updated_at"),
			ArchivedAt:        row.field("archived_at"),
		})
	}

	return rows, nil
}

func parseContactImportRows(parsed parsedImportFile) ([]repo.ImportContactRow, error) {
	if !parsed.hasAnyHeader("name", "full_name", "contact_name", "first_name", "last_name") {
		return nil, model.NewExitError(model.ErrValidation, "CSV header is missing contact name")
	}
	rows := make([]repo.ImportContactRow, 0, len(parsed.rows))
	for _, row := range parsed.rows {
		rows = append(rows, repo.ImportContactRow{
			Line:              row.line,
			ID:                row.field("id"),
			Name:              row.contactName(),
			OrgID:             row.field("org_id"),
			Org:               row.field("org", "organization", "organization_name", "org_name", "company", "company_name"),
			JobTitle:          row.field("job_title", "title", "role", "position"),
			Email:             row.field("email", "email_address"),
			Phone:             row.field("phone", "phone_number"),
			LinkedIn:          row.field("linkedin", "linkedin_url"),
			Location:          row.field("location", "city", "address"),
			Context:           row.field("context", "notes", "description"),
			RelationshipHint:  row.field("relationship_hint", "hint", "relationship", "how_we_met"),
			ProvenanceSources: row.field("provenance_sources", "source", "sources"),
			ProvenanceDetails: row.field("provenance_details", "detail", "details"),
			CreatedAt:         row.field("created_at"),
			UpdatedAt:         row.field("updated_at"),
			ArchivedAt:        row.field("archived_at"),
		})
	}

	return rows, nil
}

func (parsed parsedImportFile) hasAnyHeader(names ...string) bool {
	if len(parsed.rows) > 0 {
		for _, name := range names {
			if _, found := parsed.rows[0].fields[name]; found {
				return true
			}
		}

		return false
	}
	for _, header := range parsed.header {
		key := canonicalImportHeader(header)
		for _, name := range names {
			if key == name {
				return true
			}
		}
	}

	return false
}

func (row parsedImportRow) field(names ...string) repo.ImportField {
	for _, name := range names {
		if field, found := row.fields[name]; found {
			return field
		}
	}

	return repo.ImportField{}
}

func (row parsedImportRow) contactName() string {
	if fullName := row.field("name", "full_name", "contact_name"); fullName.Present {
		return fullName.Value
	}
	firstName := strings.TrimSpace(row.field("first_name").Value)
	lastName := strings.TrimSpace(row.field("last_name").Value)

	return strings.TrimSpace(firstName + " " + lastName)
}

func writeImportRejectFile(
	path string,
	parsed parsedImportFile,
	rejects []repo.ImportReject,
) error {
	directory := filepath.Dir(path)
	temporary, err := os.CreateTemp(directory, ".crm-import-reject-*")
	if err != nil {
		return fmt.Errorf("create reject file near %s: %w", path, err)
	}
	temporaryPath := temporary.Name()
	defer func() {
		_ = os.Remove(temporaryPath)
	}()
	if err := temporary.Chmod(0o600); err != nil {
		_ = temporary.Close()
		return fmt.Errorf("set reject file permissions: %w", err)
	}

	rowsByLine := make(map[int][]string, len(parsed.rows))
	for _, row := range parsed.rows {
		rowsByLine[row.line] = row.values
	}
	writer := csv.NewWriter(temporary)
	header := append([]string{"line", "error"}, parsed.header...)
	if err := writer.Write(header); err != nil {
		_ = temporary.Close()
		return fmt.Errorf("write reject file header: %w", err)
	}
	for _, reject := range rejects {
		record := []string{fmt.Sprintf("%d", reject.Line), reject.Message}
		record = append(record, rowsByLine[reject.Line]...)
		if err := writer.Write(record); err != nil {
			_ = temporary.Close()
			return fmt.Errorf("write rejected line %d: %w", reject.Line, err)
		}
	}
	writer.Flush()
	if err := writer.Error(); err != nil {
		_ = temporary.Close()
		return fmt.Errorf("flush reject file: %w", err)
	}
	if err := temporary.Close(); err != nil {
		return fmt.Errorf("close reject file: %w", err)
	}
	if err := os.Rename(temporaryPath, path); err != nil {
		return fmt.Errorf("install reject file %s: %w", path, err)
	}

	return nil
}
