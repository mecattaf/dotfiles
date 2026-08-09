package repo

import (
	"context"
	"database/sql"
	"fmt"
	"strings"
	"time"

	"github.com/mecattaf/crm/internal/model"
)

type storedContactLink struct {
	id               int64
	contactID        int64
	relatedContactID int64
	linkType         string
	note             *string
	createdAt        string
}

// ContactLinkRepo owns directed contact-link persistence and both-end reads.
type ContactLinkRepo struct {
	database *sql.DB
}

// NewContactLinkRepo constructs a contact-link repository.
func NewContactLinkRepo(database *sql.DB) *ContactLinkRepo {
	return &ContactLinkRepo{database: database}
}

// Relate inserts one directed contact link and returns the committed first
// contact with links populated from both endpoint directions.
func (repository *ContactLinkRepo) Relate(
	ctx context.Context,
	contactID int64,
	relatedContactID int64,
	linkType string,
	note string,
) (*model.Contact, error) {
	if contactID <= 0 || relatedContactID <= 0 {
		return nil, model.NewExitError(model.ErrValidation, "contact ids must be positive")
	}
	if contactID == relatedContactID {
		return nil, model.NewExitError(
			model.ErrValidation,
			"cannot relate a contact to itself",
		)
	}

	linkType = strings.TrimSpace(linkType)
	if linkType == "" {
		return nil, model.NewExitError(model.ErrValidation, "link type must not be empty")
	}
	normalizedNote := trimmedOptional(note)

	transaction, err := repository.database.BeginTx(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("begin contact relate: %w", err)
	}
	defer func() {
		_ = transaction.Rollback()
	}()

	_, err = transaction.ExecContext(
		ctx,
		`INSERT INTO contact_links (
            contact_id, related_contact_id, link_type, note, created_at
        ) VALUES (?, ?, ?, ?, ?)`,
		contactID,
		relatedContactID,
		linkType,
		optionalStringArgument(normalizedNote),
		time.Now().UTC().Format(time.RFC3339),
	)
	if err != nil {
		if isUniqueConstraint(err) {
			return nil, model.NewExitError(
				model.ErrConflict,
				"duplicate contact link c%d -> c%d with type %q",
				contactID,
				relatedContactID,
				linkType,
			)
		}

		return nil, fmt.Errorf("relate contact c%d to c%d: %w", contactID, relatedContactID, err)
	}
	if err := transaction.Commit(); err != nil {
		return nil, fmt.Errorf("commit contact relate: %w", err)
	}

	// Re-read only after commit: the transaction owns the sole pooled
	// connection until this point.
	return NewContactRepo(repository.database).FindByID(ctx, contactID)
}

// Unrelate deletes one directed typed link, or every link between the pair
// in either direction when linkType is nil. It echoes the first contact.
func (repository *ContactLinkRepo) Unrelate(
	ctx context.Context,
	contactID int64,
	relatedContactID int64,
	linkType *string,
) (*model.Contact, error) {
	if contactID <= 0 || relatedContactID <= 0 {
		return nil, model.NewExitError(model.ErrValidation, "contact ids must be positive")
	}
	if contactID == relatedContactID {
		return nil, model.NewExitError(
			model.ErrValidation,
			"cannot unrelate a contact from itself",
		)
	}

	var normalizedType *string
	if linkType != nil {
		trimmed := strings.TrimSpace(*linkType)
		if trimmed == "" {
			return nil, model.NewExitError(model.ErrValidation, "link type must not be empty")
		}
		normalizedType = &trimmed
	}

	transaction, err := repository.database.BeginTx(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("begin contact unrelate: %w", err)
	}
	defer func() {
		_ = transaction.Rollback()
	}()

	var result sql.Result
	if normalizedType != nil {
		result, err = transaction.ExecContext(
			ctx,
			`DELETE FROM contact_links
             WHERE contact_id = ? AND related_contact_id = ? AND link_type = ?`,
			contactID,
			relatedContactID,
			*normalizedType,
		)
	} else {
		result, err = transaction.ExecContext(
			ctx,
			`DELETE FROM contact_links
             WHERE (contact_id = ? AND related_contact_id = ?)
                OR (contact_id = ? AND related_contact_id = ?)`,
			contactID,
			relatedContactID,
			relatedContactID,
			contactID,
		)
	}
	if err != nil {
		return nil, fmt.Errorf("unrelate contacts c%d and c%d: %w", contactID, relatedContactID, err)
	}
	deleted, err := result.RowsAffected()
	if err != nil {
		return nil, fmt.Errorf("read unrelate row count: %w", err)
	}
	if deleted == 0 {
		if normalizedType != nil {
			return nil, model.NewExitError(
				model.ErrNotFound,
				"no contact link c%d -> c%d with type %q",
				contactID,
				relatedContactID,
				*normalizedType,
			)
		}

		return nil, model.NewExitError(
			model.ErrNotFound,
			"no contact links between c%d and c%d",
			contactID,
			relatedContactID,
		)
	}
	if err := transaction.Commit(); err != nil {
		return nil, fmt.Errorf("commit contact unrelate: %w", err)
	}

	return NewContactRepo(repository.database).FindByID(ctx, contactID)
}

// FindForContact returns every directed link touching one contact. Direction
// is expressed from the requested contact's point of view.
func (repository *ContactLinkRepo) FindForContact(
	ctx context.Context,
	contactID int64,
) ([]model.ContextLink, error) {
	if contactID <= 0 {
		return nil, model.NewExitError(model.ErrValidation, "contact id must be positive")
	}

	linksByContact, err := repository.FindForContacts(ctx, []int64{contactID})
	if err != nil {
		return nil, err
	}

	return linksByContact[contactID], nil
}

// FindForContacts batch-loads links and counterpart contacts after the link
// rows are fully drained and closed, avoiding the one-connection deadlock.
func (repository *ContactLinkRepo) FindForContacts(
	ctx context.Context,
	contactIDs []int64,
) (map[int64][]model.ContextLink, error) {
	linksByContact := make(map[int64][]model.ContextLink, len(contactIDs))
	if len(contactIDs) == 0 {
		return linksByContact, nil
	}

	uniqueIDs := make([]int64, 0, len(contactIDs))
	targets := make(map[int64]struct{}, len(contactIDs))
	for _, id := range contactIDs {
		if id <= 0 {
			return nil, model.NewExitError(model.ErrValidation, "contact id must be positive")
		}
		if _, found := targets[id]; found {
			continue
		}
		targets[id] = struct{}{}
		uniqueIDs = append(uniqueIDs, id)
		linksByContact[id] = make([]model.ContextLink, 0)
	}

	placeholders := make([]string, len(uniqueIDs))
	arguments := make([]any, 0, len(uniqueIDs)*2)
	for index, id := range uniqueIDs {
		placeholders[index] = "?"
		arguments = append(arguments, id)
	}
	for _, id := range uniqueIDs {
		arguments = append(arguments, id)
	}

	rows, err := repository.database.QueryContext(
		ctx,
		`SELECT id, contact_id, related_contact_id, link_type, note, created_at
         FROM contact_links
         WHERE contact_id IN (`+strings.Join(placeholders, ",")+`)
            OR related_contact_id IN (`+strings.Join(placeholders, ",")+`)
         ORDER BY created_at DESC, id DESC`,
		arguments...,
	)
	if err != nil {
		return nil, fmt.Errorf("find contact links: %w", err)
	}

	stored := make([]storedContactLink, 0)
	counterpartIDs := make([]int64, 0)
	for rows.Next() {
		var link storedContactLink
		var note sql.NullString
		if err := rows.Scan(
			&link.id,
			&link.contactID,
			&link.relatedContactID,
			&link.linkType,
			&note,
			&link.createdAt,
		); err != nil {
			_ = rows.Close()
			return nil, fmt.Errorf("scan contact link: %w", err)
		}
		link.note = nullString(note)
		stored = append(stored, link)
		if _, found := targets[link.contactID]; found {
			counterpartIDs = append(counterpartIDs, link.relatedContactID)
		}
		if _, found := targets[link.relatedContactID]; found {
			counterpartIDs = append(counterpartIDs, link.contactID)
		}
	}
	if err := rows.Err(); err != nil {
		_ = rows.Close()
		return nil, fmt.Errorf("iterate contact links: %w", err)
	}
	if err := rows.Close(); err != nil {
		return nil, fmt.Errorf("close contact link rows: %w", err)
	}

	counterparts, err := NewContactRepo(repository.database).findByIDs(ctx, counterpartIDs)
	if err != nil {
		return nil, err
	}
	for _, link := range stored {
		if _, found := targets[link.contactID]; found {
			counterpart, exists := counterparts[link.relatedContactID]
			if !exists {
				return nil, fmt.Errorf("contact link %d references missing contact c%d", link.id, link.relatedContactID)
			}
			linksByContact[link.contactID] = append(
				linksByContact[link.contactID],
				model.ContextLink{
					Direction: "outgoing",
					Type:      link.linkType,
					Note:      link.note,
					Contact:   counterpart,
				},
			)
		}
		if _, found := targets[link.relatedContactID]; found {
			counterpart, exists := counterparts[link.contactID]
			if !exists {
				return nil, fmt.Errorf("contact link %d references missing contact c%d", link.id, link.contactID)
			}
			linksByContact[link.relatedContactID] = append(
				linksByContact[link.relatedContactID],
				model.ContextLink{
					Direction: "incoming",
					Type:      link.linkType,
					Note:      link.note,
					Contact:   counterpart,
				},
			)
		}
	}

	return linksByContact, nil
}
