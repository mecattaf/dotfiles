package repo

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/mecattaf/crm/internal/model"
)

const contactColumns = `id, name, name_norm, org_id, job_title, email, phone,
linkedin, location, context, relationship_hint, provenance_sources,
provenance_details, created_at, updated_at, archived_at`

// ContactRepo owns contact persistence.
type ContactRepo struct {
	database *sql.DB
}

// NewContactRepo constructs a contact repository.
func NewContactRepo(database *sql.DB) *ContactRepo {
	return &ContactRepo{database: database}
}

func scanContact(row scanner) (*model.Contact, error) {
	var contact model.Contact
	var orgID sql.NullInt64
	var jobTitle sql.NullString
	var email sql.NullString
	var phone sql.NullString
	var linkedIn sql.NullString
	var location sql.NullString
	var contextValue sql.NullString
	var relationshipHint sql.NullString
	var provenanceSources sql.NullString
	var provenanceDetails sql.NullString
	var archivedAt sql.NullString

	if err := row.Scan(
		&contact.ID,
		&contact.Name,
		&contact.NameNorm,
		&orgID,
		&jobTitle,
		&email,
		&phone,
		&linkedIn,
		&location,
		&contextValue,
		&relationshipHint,
		&provenanceSources,
		&provenanceDetails,
		&contact.CreatedAt,
		&contact.UpdatedAt,
		&archivedAt,
	); err != nil {
		return nil, err
	}

	contact.Ref = fmt.Sprintf("c%d", contact.ID)
	contact.OrgID = nullInt64(orgID)
	contact.JobTitle = nullString(jobTitle)
	contact.Email = nullString(email)
	contact.Phone = nullString(phone)
	contact.LinkedIn = nullString(linkedIn)
	contact.Location = nullString(location)
	contact.Context = nullString(contextValue)
	contact.RelationshipHint = nullString(relationshipHint)
	contact.ProvenanceSources = nullString(provenanceSources)
	contact.ProvenanceDetails = nullString(provenanceDetails)
	contact.ArchivedAt = nullString(archivedAt)
	contact.Links = make([]model.ContextLink, 0)

	return &contact, nil
}

func nullInt64(value sql.NullInt64) *int64 {
	if !value.Valid {
		return nil
	}

	return &value.Int64
}

// Create inserts a contact and returns its committed record. The live email
// UNIQUE index is the sole duplicate arbiter.
func (repository *ContactRepo) Create(
	ctx context.Context,
	input model.CreateContactInput,
) (*model.Contact, error) {
	name := strings.TrimSpace(input.Name)
	nameNorm, ok := model.TryNormalizeName(name)
	if !ok {
		return nil, model.NewExitError(model.ErrValidation, "contact name must not be empty")
	}

	email, err := normalizedOptionalString(input.Email, model.NormalizeEmail)
	if err != nil {
		return nil, err
	}
	phone, err := normalizedOptionalString(input.Phone, model.NormalizePhone)
	if err != nil {
		return nil, err
	}
	linkedIn, err := normalizedOptionalString(input.LinkedIn, model.NormalizeLinkedIn)
	if err != nil {
		return nil, err
	}
	location, err := normalizedOptionalString(input.Location, model.NormalizeLocation)
	if err != nil {
		return nil, err
	}

	now := time.Now().UTC().Format(time.RFC3339)
	transaction, err := repository.database.BeginTx(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("begin contact create: %w", err)
	}
	defer func() {
		_ = transaction.Rollback()
	}()

	result, err := transaction.ExecContext(
		ctx,
		`INSERT INTO contacts (
            name, name_norm, org_id, job_title, email, phone, linkedin,
            location, context, relationship_hint, provenance_sources,
            provenance_details, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		name,
		nameNorm,
		optionalInt64Argument(input.OrgID),
		optionalString(input.JobTitle),
		optionalStringArgument(email),
		optionalStringArgument(phone),
		optionalStringArgument(linkedIn),
		optionalStringArgument(location),
		optionalString(input.Context),
		optionalString(input.RelationshipHint),
		joinedValues(input.ProvenanceSources),
		joinedValues(input.ProvenanceDetails),
		now,
		now,
	)
	if err != nil {
		if isUniqueConstraint(err) && email != nil {
			if rollbackErr := transaction.Rollback(); rollbackErr != nil {
				return nil, errors.Join(
					fmt.Errorf("insert contact: %w", err),
					fmt.Errorf("rollback contact create: %w", rollbackErr),
				)
			}

			return repository.translateDuplicateEmail(ctx, *email, err)
		}

		return nil, fmt.Errorf("insert contact: %w", err)
	}

	id, err := result.LastInsertId()
	if err != nil {
		return nil, fmt.Errorf("read inserted contact id: %w", err)
	}
	if err := transaction.Commit(); err != nil {
		return nil, fmt.Errorf("commit contact create: %w", err)
	}

	// The transaction is complete before re-reading: SetMaxOpenConns(1) makes
	// a pool read while the transaction owns the connection self-deadlock.
	return repository.FindByID(ctx, id)
}

func optionalInt64Argument(value *int64) any {
	if value == nil {
		return nil
	}

	return *value
}

func (repository *ContactRepo) translateDuplicateEmail(
	ctx context.Context,
	email string,
	constraintError error,
) (*model.Contact, error) {
	row := repository.database.QueryRowContext(
		ctx,
		"SELECT "+contactColumns+" FROM contacts WHERE email = ? AND archived_at IS NULL ORDER BY id ASC LIMIT 1",
		email,
	)
	owner, err := scanContact(row)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, fmt.Errorf("write contact: %w", constraintError)
	}
	if err != nil {
		return nil, fmt.Errorf("find contact owning duplicate email: %w", err)
	}

	return nil, model.NewExitError(
		model.ErrConflict,
		"duplicate email %q — already on contact %d (%s)",
		email,
		owner.ID,
		owner.Name,
	)
}

// Update applies a true PATCH and preserves updated_at when all supplied
// fields are unchanged after normalization.
func (repository *ContactRepo) Update(
	ctx context.Context,
	id int64,
	input model.UpdateContactInput,
) (*model.Contact, error) {
	current, err := repository.FindByID(ctx, id)
	if err != nil {
		return nil, err
	}

	setClauses := make([]string, 0, 11)
	arguments := make([]any, 0, 12)
	addNullableString := func(column string, before, after *string) {
		if equalOptionalStrings(before, after) {
			return
		}
		setClauses = append(setClauses, column+" = ?")
		arguments = append(arguments, optionalStringArgument(after))
	}

	if input.OrgID != nil && !equalOptionalInt64s(current.OrgID, *input.OrgID) {
		setClauses = append(setClauses, "org_id = ?")
		arguments = append(arguments, optionalInt64Argument(*input.OrgID))
	}
	if input.JobTitle != nil {
		addNullableString("job_title", current.JobTitle, trimmedOptional(*input.JobTitle))
	}

	var duplicateEmail *string
	if input.Email != nil {
		normalized, normalizeErr := normalizedOptionalString(*input.Email, model.NormalizeEmail)
		if normalizeErr != nil {
			return nil, normalizeErr
		}
		if !equalOptionalStrings(current.Email, normalized) {
			addNullableString("email", current.Email, normalized)
			duplicateEmail = normalized
		}
	}
	if input.Phone != nil {
		normalized, normalizeErr := normalizedOptionalString(*input.Phone, model.NormalizePhone)
		if normalizeErr != nil {
			return nil, normalizeErr
		}
		addNullableString("phone", current.Phone, normalized)
	}
	if input.LinkedIn != nil {
		normalized, normalizeErr := normalizedOptionalString(*input.LinkedIn, model.NormalizeLinkedIn)
		if normalizeErr != nil {
			return nil, normalizeErr
		}
		addNullableString("linkedin", current.LinkedIn, normalized)
	}
	if input.Location != nil {
		normalized, normalizeErr := normalizedOptionalString(*input.Location, model.NormalizeLocation)
		if normalizeErr != nil {
			return nil, normalizeErr
		}
		addNullableString("location", current.Location, normalized)
	}
	if input.RelationshipHint != nil {
		addNullableString(
			"relationship_hint",
			current.RelationshipHint,
			trimmedOptional(*input.RelationshipHint),
		)
	}

	nextContext := current.Context
	contextSupplied := false
	if input.Context != nil {
		nextContext = trimmedOptional(*input.Context)
		contextSupplied = true
	}
	if input.ContextAppend != nil {
		addition := strings.TrimSpace(*input.ContextAppend)
		if addition != "" {
			nextContext = appendOptional(nextContext, addition, "\n\n")
			contextSupplied = true
		}
	}
	if contextSupplied {
		addNullableString("context", current.Context, nextContext)
	}

	if addition := joinValues(input.ProvenanceSources); addition != "" {
		addNullableString(
			"provenance_sources",
			current.ProvenanceSources,
			appendOptional(current.ProvenanceSources, addition, " || "),
		)
	}
	if addition := joinValues(input.ProvenanceDetails); addition != "" {
		addNullableString(
			"provenance_details",
			current.ProvenanceDetails,
			appendOptional(current.ProvenanceDetails, addition, " || "),
		)
	}

	if len(setClauses) == 0 {
		return current, nil
	}

	setClauses = append(setClauses, "updated_at = ?")
	arguments = append(arguments, time.Now().UTC().Format(time.RFC3339), id)
	query := fmt.Sprintf(
		"UPDATE contacts SET %s WHERE id = ?",
		strings.Join(setClauses, ", "),
	)
	result, err := repository.database.ExecContext(ctx, query, arguments...)
	if err != nil {
		if isUniqueConstraint(err) && duplicateEmail != nil {
			return repository.translateDuplicateEmail(ctx, *duplicateEmail, err)
		}

		return nil, fmt.Errorf("update contact c%d: %w", id, err)
	}
	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return nil, fmt.Errorf("read updated contact row count: %w", err)
	}
	if rowsAffected == 0 {
		return nil, model.NewExitError(model.ErrNotFound, "contact c%d not found", id)
	}

	return repository.FindByID(ctx, id)
}

func equalOptionalInt64s(left, right *int64) bool {
	if left == nil || right == nil {
		return left == nil && right == nil
	}

	return *left == *right
}

// FindByID returns a contact by numeric id, including archived rows, with
// links assembled from both endpoint directions.
func (repository *ContactRepo) FindByID(ctx context.Context, id int64) (*model.Contact, error) {
	contact, err := repository.findByID(ctx, id)
	if err != nil {
		return nil, err
	}

	links, err := NewContactLinkRepo(repository.database).FindForContact(ctx, id)
	if err != nil {
		return nil, err
	}
	contact.Links = links

	return contact, nil
}

func (repository *ContactRepo) findByID(ctx context.Context, id int64) (*model.Contact, error) {
	row := repository.database.QueryRowContext(
		ctx,
		"SELECT "+contactColumns+" FROM contacts WHERE id = ?",
		id,
	)
	contact, err := scanContact(row)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, model.NewExitError(model.ErrNotFound, "contact c%d not found", id)
	}
	if err != nil {
		return nil, fmt.Errorf("find contact c%d: %w", id, err)
	}

	return contact, nil
}

func (repository *ContactRepo) findByIDs(
	ctx context.Context,
	ids []int64,
) (map[int64]model.Contact, error) {
	contacts := make(map[int64]model.Contact, len(ids))
	if len(ids) == 0 {
		return contacts, nil
	}

	uniqueIDs := make([]int64, 0, len(ids))
	seen := make(map[int64]struct{}, len(ids))
	for _, id := range ids {
		if _, found := seen[id]; found {
			continue
		}
		seen[id] = struct{}{}
		uniqueIDs = append(uniqueIDs, id)
	}
	placeholders := make([]string, len(uniqueIDs))
	arguments := make([]any, len(uniqueIDs))
	for index, id := range uniqueIDs {
		placeholders[index] = "?"
		arguments[index] = id
	}

	rows, err := repository.database.QueryContext(
		ctx,
		"SELECT "+contactColumns+" FROM contacts WHERE id IN ("+
			strings.Join(placeholders, ",")+") ORDER BY id ASC",
		arguments...,
	)
	if err != nil {
		return nil, fmt.Errorf("batch load contacts: %w", err)
	}
	for rows.Next() {
		contact, scanErr := scanContact(rows)
		if scanErr != nil {
			_ = rows.Close()
			return nil, fmt.Errorf("scan batch contact: %w", scanErr)
		}
		contacts[contact.ID] = *contact
	}
	if err := rows.Err(); err != nil {
		_ = rows.Close()
		return nil, fmt.Errorf("iterate batch contacts: %w", err)
	}
	if err := rows.Close(); err != nil {
		return nil, fmt.Errorf("close batch contact rows: %w", err)
	}

	return contacts, nil
}

// List returns contacts in deterministic normalized-name order.
func (repository *ContactRepo) List(
	ctx context.Context,
	filters model.ContactFilters,
) ([]model.Contact, error) {
	if filters.Limit < 0 {
		return nil, model.NewExitError(model.ErrValidation, "limit must not be negative")
	}

	query := "SELECT " + contactColumns + " FROM contacts WHERE 1 = 1"
	arguments := make([]any, 0, 2)
	if !filters.All {
		query += " AND archived_at IS NULL"
	}
	if filters.OrgID != nil {
		query += " AND org_id = ?"
		arguments = append(arguments, *filters.OrgID)
	}
	query += " ORDER BY name_norm ASC, id ASC"
	if filters.Limit > 0 {
		query += " LIMIT ?"
		arguments = append(arguments, filters.Limit)
	}

	rows, err := repository.database.QueryContext(ctx, query, arguments...)
	if err != nil {
		return nil, fmt.Errorf("list contacts: %w", err)
	}

	contacts := make([]model.Contact, 0)
	for rows.Next() {
		contact, scanErr := scanContact(rows)
		if scanErr != nil {
			_ = rows.Close()
			return nil, fmt.Errorf("scan contact: %w", scanErr)
		}
		contacts = append(contacts, *contact)
	}
	if err := rows.Err(); err != nil {
		_ = rows.Close()
		return nil, fmt.Errorf("iterate contacts: %w", err)
	}
	if err := rows.Close(); err != nil {
		return nil, fmt.Errorf("close contact rows: %w", err)
	}

	// SetMaxOpenConns(1) makes a second query while sql.Rows is open
	// self-deadlock. Contacts are deliberately drained and closed before this
	// one batch query loads links for the complete record projection.
	contactIDs := make([]int64, len(contacts))
	for index := range contacts {
		contactIDs[index] = contacts[index].ID
	}
	linksByContact, err := NewContactLinkRepo(repository.database).FindForContacts(ctx, contactIDs)
	if err != nil {
		return nil, err
	}
	for index := range contacts {
		contacts[index].Links = linksByContact[contacts[index].ID]
	}

	return contacts, nil
}
