package repo

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"sort"
	"strings"
	"time"

	"github.com/mecattaf/crm/internal/model"
)

const interactionColumns = `i.id, i.kind, i.occurred_on, i.summary, i.body,
i.transcript_path, i.org_id, i.deal_id, i.created_at, i.updated_at,
i.archived_at`

// InteractionRepo owns interaction persistence and participant junctions.
type InteractionRepo struct {
	database *sql.DB
}

// NewInteractionRepo constructs an interaction repository.
func NewInteractionRepo(database *sql.DB) *InteractionRepo {
	return &InteractionRepo{database: database}
}

func scanInteraction(row scanner) (*model.Interaction, error) {
	var interaction model.Interaction
	var body sql.NullString
	var transcriptPath sql.NullString
	var orgID sql.NullInt64
	var dealID sql.NullInt64
	var archivedAt sql.NullString
	if err := row.Scan(
		&interaction.ID,
		&interaction.Kind,
		&interaction.OccurredOn,
		&interaction.Summary,
		&body,
		&transcriptPath,
		&orgID,
		&dealID,
		&interaction.CreatedAt,
		&interaction.UpdatedAt,
		&archivedAt,
	); err != nil {
		return nil, err
	}

	interaction.Ref = fmt.Sprintf("i%d", interaction.ID)
	interaction.Body = nullString(body)
	interaction.TranscriptPath = nullString(transcriptPath)
	interaction.OrgID = nullInt64(orgID)
	interaction.DealID = nullInt64(dealID)
	interaction.ContactIDs = make([]int64, 0)
	interaction.ArchivedAt = nullString(archivedAt)

	return &interaction, nil
}

// Create inserts an interaction and all participant rows in one transaction.
func (repository *InteractionRepo) Create(
	ctx context.Context,
	input model.CreateInteractionInput,
) (*model.Interaction, error) {
	kind, occurredOn, summary, err := validateInteractionValues(
		input.Kind,
		input.OccurredOn,
		input.Summary,
	)
	if err != nil {
		return nil, err
	}
	contactIDs, err := normalizedIDs(input.ContactIDs)
	if err != nil {
		return nil, err
	}
	if len(contactIDs) == 0 && input.OrgID == nil && input.DealID == nil {
		return nil, model.NewExitError(
			model.ErrValidation,
			"log requires at least one of --with, --org, or --deal",
		)
	}

	now := time.Now().UTC().Format(time.RFC3339)
	transaction, err := repository.database.BeginTx(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("begin interaction create: %w", err)
	}
	defer func() {
		_ = transaction.Rollback()
	}()

	result, err := transaction.ExecContext(
		ctx,
		`INSERT INTO interactions (
            kind, occurred_on, summary, body, transcript_path, org_id,
            deal_id, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		kind,
		occurredOn,
		summary,
		optionalContentArgument(input.Body),
		optionalContentArgument(input.TranscriptPath),
		optionalInt64Argument(input.OrgID),
		optionalInt64Argument(input.DealID),
		now,
		now,
	)
	if err != nil {
		return nil, fmt.Errorf("insert interaction: %w", err)
	}
	interactionID, err := result.LastInsertId()
	if err != nil {
		return nil, fmt.Errorf("read inserted interaction id: %w", err)
	}
	for _, contactID := range contactIDs {
		if _, err := transaction.ExecContext(
			ctx,
			`INSERT INTO interaction_people (interaction_id, contact_id)
             VALUES (?, ?)`,
			interactionID,
			contactID,
		); err != nil {
			return nil, fmt.Errorf(
				"link interaction i%d to contact c%d: %w",
				interactionID,
				contactID,
				err,
			)
		}
	}
	if err := transaction.Commit(); err != nil {
		return nil, fmt.Errorf("commit interaction create: %w", err)
	}

	// The transaction is complete before re-reading: SetMaxOpenConns(1) makes
	// a pool read while the transaction owns the connection self-deadlock.
	return repository.FindByID(ctx, interactionID)
}

func validateInteractionValues(kind, occurredOn, summary string) (string, string, string, error) {
	kind = strings.TrimSpace(kind)
	if !model.ValidInteractionKind(kind) {
		return "", "", "", model.NewExitError(
			model.ErrValidation,
			"invalid interaction kind %q (accepted: %s)",
			kind,
			strings.Join(model.InteractionKinds, ","),
		)
	}
	if strings.TrimSpace(occurredOn) == "" {
		occurredOn = time.Now().Format("2006-01-02")
	}
	occurredOn, err := model.NormalizeDate(occurredOn)
	if err != nil {
		return "", "", "", err
	}
	summary = strings.TrimSpace(summary)
	if summary == "" {
		return "", "", "", model.NewExitError(
			model.ErrValidation,
			"interaction summary must not be empty",
		)
	}

	return kind, occurredOn, summary, nil
}

func optionalContentArgument(value *string) any {
	if value == nil || *value == "" {
		return nil
	}

	return *value
}

func normalizedIDs(values []int64) ([]int64, error) {
	seen := make(map[int64]struct{}, len(values))
	result := make([]int64, 0, len(values))
	for _, value := range values {
		if value <= 0 {
			return nil, model.NewExitError(
				model.ErrValidation,
				"contact id must be positive (got %d)",
				value,
			)
		}
		if _, exists := seen[value]; exists {
			continue
		}
		seen[value] = struct{}{}
		result = append(result, value)
	}
	sort.Slice(result, func(left, right int) bool {
		return result[left] < result[right]
	})

	return result, nil
}

// FindByID returns an interaction by numeric id, including archived rows.
func (repository *InteractionRepo) FindByID(
	ctx context.Context,
	id int64,
) (*model.Interaction, error) {
	row := repository.database.QueryRowContext(
		ctx,
		"SELECT "+interactionColumns+" FROM interactions i WHERE i.id = ?",
		id,
	)
	interaction, err := scanInteraction(row)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, model.NewExitError(model.ErrNotFound, "interaction i%d not found", id)
	}
	if err != nil {
		return nil, fmt.Errorf("find interaction i%d: %w", id, err)
	}
	interactions := []model.Interaction{*interaction}
	if err := repository.loadContactIDs(ctx, interactions); err != nil {
		return nil, err
	}

	return &interactions[0], nil
}

// List returns interactions ordered by occurred_on DESC, id DESC.
func (repository *InteractionRepo) List(
	ctx context.Context,
	filters model.InteractionFilters,
) ([]model.Interaction, error) {
	if filters.Limit < 0 {
		return nil, model.NewExitError(model.ErrValidation, "limit must not be negative")
	}
	if filters.Kind != nil && !model.ValidInteractionKind(*filters.Kind) {
		return nil, model.NewExitError(
			model.ErrValidation,
			"invalid interaction kind %q (accepted: %s)",
			*filters.Kind,
			strings.Join(model.InteractionKinds, ","),
		)
	}

	query := "SELECT " + interactionColumns + " FROM interactions i WHERE 1 = 1"
	arguments := make([]any, 0, 5)
	if !filters.All {
		query += " AND i.archived_at IS NULL"
	}
	if filters.ContactID != nil {
		query += ` AND EXISTS (
            SELECT 1 FROM interaction_people ip
            WHERE ip.interaction_id = i.id AND ip.contact_id = ?
        )`
		arguments = append(arguments, *filters.ContactID)
	}
	if filters.OrgID != nil {
		query += " AND i.org_id = ?"
		arguments = append(arguments, *filters.OrgID)
	}
	if filters.DealID != nil {
		query += " AND i.deal_id = ?"
		arguments = append(arguments, *filters.DealID)
	}
	if filters.Kind != nil {
		query += " AND i.kind = ?"
		arguments = append(arguments, *filters.Kind)
	}
	query += " ORDER BY i.occurred_on DESC, i.id DESC"
	if filters.Limit > 0 {
		query += " LIMIT ?"
		arguments = append(arguments, filters.Limit)
	}

	rows, err := repository.database.QueryContext(ctx, query, arguments...)
	if err != nil {
		return nil, fmt.Errorf("list interactions: %w", err)
	}
	interactions := make([]model.Interaction, 0)
	for rows.Next() {
		interaction, scanErr := scanInteraction(rows)
		if scanErr != nil {
			_ = rows.Close()
			return nil, fmt.Errorf("scan interaction: %w", scanErr)
		}
		interactions = append(interactions, *interaction)
	}
	if err := rows.Err(); err != nil {
		_ = rows.Close()
		return nil, fmt.Errorf("iterate interactions: %w", err)
	}
	if err := rows.Close(); err != nil {
		return nil, fmt.Errorf("close interaction rows: %w", err)
	}

	// SetMaxOpenConns(1) makes a second query while sql.Rows is open
	// self-deadlock. The parent rows are deliberately drained and closed
	// before this single batch child query.
	if err := repository.loadContactIDs(ctx, interactions); err != nil {
		return nil, err
	}

	return interactions, nil
}

func (repository *InteractionRepo) loadContactIDs(
	ctx context.Context,
	interactions []model.Interaction,
) error {
	if len(interactions) == 0 {
		return nil
	}

	placeholders := make([]string, len(interactions))
	arguments := make([]any, len(interactions))
	byID := make(map[int64]int, len(interactions))
	for index := range interactions {
		placeholders[index] = "?"
		arguments[index] = interactions[index].ID
		byID[interactions[index].ID] = index
		interactions[index].ContactIDs = make([]int64, 0)
	}
	rows, err := repository.database.QueryContext(
		ctx,
		`SELECT interaction_id, contact_id
         FROM interaction_people
         WHERE interaction_id IN (`+strings.Join(placeholders, ",")+`)
         ORDER BY interaction_id ASC, contact_id ASC`,
		arguments...,
	)
	if err != nil {
		return fmt.Errorf("batch load interaction participants: %w", err)
	}
	defer func() {
		_ = rows.Close()
	}()

	for rows.Next() {
		var interactionID int64
		var contactID int64
		if err := rows.Scan(&interactionID, &contactID); err != nil {
			return fmt.Errorf("scan interaction participant: %w", err)
		}
		index, found := byID[interactionID]
		if found {
			interactions[index].ContactIDs = append(interactions[index].ContactIDs, contactID)
		}
	}
	if err := rows.Err(); err != nil {
		return fmt.Errorf("iterate interaction participants: %w", err)
	}

	return nil
}

// Update applies scalar PATCH fields and participant set edits atomically.
func (repository *InteractionRepo) Update(
	ctx context.Context,
	id int64,
	input model.UpdateInteractionInput,
) (*model.Interaction, error) {
	validated, err := validateInteractionPatch(input)
	if err != nil {
		return nil, err
	}

	transaction, err := repository.database.BeginTx(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("begin interaction update: %w", err)
	}
	defer func() {
		_ = transaction.Rollback()
	}()

	current, err := findInteractionInTransaction(ctx, transaction, id)
	if err != nil {
		return nil, err
	}
	currentContactIDs, err := contactIDsInTransaction(ctx, transaction, id)
	if err != nil {
		return nil, err
	}
	current.ContactIDs = currentContactIDs
	nextContactIDs := applyContactPatch(
		currentContactIDs,
		validated.AddContactIDs,
		validated.RemoveContactIDs,
	)

	nextOrgID := current.OrgID
	if validated.OrgID != nil {
		nextOrgID = *validated.OrgID
	}
	nextDealID := current.DealID
	if validated.DealID != nil {
		nextDealID = *validated.DealID
	}
	if len(nextContactIDs) == 0 && nextOrgID == nil && nextDealID == nil {
		return nil, model.NewExitError(
			model.ErrConflict,
			"interaction i%d must keep at least one link — patch would leave participants=0, org=none, deal=none",
			id,
		)
	}

	setClauses := make([]string, 0, 8)
	arguments := make([]any, 0, 9)
	addValue := func(column string, value any) {
		setClauses = append(setClauses, column+" = ?")
		arguments = append(arguments, value)
	}
	if validated.Kind != nil && *validated.Kind != current.Kind {
		addValue("kind", *validated.Kind)
	}
	if validated.OccurredOn != nil && *validated.OccurredOn != current.OccurredOn {
		addValue("occurred_on", *validated.OccurredOn)
	}
	if validated.Summary != nil && *validated.Summary != current.Summary {
		addValue("summary", *validated.Summary)
	}
	if validated.Body != nil && !equalOptionalStrings(current.Body, *validated.Body) {
		addValue("body", optionalContentArgument(*validated.Body))
	}
	if validated.TranscriptPath != nil &&
		!equalOptionalStrings(current.TranscriptPath, *validated.TranscriptPath) {
		addValue("transcript_path", optionalContentArgument(*validated.TranscriptPath))
	}
	if validated.OrgID != nil && !equalOptionalInt64s(current.OrgID, *validated.OrgID) {
		addValue("org_id", optionalInt64Argument(*validated.OrgID))
	}
	if validated.DealID != nil && !equalOptionalInt64s(current.DealID, *validated.DealID) {
		addValue("deal_id", optionalInt64Argument(*validated.DealID))
	}

	membershipChanged := !equalInt64Slices(currentContactIDs, nextContactIDs)
	if len(setClauses) == 0 && !membershipChanged {
		return current, nil
	}

	addValue("updated_at", time.Now().UTC().Format(time.RFC3339))
	arguments = append(arguments, id)
	result, err := transaction.ExecContext(
		ctx,
		"UPDATE interactions SET "+strings.Join(setClauses, ", ")+" WHERE id = ?",
		arguments...,
	)
	if err != nil {
		return nil, fmt.Errorf("update interaction i%d: %w", id, err)
	}
	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return nil, fmt.Errorf("read updated interaction row count: %w", err)
	}
	if rowsAffected == 0 {
		return nil, model.NewExitError(model.ErrNotFound, "interaction i%d not found", id)
	}

	if membershipChanged {
		if err := replaceContactIDs(
			ctx,
			transaction,
			id,
			currentContactIDs,
			nextContactIDs,
		); err != nil {
			return nil, err
		}
	}
	if err := transaction.Commit(); err != nil {
		return nil, fmt.Errorf("commit interaction update: %w", err)
	}

	return repository.FindByID(ctx, id)
}

func validateInteractionPatch(
	input model.UpdateInteractionInput,
) (model.UpdateInteractionInput, error) {
	validated := input
	if input.Kind != nil {
		kind := strings.TrimSpace(*input.Kind)
		if !model.ValidInteractionKind(kind) {
			return model.UpdateInteractionInput{}, model.NewExitError(
				model.ErrValidation,
				"invalid interaction kind %q (accepted: %s)",
				kind,
				strings.Join(model.InteractionKinds, ","),
			)
		}
		validated.Kind = &kind
	}
	if input.OccurredOn != nil {
		occurredOn, err := model.NormalizeDate(*input.OccurredOn)
		if err != nil {
			return model.UpdateInteractionInput{}, err
		}
		validated.OccurredOn = &occurredOn
	}
	if input.Summary != nil {
		summary := strings.TrimSpace(*input.Summary)
		if summary == "" {
			return model.UpdateInteractionInput{}, model.NewExitError(
				model.ErrValidation,
				"interaction summary must not be empty",
			)
		}
		validated.Summary = &summary
	}
	addContactIDs, err := normalizedIDs(input.AddContactIDs)
	if err != nil {
		return model.UpdateInteractionInput{}, err
	}
	removeContactIDs, err := normalizedIDs(input.RemoveContactIDs)
	if err != nil {
		return model.UpdateInteractionInput{}, err
	}
	if overlaps(addContactIDs, removeContactIDs) {
		return model.UpdateInteractionInput{}, model.NewExitError(
			model.ErrValidation,
			"the same contact cannot be both --add-with and --rm-with",
		)
	}
	validated.AddContactIDs = addContactIDs
	validated.RemoveContactIDs = removeContactIDs

	return validated, nil
}

func findInteractionInTransaction(
	ctx context.Context,
	transaction *sql.Tx,
	id int64,
) (*model.Interaction, error) {
	row := transaction.QueryRowContext(
		ctx,
		"SELECT "+interactionColumns+" FROM interactions i WHERE i.id = ?",
		id,
	)
	interaction, err := scanInteraction(row)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, model.NewExitError(model.ErrNotFound, "interaction i%d not found", id)
	}
	if err != nil {
		return nil, fmt.Errorf("find interaction i%d for update: %w", id, err)
	}

	return interaction, nil
}

func contactIDsInTransaction(
	ctx context.Context,
	transaction *sql.Tx,
	interactionID int64,
) ([]int64, error) {
	rows, err := transaction.QueryContext(
		ctx,
		`SELECT contact_id FROM interaction_people
         WHERE interaction_id = ? ORDER BY contact_id ASC`,
		interactionID,
	)
	if err != nil {
		return nil, fmt.Errorf("load interaction i%d participants: %w", interactionID, err)
	}
	defer func() {
		_ = rows.Close()
	}()

	contactIDs := make([]int64, 0)
	for rows.Next() {
		var contactID int64
		if err := rows.Scan(&contactID); err != nil {
			return nil, fmt.Errorf("scan interaction participant: %w", err)
		}
		contactIDs = append(contactIDs, contactID)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate interaction participants: %w", err)
	}

	return contactIDs, nil
}

func applyContactPatch(current, add, remove []int64) []int64 {
	values := make(map[int64]struct{}, len(current)+len(add))
	for _, contactID := range current {
		values[contactID] = struct{}{}
	}
	for _, contactID := range remove {
		delete(values, contactID)
	}
	for _, contactID := range add {
		values[contactID] = struct{}{}
	}
	result := make([]int64, 0, len(values))
	for contactID := range values {
		result = append(result, contactID)
	}
	sort.Slice(result, func(left, right int) bool {
		return result[left] < result[right]
	})

	return result
}

func replaceContactIDs(
	ctx context.Context,
	transaction *sql.Tx,
	interactionID int64,
	current []int64,
	next []int64,
) error {
	currentSet := idSet(current)
	nextSet := idSet(next)
	for _, contactID := range current {
		if _, keep := nextSet[contactID]; keep {
			continue
		}
		if _, err := transaction.ExecContext(
			ctx,
			"DELETE FROM interaction_people WHERE interaction_id = ? AND contact_id = ?",
			interactionID,
			contactID,
		); err != nil {
			return fmt.Errorf("unlink interaction i%d from contact c%d: %w", interactionID, contactID, err)
		}
	}
	for _, contactID := range next {
		if _, exists := currentSet[contactID]; exists {
			continue
		}
		if _, err := transaction.ExecContext(
			ctx,
			`INSERT INTO interaction_people (interaction_id, contact_id)
             VALUES (?, ?)`,
			interactionID,
			contactID,
		); err != nil {
			return fmt.Errorf("link interaction i%d to contact c%d: %w", interactionID, contactID, err)
		}
	}

	return nil
}

func overlaps(left, right []int64) bool {
	rightSet := idSet(right)
	for _, value := range left {
		if _, found := rightSet[value]; found {
			return true
		}
	}

	return false
}

func idSet(values []int64) map[int64]struct{} {
	result := make(map[int64]struct{}, len(values))
	for _, value := range values {
		result[value] = struct{}{}
	}

	return result
}

func equalInt64Slices(left, right []int64) bool {
	if len(left) != len(right) {
		return false
	}
	for index := range left {
		if left[index] != right[index] {
			return false
		}
	}

	return true
}
