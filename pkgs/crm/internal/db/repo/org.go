// Package repo contains database repositories built on crm's configured SQL
// handle.
package repo

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/mecattaf/crm/internal/model"
	modernsqlite "modernc.org/sqlite"
	sqlite3 "modernc.org/sqlite/lib"
)

const orgColumns = `id, name, name_norm, category, website, linkedin,
location, focus, context, relationship_hint, provenance_sources,
provenance_details, created_at, updated_at, archived_at`

type scanner interface {
	Scan(destinations ...any) error
}

// OrgRepo owns organization persistence.
type OrgRepo struct {
	database *sql.DB
}

// NewOrgRepo constructs an organization repository.
func NewOrgRepo(database *sql.DB) *OrgRepo {
	return &OrgRepo{database: database}
}

func scanOrg(row scanner) (*model.Org, error) {
	var organization model.Org
	var category sql.NullString
	var website sql.NullString
	var linkedIn sql.NullString
	var location sql.NullString
	var focus sql.NullString
	var contextValue sql.NullString
	var relationshipHint sql.NullString
	var provenanceSources sql.NullString
	var provenanceDetails sql.NullString
	var archivedAt sql.NullString

	if err := row.Scan(
		&organization.ID,
		&organization.Name,
		&organization.NameNorm,
		&category,
		&website,
		&linkedIn,
		&location,
		&focus,
		&contextValue,
		&relationshipHint,
		&provenanceSources,
		&provenanceDetails,
		&organization.CreatedAt,
		&organization.UpdatedAt,
		&archivedAt,
	); err != nil {
		return nil, err
	}

	organization.Ref = fmt.Sprintf("o%d", organization.ID)
	organization.Category = nullString(category)
	organization.Website = nullString(website)
	organization.LinkedIn = nullString(linkedIn)
	organization.Location = nullString(location)
	organization.Focus = nullString(focus)
	organization.Context = nullString(contextValue)
	organization.RelationshipHint = nullString(relationshipHint)
	organization.ProvenanceSources = nullString(provenanceSources)
	organization.ProvenanceDetails = nullString(provenanceDetails)
	organization.ArchivedAt = nullString(archivedAt)

	return &organization, nil
}

func nullString(value sql.NullString) *string {
	if !value.Valid {
		return nil
	}

	return &value.String
}

// Create inserts an organization and returns its committed record. The live
// name UNIQUE index is the sole duplicate arbiter.
func (repository *OrgRepo) Create(
	ctx context.Context,
	input model.CreateOrgInput,
) (*model.Org, error) {
	name := strings.TrimSpace(input.Name)
	nameNorm, ok := model.TryNormalizeName(name)
	if !ok {
		return nil, model.NewExitError(model.ErrValidation, "organization name must not be empty")
	}

	website, err := normalizedOptional(input.Website, model.NormalizeWebsite)
	if err != nil {
		return nil, err
	}
	linkedIn, err := normalizedOptional(input.LinkedIn, model.NormalizeLinkedIn)
	if err != nil {
		return nil, err
	}
	location, err := normalizedOptional(input.Location, model.NormalizeLocation)
	if err != nil {
		return nil, err
	}

	now := time.Now().UTC().Format(time.RFC3339)
	transaction, err := repository.database.BeginTx(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("begin organization create: %w", err)
	}
	defer func() {
		_ = transaction.Rollback()
	}()

	result, err := transaction.ExecContext(
		ctx,
		`INSERT INTO orgs (
            name, name_norm, category, website, linkedin, location, focus,
            context, relationship_hint, provenance_sources,
            provenance_details, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		name,
		nameNorm,
		optionalString(input.Category),
		website,
		linkedIn,
		location,
		optionalString(input.Focus),
		optionalString(input.Context),
		optionalString(input.RelationshipHint),
		joinedValues(input.ProvenanceSources),
		joinedValues(input.ProvenanceDetails),
		now,
		now,
	)
	if err != nil {
		if isUniqueConstraint(err) {
			if rollbackErr := transaction.Rollback(); rollbackErr != nil {
				return nil, errors.Join(
					fmt.Errorf("insert organization: %w", err),
					fmt.Errorf("rollback organization create: %w", rollbackErr),
				)
			}

			return repository.translateDuplicateName(ctx, name, nameNorm, err)
		}

		return nil, fmt.Errorf("insert organization: %w", err)
	}

	id, err := result.LastInsertId()
	if err != nil {
		return nil, fmt.Errorf("read inserted organization id: %w", err)
	}
	if err := transaction.Commit(); err != nil {
		return nil, fmt.Errorf("commit organization create: %w", err)
	}

	// The transaction is complete before re-reading: SetMaxOpenConns(1) makes
	// a pool read while the transaction owns the connection self-deadlock.
	return repository.FindByID(ctx, id)
}

func normalizedOptional(
	input string,
	normalize func(string) (string, error),
) (any, error) {
	normalized, err := normalizedOptionalString(input, normalize)
	if err != nil {
		return nil, err
	}

	return optionalStringArgument(normalized), nil
}

func optionalString(input string) any {
	return optionalStringArgument(trimmedOptional(input))
}

func joinedValues(values []string) any {
	joined := joinValues(values)
	if joined == "" {
		return nil
	}

	return joined
}

func joinValues(values []string) string {
	nonempty := make([]string, 0, len(values))
	for _, value := range values {
		trimmed := strings.TrimSpace(value)
		if trimmed != "" {
			nonempty = append(nonempty, trimmed)
		}
	}
	if len(nonempty) == 0 {
		return ""
	}

	return strings.Join(nonempty, " || ")
}

func isUniqueConstraint(err error) bool {
	var sqliteError *modernsqlite.Error
	return errors.As(err, &sqliteError) &&
		sqliteError.Code() == sqlite3.SQLITE_CONSTRAINT_UNIQUE
}

func (repository *OrgRepo) translateDuplicateName(
	ctx context.Context,
	inputName string,
	nameNorm string,
	constraintError error,
) (*model.Org, error) {
	row := repository.database.QueryRowContext(
		ctx,
		"SELECT "+orgColumns+" FROM orgs WHERE name_norm = ? AND archived_at IS NULL",
		nameNorm,
	)
	owner, err := scanOrg(row)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, fmt.Errorf("insert organization: %w", constraintError)
	}
	if err != nil {
		return nil, fmt.Errorf("find organization owning duplicate name: %w", err)
	}

	return nil, model.NewExitError(
		model.ErrConflict,
		"duplicate org name %q — already on org %s (%s)",
		inputName,
		owner.Reference(),
		owner.Name,
	)
}

// Update applies a true PATCH and returns the complete persisted record. It
// avoids issuing UPDATE entirely when normalization leaves every supplied
// field unchanged, preserving updated_at for an idempotent edit.
func (repository *OrgRepo) Update(
	ctx context.Context,
	id int64,
	input model.UpdateOrgInput,
) (*model.Org, error) {
	current, err := repository.FindByID(ctx, id)
	if err != nil {
		return nil, err
	}

	setClauses := make([]string, 0, 10)
	arguments := make([]any, 0, 11)
	addNullable := func(column string, before, after *string) {
		if equalOptionalStrings(before, after) {
			return
		}
		setClauses = append(setClauses, column+" = ?")
		arguments = append(arguments, optionalStringArgument(after))
	}

	if input.Category != nil {
		addNullable("category", current.Category, trimmedOptional(*input.Category))
	}
	if input.Website != nil {
		normalized, normalizeErr := normalizedOptionalString(
			*input.Website,
			model.NormalizeWebsite,
		)
		if normalizeErr != nil {
			return nil, normalizeErr
		}
		addNullable("website", current.Website, normalized)
	}
	if input.LinkedIn != nil {
		normalized, normalizeErr := normalizedOptionalString(
			*input.LinkedIn,
			model.NormalizeLinkedIn,
		)
		if normalizeErr != nil {
			return nil, normalizeErr
		}
		addNullable("linkedin", current.LinkedIn, normalized)
	}
	if input.Location != nil {
		normalized, normalizeErr := normalizedOptionalString(
			*input.Location,
			model.NormalizeLocation,
		)
		if normalizeErr != nil {
			return nil, normalizeErr
		}
		addNullable("location", current.Location, normalized)
	}
	if input.Focus != nil {
		addNullable("focus", current.Focus, trimmedOptional(*input.Focus))
	}
	if input.RelationshipHint != nil {
		addNullable(
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
		addNullable("context", current.Context, nextContext)
	}

	if addition := joinValues(input.ProvenanceSources); addition != "" {
		addNullable(
			"provenance_sources",
			current.ProvenanceSources,
			appendOptional(current.ProvenanceSources, addition, " || "),
		)
	}
	if addition := joinValues(input.ProvenanceDetails); addition != "" {
		addNullable(
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
		"UPDATE orgs SET %s WHERE id = ?",
		strings.Join(setClauses, ", "),
	)
	result, err := repository.database.ExecContext(ctx, query, arguments...)
	if err != nil {
		return nil, fmt.Errorf("update organization o%d: %w", id, err)
	}
	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return nil, fmt.Errorf("read updated organization row count: %w", err)
	}
	if rowsAffected == 0 {
		return nil, model.NewExitError(model.ErrNotFound, "organization o%d not found", id)
	}

	return repository.FindByID(ctx, id)
}

func normalizedOptionalString(
	input string,
	normalize func(string) (string, error),
) (*string, error) {
	if strings.TrimSpace(input) == "" {
		return nil, nil
	}
	normalized, err := normalize(input)
	if err != nil {
		return nil, err
	}
	if normalized == "" {
		return nil, nil
	}

	return &normalized, nil
}

func trimmedOptional(input string) *string {
	trimmed := strings.TrimSpace(input)
	if trimmed == "" {
		return nil
	}

	return &trimmed
}

func appendOptional(current *string, addition, separator string) *string {
	if current == nil || *current == "" {
		return &addition
	}
	combined := *current + separator + addition

	return &combined
}

func equalOptionalStrings(left, right *string) bool {
	if left == nil || right == nil {
		return left == nil && right == nil
	}

	return *left == *right
}

func optionalStringArgument(value *string) any {
	if value == nil {
		return nil
	}

	return *value
}

// FindByID returns an organization by numeric id, including archived rows.
func (repository *OrgRepo) FindByID(ctx context.Context, id int64) (*model.Org, error) {
	row := repository.database.QueryRowContext(
		ctx,
		"SELECT "+orgColumns+" FROM orgs WHERE id = ?",
		id,
	)
	organization, err := scanOrg(row)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, model.NewExitError(model.ErrNotFound, "organization o%d not found", id)
	}
	if err != nil {
		return nil, fmt.Errorf("find organization o%d: %w", id, err)
	}

	return organization, nil
}

// List returns organizations in deterministic normalized-name order.
func (repository *OrgRepo) List(
	ctx context.Context,
	filters model.OrgFilters,
) ([]model.Org, error) {
	if filters.Limit < 0 {
		return nil, model.NewExitError(model.ErrValidation, "limit must not be negative")
	}

	query := "SELECT " + orgColumns + " FROM orgs WHERE 1 = 1"
	arguments := make([]any, 0, 2)
	if !filters.All {
		query += " AND archived_at IS NULL"
	}
	if filters.Category != nil {
		query += " AND category = ?"
		arguments = append(arguments, *filters.Category)
	}
	query += " ORDER BY name_norm ASC, id ASC"
	if filters.Limit > 0 {
		query += " LIMIT ?"
		arguments = append(arguments, filters.Limit)
	}

	rows, err := repository.database.QueryContext(ctx, query, arguments...)
	if err != nil {
		return nil, fmt.Errorf("list organizations: %w", err)
	}
	defer func() {
		_ = rows.Close()
	}()

	organizations := make([]model.Org, 0)
	for rows.Next() {
		organization, scanErr := scanOrg(rows)
		if scanErr != nil {
			return nil, fmt.Errorf("scan organization: %w", scanErr)
		}
		organizations = append(organizations, *organization)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate organizations: %w", err)
	}

	return organizations, nil
}
