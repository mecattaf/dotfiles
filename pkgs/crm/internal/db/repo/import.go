package repo

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/mecattaf/crm/internal/model"
)

const importSavepoint = "crm_import_row"

// ImportField preserves the distinction between an absent CSV column and an
// explicitly empty cell. Import update uses that distinction as true PATCH
// input.
type ImportField struct {
	Value   string
	Present bool
}

// ImportOrgRow is one parsed organization CSV row.
type ImportOrgRow struct {
	Line              int
	ID                ImportField
	Name              string
	Category          ImportField
	Website           ImportField
	LinkedIn          ImportField
	Location          ImportField
	Focus             ImportField
	Context           ImportField
	RelationshipHint  ImportField
	ProvenanceSources ImportField
	ProvenanceDetails ImportField
	CreatedAt         ImportField
	UpdatedAt         ImportField
	ArchivedAt        ImportField
}

// ImportContactRow is one parsed contact CSV row.
type ImportContactRow struct {
	Line              int
	ID                ImportField
	Name              string
	OrgID             ImportField
	Org               ImportField
	JobTitle          ImportField
	Email             ImportField
	Phone             ImportField
	LinkedIn          ImportField
	Location          ImportField
	Context           ImportField
	RelationshipHint  ImportField
	ProvenanceSources ImportField
	ProvenanceDetails ImportField
	CreatedAt         ImportField
	UpdatedAt         ImportField
	ArchivedAt        ImportField
}

// ImportOptions controls one file transaction.
type ImportOptions struct {
	Source        string
	Update        bool
	DryRun        bool
	SkipErrors    bool
	CreateMissing bool
}

// ImportCreated identifies one record inserted by an import. Contact imports
// may include both a stub organization and the contact from one CSV row.
type ImportCreated struct {
	Entity string
	ID     int64
	Ref    string
	Name   string
}

// ImportReject is one row failure retained after savepoint rollback.
type ImportReject struct {
	Line    int
	Message string
}

// ImportResult is the complete observable outcome of one file transaction.
type ImportResult struct {
	Imported          int
	Updated           int
	Skipped           int
	Errors            int
	Created           []ImportCreated
	AutoCreated       []ImportCreated
	Actions           []model.ImportAction
	Rejects           []ImportReject
	ChangedPrimaryIDs []int64
}

type importRowOutcome struct {
	operation   string
	actions     []model.ImportAction
	created     []ImportCreated
	autoCreated []ImportCreated
	changedID   int64
}

// ImportRepo owns the one-transaction import path.
type ImportRepo struct {
	database *sql.DB
}

// NewImportRepo constructs an import repository.
func NewImportRepo(database *sql.DB) *ImportRepo {
	return &ImportRepo{database: database}
}

// ImportOrganizations imports every organization row in one transaction.
func (repository *ImportRepo) ImportOrganizations(
	ctx context.Context,
	rows []ImportOrgRow,
	options ImportOptions,
) (ImportResult, error) {
	return runFileImport(
		ctx,
		repository.database,
		rows,
		options,
		func(row ImportOrgRow) int { return row.Line },
		func(transaction *sql.Tx, row ImportOrgRow) (importRowOutcome, error) {
			return repository.importOrganizationRow(ctx, transaction, row, options)
		},
	)
}

// ImportContacts imports every contact row in one transaction.
func (repository *ImportRepo) ImportContacts(
	ctx context.Context,
	rows []ImportContactRow,
	options ImportOptions,
) (ImportResult, error) {
	return runFileImport(
		ctx,
		repository.database,
		rows,
		options,
		func(row ImportContactRow) int { return row.Line },
		func(transaction *sql.Tx, row ImportContactRow) (importRowOutcome, error) {
			return repository.importContactRow(ctx, transaction, row, options)
		},
	)
}

func runFileImport[T any](
	ctx context.Context,
	database *sql.DB,
	rows []T,
	options ImportOptions,
	lineOf func(T) int,
	process func(*sql.Tx, T) (importRowOutcome, error),
) (ImportResult, error) {
	result := ImportResult{
		Created:           make([]ImportCreated, 0),
		AutoCreated:       make([]ImportCreated, 0),
		Actions:           make([]model.ImportAction, 0, len(rows)),
		Rejects:           make([]ImportReject, 0),
		ChangedPrimaryIDs: make([]int64, 0),
	}
	transaction, err := database.BeginTx(ctx, nil)
	if err != nil {
		return result, fmt.Errorf("begin import: %w", err)
	}
	defer func() {
		_ = transaction.Rollback()
	}()

	for _, row := range rows {
		outcome, rowErr := processImportRow(transaction, row, options.SkipErrors, process)
		if rowErr != nil {
			if !options.SkipErrors {
				return result, fmt.Errorf("line %d: %w", lineOf(row), rowErr)
			}
			result.Skipped++
			result.Errors++
			result.Rejects = append(result.Rejects, ImportReject{
				Line:    lineOf(row),
				Message: rowErr.Error(),
			})

			continue
		}
		applyImportOutcome(&result, outcome)
	}

	if options.DryRun {
		if err := transaction.Rollback(); err != nil {
			return result, fmt.Errorf("roll back import dry run: %w", err)
		}

		return result, nil
	}
	if err := transaction.Commit(); err != nil {
		return result, fmt.Errorf("commit import: %w", err)
	}

	return result, nil
}

func processImportRow[T any](
	transaction *sql.Tx,
	row T,
	useSavepoint bool,
	process func(*sql.Tx, T) (importRowOutcome, error),
) (importRowOutcome, error) {
	if !useSavepoint {
		return process(transaction, row)
	}
	if _, err := transaction.Exec("SAVEPOINT " + importSavepoint); err != nil {
		return importRowOutcome{}, fmt.Errorf("open import row savepoint: %w", err)
	}
	outcome, err := process(transaction, row)
	if err != nil {
		if _, rollbackErr := transaction.Exec("ROLLBACK TO SAVEPOINT " + importSavepoint); rollbackErr != nil {
			return importRowOutcome{}, errors.Join(
				err,
				fmt.Errorf("roll back import row savepoint: %w", rollbackErr),
			)
		}
		if _, releaseErr := transaction.Exec("RELEASE SAVEPOINT " + importSavepoint); releaseErr != nil {
			return importRowOutcome{}, errors.Join(
				err,
				fmt.Errorf("release failed import row savepoint: %w", releaseErr),
			)
		}

		return importRowOutcome{}, err
	}
	if _, err := transaction.Exec("RELEASE SAVEPOINT " + importSavepoint); err != nil {
		return importRowOutcome{}, fmt.Errorf("release import row savepoint: %w", err)
	}

	return outcome, nil
}

func applyImportOutcome(result *ImportResult, outcome importRowOutcome) {
	switch outcome.operation {
	case "create":
		result.Imported++
	case "update":
		result.Updated++
	case "skip":
		result.Skipped++
	}
	result.Actions = append(result.Actions, outcome.actions...)
	result.Created = append(result.Created, outcome.created...)
	result.AutoCreated = append(result.AutoCreated, outcome.autoCreated...)
	if outcome.changedID > 0 {
		result.ChangedPrimaryIDs = append(result.ChangedPrimaryIDs, outcome.changedID)
	}
}

func (repository *ImportRepo) importOrganizationRow(
	ctx context.Context,
	transaction *sql.Tx,
	row ImportOrgRow,
	options ImportOptions,
) (importRowOutcome, error) {
	name := strings.TrimSpace(row.Name)
	nameNorm, ok := model.TryNormalizeName(name)
	if !ok {
		return importRowOutcome{}, model.NewExitError(
			model.ErrValidation,
			"organization name must not be empty",
		)
	}

	existing, err := findImportOrg(ctx, transaction, nameNorm)
	if err != nil {
		return importRowOutcome{}, err
	}
	if existing != nil && !options.Update {
		return importRowOutcome{
			operation: "skip",
			actions: []model.ImportAction{{
				Operation: "skip", Entity: "org", Ref: existing.Reference(), Name: existing.Name,
			}},
		}, nil
	}
	if existing != nil {
		if err := updateImportedOrg(ctx, transaction, *existing, row, options.Source); err != nil {
			return importRowOutcome{}, err
		}

		return importRowOutcome{
			operation: "update",
			changedID: existing.ID,
			actions: []model.ImportAction{{
				Operation: "update", Entity: "org", Ref: existing.Reference(), Name: existing.Name,
			}},
		}, nil
	}

	created, err := insertImportedOrg(ctx, transaction, row, options.Source)
	if err != nil {
		return importRowOutcome{}, err
	}

	return importRowOutcome{
		operation: "create",
		changedID: created.ID,
		created:   []ImportCreated{created},
		actions: []model.ImportAction{{
			Operation: "create", Entity: "org", Ref: created.Ref, Name: created.Name,
		}},
	}, nil
}

func insertImportedOrg(
	ctx context.Context,
	transaction *sql.Tx,
	row ImportOrgRow,
	source string,
) (ImportCreated, error) {
	name := strings.TrimSpace(row.Name)
	nameNorm, ok := model.TryNormalizeName(name)
	if !ok {
		return ImportCreated{}, model.NewExitError(
			model.ErrValidation,
			"organization name must not be empty",
		)
	}
	id, err := parseImportID(row.ID, "organization")
	if err != nil {
		return ImportCreated{}, err
	}
	website, err := normalizeImportField(row.Website, model.NormalizeWebsite)
	if err != nil {
		return ImportCreated{}, err
	}
	linkedIn, err := normalizeImportField(row.LinkedIn, model.NormalizeLinkedIn)
	if err != nil {
		return ImportCreated{}, err
	}
	location, err := normalizeImportField(row.Location, model.NormalizeLocation)
	if err != nil {
		return ImportCreated{}, err
	}
	now := time.Now().UTC().Format(time.RFC3339)
	createdAt, err := requiredImportTimestamp(row.CreatedAt, now, "created_at")
	if err != nil {
		return ImportCreated{}, err
	}
	updatedAt, err := requiredImportTimestamp(row.UpdatedAt, createdAt, "updated_at")
	if err != nil {
		return ImportCreated{}, err
	}
	archivedAt, err := optionalImportTimestamp(row.ArchivedAt, "archived_at")
	if err != nil {
		return ImportCreated{}, err
	}
	provenance := ensureImportSource(row.ProvenanceSources.Value, source)

	result, err := transaction.ExecContext(
		ctx,
		`INSERT INTO orgs (
            id, name, name_norm, category, website, linkedin, location, focus,
            context, relationship_hint, provenance_sources,
            provenance_details, created_at, updated_at, archived_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		optionalInt64Argument(id),
		name,
		nameNorm,
		importTextArgument(row.Category),
		optionalStringArgument(website),
		optionalStringArgument(linkedIn),
		optionalStringArgument(location),
		importTextArgument(row.Focus),
		importTextArgument(row.Context),
		importTextArgument(row.RelationshipHint),
		provenance,
		importTextArgument(row.ProvenanceDetails),
		createdAt,
		updatedAt,
		optionalStringArgument(archivedAt),
	)
	if err != nil {
		return ImportCreated{}, fmt.Errorf("insert imported organization %q: %w", name, err)
	}
	createdID, err := result.LastInsertId()
	if err != nil {
		return ImportCreated{}, fmt.Errorf("read imported organization id: %w", err)
	}

	return ImportCreated{
		Entity: "org",
		ID:     createdID,
		Ref:    fmt.Sprintf("o%d", createdID),
		Name:   name,
	}, nil
}

func updateImportedOrg(
	ctx context.Context,
	transaction *sql.Tx,
	current model.Org,
	row ImportOrgRow,
	source string,
) error {
	setClauses := make([]string, 0, 10)
	arguments := make([]any, 0, 11)
	name := strings.TrimSpace(row.Name)
	nameNorm, ok := model.TryNormalizeName(name)
	if !ok {
		return model.NewExitError(model.ErrValidation, "organization name must not be empty")
	}
	if current.Name != name {
		setClauses = append(setClauses, "name = ?", "name_norm = ?")
		arguments = append(arguments, name, nameNorm)
	}
	addText := func(column string, field ImportField) {
		if field.Present {
			setClauses = append(setClauses, column+" = ?")
			arguments = append(arguments, importTextArgument(field))
		}
	}
	addNormalized := func(
		column string,
		field ImportField,
		normalize func(string) (string, error),
	) error {
		if !field.Present {
			return nil
		}
		value, err := normalizeImportField(field, normalize)
		if err != nil {
			return err
		}
		setClauses = append(setClauses, column+" = ?")
		arguments = append(arguments, optionalStringArgument(value))

		return nil
	}

	addText("category", row.Category)
	if err := addNormalized("website", row.Website, model.NormalizeWebsite); err != nil {
		return err
	}
	if err := addNormalized("linkedin", row.LinkedIn, model.NormalizeLinkedIn); err != nil {
		return err
	}
	if err := addNormalized("location", row.Location, model.NormalizeLocation); err != nil {
		return err
	}
	addText("focus", row.Focus)
	addText("context", row.Context)
	addText("relationship_hint", row.RelationshipHint)

	provenance := current.ProvenanceSources
	if row.ProvenanceSources.Present {
		provenance = appendImportValue(provenance, row.ProvenanceSources.Value)
	}
	provenance = appendImportValue(provenance, source)
	setClauses = append(setClauses, "provenance_sources = ?")
	arguments = append(arguments, optionalStringArgument(provenance))
	if row.ProvenanceDetails.Present {
		setClauses = append(setClauses, "provenance_details = ?")
		arguments = append(arguments, optionalStringArgument(
			appendImportValue(current.ProvenanceDetails, row.ProvenanceDetails.Value),
		))
	}
	setClauses = append(setClauses, "updated_at = ?")
	arguments = append(arguments, time.Now().UTC().Format(time.RFC3339), current.ID)

	if _, err := transaction.ExecContext(
		ctx,
		"UPDATE orgs SET "+strings.Join(setClauses, ", ")+" WHERE id = ?",
		arguments...,
	); err != nil {
		return fmt.Errorf("update imported organization %s: %w", current.Reference(), err)
	}

	return nil
}

func (repository *ImportRepo) importContactRow(
	ctx context.Context,
	transaction *sql.Tx,
	row ImportContactRow,
	options ImportOptions,
) (importRowOutcome, error) {
	name := strings.TrimSpace(row.Name)
	nameNorm, ok := model.TryNormalizeName(name)
	if !ok {
		return importRowOutcome{}, model.NewExitError(
			model.ErrValidation,
			"contact name must not be empty",
		)
	}
	email, err := normalizeImportField(row.Email, model.NormalizeEmail)
	if err != nil {
		return importRowOutcome{}, err
	}
	existing, err := findImportContact(ctx, transaction, email, nameNorm)
	if err != nil {
		return importRowOutcome{}, err
	}
	if existing != nil && !options.Update {
		return importRowOutcome{
			operation: "skip",
			actions: []model.ImportAction{{
				Operation: "skip", Entity: "contact", Ref: existing.Reference(), Name: existing.Name,
			}},
		}, nil
	}

	var orgID **int64
	created := make([]ImportCreated, 0, 2)
	autoCreated := make([]ImportCreated, 0, 1)
	actions := make([]model.ImportAction, 0, 2)
	if row.OrgID.Present || row.Org.Present {
		resolvedOrgID, stub, resolveErr := resolveImportedOrg(
			ctx,
			transaction,
			row.OrgID,
			row.Org,
			options,
		)
		if resolveErr != nil {
			return importRowOutcome{}, resolveErr
		}
		orgID = &resolvedOrgID
		if stub != nil {
			created = append(created, *stub)
			autoCreated = append(autoCreated, *stub)
			actions = append(actions, model.ImportAction{
				Operation: "create", Entity: "org", Ref: stub.Ref, Name: stub.Name,
			})
		}
	}

	if existing != nil {
		if err := updateImportedContact(
			ctx,
			transaction,
			*existing,
			row,
			orgID,
			email,
			options.Source,
		); err != nil {
			return importRowOutcome{}, err
		}
		actions = append(actions, model.ImportAction{
			Operation: "update", Entity: "contact", Ref: existing.Reference(), Name: existing.Name,
		})

		return importRowOutcome{
			operation:   "update",
			changedID:   existing.ID,
			created:     created,
			autoCreated: autoCreated,
			actions:     actions,
		}, nil
	}

	var createOrgID *int64
	if orgID != nil {
		createOrgID = *orgID
	}
	contact, err := insertImportedContact(
		ctx,
		transaction,
		row,
		createOrgID,
		email,
		options.Source,
	)
	if err != nil {
		return importRowOutcome{}, err
	}
	created = append(created, contact)
	actions = append(actions, model.ImportAction{
		Operation: "create", Entity: "contact", Ref: contact.Ref, Name: contact.Name,
	})

	return importRowOutcome{
		operation:   "create",
		changedID:   contact.ID,
		created:     created,
		autoCreated: autoCreated,
		actions:     actions,
	}, nil
}

func insertImportedContact(
	ctx context.Context,
	transaction *sql.Tx,
	row ImportContactRow,
	orgID *int64,
	email *string,
	source string,
) (ImportCreated, error) {
	name := strings.TrimSpace(row.Name)
	nameNorm, ok := model.TryNormalizeName(name)
	if !ok {
		return ImportCreated{}, model.NewExitError(
			model.ErrValidation,
			"contact name must not be empty",
		)
	}
	id, err := parseImportID(row.ID, "contact")
	if err != nil {
		return ImportCreated{}, err
	}
	phone, err := normalizeImportField(row.Phone, model.NormalizePhone)
	if err != nil {
		return ImportCreated{}, err
	}
	linkedIn, err := normalizeImportField(row.LinkedIn, model.NormalizeLinkedIn)
	if err != nil {
		return ImportCreated{}, err
	}
	location, err := normalizeImportField(row.Location, model.NormalizeLocation)
	if err != nil {
		return ImportCreated{}, err
	}
	now := time.Now().UTC().Format(time.RFC3339)
	createdAt, err := requiredImportTimestamp(row.CreatedAt, now, "created_at")
	if err != nil {
		return ImportCreated{}, err
	}
	updatedAt, err := requiredImportTimestamp(row.UpdatedAt, createdAt, "updated_at")
	if err != nil {
		return ImportCreated{}, err
	}
	archivedAt, err := optionalImportTimestamp(row.ArchivedAt, "archived_at")
	if err != nil {
		return ImportCreated{}, err
	}
	provenance := ensureImportSource(row.ProvenanceSources.Value, source)

	result, err := transaction.ExecContext(
		ctx,
		`INSERT INTO contacts (
            id, name, name_norm, org_id, job_title, email, phone, linkedin,
            location, context, relationship_hint, provenance_sources,
            provenance_details, created_at, updated_at, archived_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		optionalInt64Argument(id),
		name,
		nameNorm,
		optionalInt64Argument(orgID),
		importTextArgument(row.JobTitle),
		optionalStringArgument(email),
		optionalStringArgument(phone),
		optionalStringArgument(linkedIn),
		optionalStringArgument(location),
		importTextArgument(row.Context),
		importTextArgument(row.RelationshipHint),
		provenance,
		importTextArgument(row.ProvenanceDetails),
		createdAt,
		updatedAt,
		optionalStringArgument(archivedAt),
	)
	if err != nil {
		return ImportCreated{}, fmt.Errorf("insert imported contact %q: %w", name, err)
	}
	createdID, err := result.LastInsertId()
	if err != nil {
		return ImportCreated{}, fmt.Errorf("read imported contact id: %w", err)
	}

	return ImportCreated{
		Entity: "contact",
		ID:     createdID,
		Ref:    fmt.Sprintf("c%d", createdID),
		Name:   name,
	}, nil
}

func updateImportedContact(
	ctx context.Context,
	transaction *sql.Tx,
	current model.Contact,
	row ImportContactRow,
	orgID **int64,
	email *string,
	source string,
) error {
	setClauses := make([]string, 0, 11)
	arguments := make([]any, 0, 12)
	name := strings.TrimSpace(row.Name)
	nameNorm, ok := model.TryNormalizeName(name)
	if !ok {
		return model.NewExitError(model.ErrValidation, "contact name must not be empty")
	}
	if current.Name != name {
		setClauses = append(setClauses, "name = ?", "name_norm = ?")
		arguments = append(arguments, name, nameNorm)
	}
	addText := func(column string, field ImportField) {
		if field.Present {
			setClauses = append(setClauses, column+" = ?")
			arguments = append(arguments, importTextArgument(field))
		}
	}
	addNormalized := func(
		column string,
		field ImportField,
		normalize func(string) (string, error),
	) error {
		if !field.Present {
			return nil
		}
		value, err := normalizeImportField(field, normalize)
		if err != nil {
			return err
		}
		setClauses = append(setClauses, column+" = ?")
		arguments = append(arguments, optionalStringArgument(value))

		return nil
	}

	if orgID != nil {
		setClauses = append(setClauses, "org_id = ?")
		arguments = append(arguments, optionalInt64Argument(*orgID))
	}
	addText("job_title", row.JobTitle)
	if row.Email.Present {
		setClauses = append(setClauses, "email = ?")
		arguments = append(arguments, optionalStringArgument(email))
	}
	if err := addNormalized("phone", row.Phone, model.NormalizePhone); err != nil {
		return err
	}
	if err := addNormalized("linkedin", row.LinkedIn, model.NormalizeLinkedIn); err != nil {
		return err
	}
	if err := addNormalized("location", row.Location, model.NormalizeLocation); err != nil {
		return err
	}
	addText("context", row.Context)
	addText("relationship_hint", row.RelationshipHint)

	provenance := current.ProvenanceSources
	if row.ProvenanceSources.Present {
		provenance = appendImportValue(provenance, row.ProvenanceSources.Value)
	}
	provenance = appendImportValue(provenance, source)
	setClauses = append(setClauses, "provenance_sources = ?")
	arguments = append(arguments, optionalStringArgument(provenance))
	if row.ProvenanceDetails.Present {
		setClauses = append(setClauses, "provenance_details = ?")
		arguments = append(arguments, optionalStringArgument(
			appendImportValue(current.ProvenanceDetails, row.ProvenanceDetails.Value),
		))
	}
	setClauses = append(setClauses, "updated_at = ?")
	arguments = append(arguments, time.Now().UTC().Format(time.RFC3339), current.ID)

	if _, err := transaction.ExecContext(
		ctx,
		"UPDATE contacts SET "+strings.Join(setClauses, ", ")+" WHERE id = ?",
		arguments...,
	); err != nil {
		return fmt.Errorf("update imported contact %s: %w", current.Reference(), err)
	}

	return nil
}

func resolveImportedOrg(
	ctx context.Context,
	transaction *sql.Tx,
	idField ImportField,
	nameField ImportField,
	options ImportOptions,
) (*int64, *ImportCreated, error) {
	if idField.Present && strings.TrimSpace(idField.Value) != "" {
		id, err := parseImportID(idField, "organization")
		if err != nil {
			return nil, nil, err
		}
		organization, found, err := findImportOrgByID(ctx, transaction, *id)
		if err != nil {
			return nil, nil, err
		}
		if !found {
			return nil, nil, model.NewExitError(
				model.ErrNotFound,
				"org id %q not found — import orgs before contacts",
				idField.Value,
			)
		}

		return &organization.ID, nil, nil
	}

	name := strings.TrimSpace(nameField.Value)
	if name == "" {
		return nil, nil, nil
	}
	nameNorm, ok := model.TryNormalizeName(name)
	if !ok {
		return nil, nil, model.NewExitError(model.ErrValidation, "organization name must not be empty")
	}
	organization, err := findImportOrg(ctx, transaction, nameNorm)
	if err != nil {
		return nil, nil, err
	}
	if organization != nil {
		return &organization.ID, nil, nil
	}
	if !options.CreateMissing {
		return nil, nil, model.NewExitError(
			model.ErrNotFound,
			"no org %q — try: crm org add %q --source %q",
			name,
			name,
			options.Source,
		)
	}

	stub, err := insertImportedOrg(ctx, transaction, ImportOrgRow{
		Name: name,
		ProvenanceSources: ImportField{
			Value:   "auto-created by crm import",
			Present: true,
		},
	}, "auto-created by crm import")
	if err != nil {
		return nil, nil, err
	}

	return &stub.ID, &stub, nil
}

func findImportOrg(
	ctx context.Context,
	transaction *sql.Tx,
	nameNorm string,
) (*model.Org, error) {
	ids, err := importMatchIDs(
		ctx,
		transaction,
		"SELECT id FROM orgs WHERE name_norm = ? ORDER BY id ASC LIMIT 2",
		nameNorm,
	)
	if err != nil {
		return nil, fmt.Errorf("match imported organization: %w", err)
	}
	if len(ids) > 1 {
		return nil, model.NewExitError(
			model.ErrAmbiguous,
			"ambiguous imported org name %q (%s)",
			nameNorm,
			joinImportRefs("o", ids),
		)
	}
	if len(ids) == 0 {
		return nil, nil
	}
	organization, _, err := findImportOrgByID(ctx, transaction, ids[0])

	return organization, err
}

func findImportOrgByID(
	ctx context.Context,
	transaction *sql.Tx,
	id int64,
) (*model.Org, bool, error) {
	organization, err := scanOrg(transaction.QueryRowContext(
		ctx,
		"SELECT "+orgColumns+" FROM orgs WHERE id = ?",
		id,
	))
	if errors.Is(err, sql.ErrNoRows) {
		return nil, false, nil
	}
	if err != nil {
		return nil, false, fmt.Errorf("find imported organization o%d: %w", id, err)
	}

	return organization, true, nil
}

func findImportContact(
	ctx context.Context,
	transaction *sql.Tx,
	email *string,
	nameNorm string,
) (*model.Contact, error) {
	if email != nil {
		contact, err := findImportContactBy(
			ctx,
			transaction,
			"email = ?",
			*email,
			"email "+strconv.Quote(*email),
		)
		if err != nil || contact != nil {
			return contact, err
		}
	}

	return findImportContactBy(
		ctx,
		transaction,
		"name_norm = ?",
		nameNorm,
		"name "+strconv.Quote(nameNorm),
	)
}

func findImportContactBy(
	ctx context.Context,
	transaction *sql.Tx,
	condition string,
	value string,
	label string,
) (*model.Contact, error) {
	ids, err := importMatchIDs(
		ctx,
		transaction,
		"SELECT id FROM contacts WHERE "+condition+" ORDER BY id ASC LIMIT 2",
		value,
	)
	if err != nil {
		return nil, fmt.Errorf("match imported contact: %w", err)
	}
	if len(ids) > 1 {
		return nil, model.NewExitError(
			model.ErrAmbiguous,
			"ambiguous imported contact %s (%s)",
			label,
			joinImportRefs("c", ids),
		)
	}
	if len(ids) == 0 {
		return nil, nil
	}
	contact, err := scanContact(transaction.QueryRowContext(
		ctx,
		"SELECT "+contactColumns+" FROM contacts WHERE id = ?",
		ids[0],
	))
	if err != nil {
		return nil, fmt.Errorf("find imported contact c%d: %w", ids[0], err)
	}

	return contact, nil
}

func importMatchIDs(
	ctx context.Context,
	transaction *sql.Tx,
	query string,
	arguments ...any,
) ([]int64, error) {
	rows, err := transaction.QueryContext(ctx, query, arguments...)
	if err != nil {
		return nil, err
	}
	ids := make([]int64, 0, 2)
	for rows.Next() {
		var id int64
		if err := rows.Scan(&id); err != nil {
			_ = rows.Close()
			return nil, err
		}
		ids = append(ids, id)
	}
	if err := rows.Err(); err != nil {
		_ = rows.Close()
		return nil, err
	}
	if err := rows.Close(); err != nil {
		return nil, err
	}

	return ids, nil
}

func joinImportRefs(prefix string, ids []int64) string {
	refs := make([]string, len(ids))
	for index, id := range ids {
		refs[index] = prefix + strconv.FormatInt(id, 10)
	}

	return strings.Join(refs, ", ")
}

func parseImportID(field ImportField, entity string) (*int64, error) {
	value := strings.TrimSpace(field.Value)
	if !field.Present || value == "" {
		return nil, nil
	}
	id, err := strconv.ParseInt(value, 10, 64)
	if err != nil || id <= 0 {
		return nil, model.NewExitError(
			model.ErrValidation,
			"invalid %s id %q",
			entity,
			field.Value,
		)
	}

	return &id, nil
}

func normalizeImportField(
	field ImportField,
	normalize func(string) (string, error),
) (*string, error) {
	if !field.Present || strings.TrimSpace(field.Value) == "" {
		return nil, nil
	}

	return normalizedOptionalString(field.Value, normalize)
}

func importTextArgument(field ImportField) any {
	if !field.Present {
		return nil
	}

	return optionalStringArgument(trimmedOptional(field.Value))
}

func requiredImportTimestamp(field ImportField, fallback, name string) (string, error) {
	value := strings.TrimSpace(field.Value)
	if !field.Present || value == "" {
		return fallback, nil
	}
	parsed, err := time.Parse(time.RFC3339, value)
	if err != nil {
		return "", model.NewExitError(model.ErrValidation, "invalid %s %q", name, field.Value)
	}

	return parsed.UTC().Format(time.RFC3339), nil
}

func optionalImportTimestamp(field ImportField, name string) (*string, error) {
	value := strings.TrimSpace(field.Value)
	if !field.Present || value == "" {
		return nil, nil
	}
	parsed, err := time.Parse(time.RFC3339, value)
	if err != nil {
		return nil, model.NewExitError(model.ErrValidation, "invalid %s %q", name, field.Value)
	}
	normalized := parsed.UTC().Format(time.RFC3339)

	return &normalized, nil
}

func ensureImportSource(existing, source string) any {
	existing = strings.TrimSpace(existing)
	source = strings.TrimSpace(source)
	if existing == "" {
		return source
	}
	for _, value := range strings.Split(existing, " || ") {
		if strings.TrimSpace(value) == source {
			return existing
		}
	}

	return existing + " || " + source
}

func appendImportValue(current *string, addition string) *string {
	addition = strings.TrimSpace(addition)
	if addition == "" {
		return current
	}
	if current == nil || *current == "" {
		return &addition
	}
	combined := *current + " || " + addition

	return &combined
}
