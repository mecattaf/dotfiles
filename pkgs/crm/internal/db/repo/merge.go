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

// Merge absorbs loser into winner in one transaction and returns the
// committed surviving contact with its links assembled.
func (repository *ContactRepo) Merge(
	ctx context.Context,
	winnerID int64,
	loserID int64,
) (*model.Contact, error) {
	if winnerID <= 0 || loserID <= 0 {
		return nil, model.NewExitError(model.ErrValidation, "contact ids must be positive")
	}
	if winnerID == loserID {
		return nil, model.NewExitError(
			model.ErrValidation,
			"cannot merge contact c%d into itself",
			winnerID,
		)
	}

	transaction, err := repository.database.BeginTx(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("begin contact merge: %w", err)
	}
	defer func() {
		_ = transaction.Rollback()
	}()

	winner, err := contactMergeRecord(ctx, transaction, winnerID)
	if err != nil {
		return nil, err
	}
	loser, err := contactMergeRecord(ctx, transaction, loserID)
	if err != nil {
		return nil, err
	}
	now := time.Now().UTC().Format(time.RFC3339)

	// Step 1: the live email index is partial on archived_at. Archive the
	// loser's unique presence before the winner can inherit its email, while
	// preserving the absorbed row for id-rung reads and reversal.
	if err := execMergeStatement(
		ctx,
		transaction,
		"archive contact loser unique presence",
		`UPDATE contacts
		 SET archived_at = COALESCE(archived_at, ?), updated_at = ?
		 WHERE id = ?`,
		now,
		now,
		loserID,
	); err != nil {
		return nil, err
	}

	// Steps 2 and 3: nullable scalars are winner-first; provenance is the
	// deliberate exception and always accumulates winner then loser.
	if err := execMergeStatement(
		ctx,
		transaction,
		"coalesce contact survivor",
		`UPDATE contacts SET
			org_id = ?, job_title = ?, email = ?, phone = ?, linkedin = ?,
			location = ?, context = ?, relationship_hint = ?,
			provenance_sources = ?, provenance_details = ?, updated_at = ?
		 WHERE id = ?`,
		optionalInt64Argument(coalesceInt64(winner.OrgID, loser.OrgID)),
		optionalStringArgument(coalesceString(winner.JobTitle, loser.JobTitle)),
		optionalStringArgument(coalesceString(winner.Email, loser.Email)),
		optionalStringArgument(coalesceString(winner.Phone, loser.Phone)),
		optionalStringArgument(coalesceString(winner.LinkedIn, loser.LinkedIn)),
		optionalStringArgument(coalesceString(winner.Location, loser.Location)),
		optionalStringArgument(coalesceString(winner.Context, loser.Context)),
		optionalStringArgument(coalesceString(winner.RelationshipHint, loser.RelationshipHint)),
		optionalStringArgument(concatenateProvenance(winner.ProvenanceSources, loser.ProvenanceSources)),
		optionalStringArgument(concatenateProvenance(winner.ProvenanceDetails, loser.ProvenanceDetails)),
		now,
		winnerID,
	); err != nil {
		return nil, err
	}

	// Step 4a: junction rows use insert-or-ignore before loser rows are
	// removed so an interaction already containing both contacts collapses.
	if err := execMergeStatement(
		ctx,
		transaction,
		"copy contact interaction participants",
		`INSERT OR IGNORE INTO interaction_people (interaction_id, contact_id)
		 SELECT interaction_id, ? FROM interaction_people WHERE contact_id = ?`,
		winnerID,
		loserID,
	); err != nil {
		return nil, err
	}
	if err := execMergeStatement(
		ctx,
		transaction,
		"delete absorbed contact interaction participants",
		"DELETE FROM interaction_people WHERE contact_id = ?",
		loserID,
	); err != nil {
		return nil, err
	}
	if err := execMergeStatement(
		ctx,
		transaction,
		"repoint contact deals",
		"UPDATE deals SET contact_id = ? WHERE contact_id = ?",
		winnerID,
		loserID,
	); err != nil {
		return nil, err
	}

	// Step 4b: links between winner and loser cannot be repointed without
	// violating the self-link CHECK. Remove them first, then let OR IGNORE
	// collapse matching third-party links before deleting ignored leftovers.
	if err := execMergeStatement(
		ctx,
		transaction,
		"delete winner-loser contact links",
		`DELETE FROM contact_links
		 WHERE (contact_id = ? AND related_contact_id = ?)
		    OR (contact_id = ? AND related_contact_id = ?)`,
		winnerID,
		loserID,
		loserID,
		winnerID,
	); err != nil {
		return nil, err
	}
	if err := execMergeStatement(
		ctx,
		transaction,
		"repoint contact link origins",
		"UPDATE OR IGNORE contact_links SET contact_id = ? WHERE contact_id = ?",
		winnerID,
		loserID,
	); err != nil {
		return nil, err
	}
	if err := execMergeStatement(
		ctx,
		transaction,
		"repoint contact link targets",
		"UPDATE OR IGNORE contact_links SET related_contact_id = ? WHERE related_contact_id = ?",
		winnerID,
		loserID,
	); err != nil {
		return nil, err
	}
	if err := execMergeStatement(
		ctx,
		transaction,
		"delete absorbed contact link leftovers",
		"DELETE FROM contact_links WHERE contact_id = ? OR related_contact_id = ?",
		loserID,
		loserID,
	); err != nil {
		return nil, err
	}

	// Step 5: step 1 deliberately established the final soft-archive state
	// early. Verify that invariant before committing the entire graph rewrite.
	if err := verifyMergeLoserArchived(ctx, transaction, "contacts", "contact", "c", loserID); err != nil {
		return nil, err
	}
	if err := transaction.Commit(); err != nil {
		return nil, fmt.Errorf("commit contact merge: %w", err)
	}

	// Step 6 happens outside the transaction: the transaction owns the only
	// pooled connection until commit under SetMaxOpenConns(1).
	return repository.FindByID(ctx, winnerID)
}

// Merge absorbs loser into winner in one transaction and returns the
// committed surviving organization.
func (repository *OrgRepo) Merge(
	ctx context.Context,
	winnerID int64,
	loserID int64,
) (*model.Org, error) {
	if winnerID <= 0 || loserID <= 0 {
		return nil, model.NewExitError(model.ErrValidation, "organization ids must be positive")
	}
	if winnerID == loserID {
		return nil, model.NewExitError(
			model.ErrValidation,
			"cannot merge org o%d into itself",
			winnerID,
		)
	}

	transaction, err := repository.database.BeginTx(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("begin organization merge: %w", err)
	}
	defer func() {
		_ = transaction.Rollback()
	}()

	winner, err := orgMergeRecord(ctx, transaction, winnerID)
	if err != nil {
		return nil, err
	}
	loser, err := orgMergeRecord(ctx, transaction, loserID)
	if err != nil {
		return nil, err
	}
	now := time.Now().UTC().Format(time.RFC3339)

	// Step 1: the live name_norm index is partial on archived_at, so the
	// loser's canonical name remains intact while its unique presence is freed.
	if err := execMergeStatement(
		ctx,
		transaction,
		"archive organization loser unique presence",
		`UPDATE orgs
		 SET archived_at = COALESCE(archived_at, ?), updated_at = ?
		 WHERE id = ?`,
		now,
		now,
		loserID,
	); err != nil {
		return nil, err
	}

	// Steps 2 and 3: scalar values prefer the winner, while both provenance
	// histories survive in winner-then-loser order.
	if err := execMergeStatement(
		ctx,
		transaction,
		"coalesce organization survivor",
		`UPDATE orgs SET
			category = ?, website = ?, linkedin = ?, location = ?, focus = ?,
			context = ?, relationship_hint = ?, provenance_sources = ?,
			provenance_details = ?, updated_at = ?
		 WHERE id = ?`,
		optionalStringArgument(coalesceString(winner.Category, loser.Category)),
		optionalStringArgument(coalesceString(winner.Website, loser.Website)),
		optionalStringArgument(coalesceString(winner.LinkedIn, loser.LinkedIn)),
		optionalStringArgument(coalesceString(winner.Location, loser.Location)),
		optionalStringArgument(coalesceString(winner.Focus, loser.Focus)),
		optionalStringArgument(coalesceString(winner.Context, loser.Context)),
		optionalStringArgument(coalesceString(winner.RelationshipHint, loser.RelationshipHint)),
		optionalStringArgument(concatenateProvenance(winner.ProvenanceSources, loser.ProvenanceSources)),
		optionalStringArgument(concatenateProvenance(winner.ProvenanceDetails, loser.ProvenanceDetails)),
		now,
		winnerID,
	); err != nil {
		return nil, err
	}

	// Step 4: every scalar organization reference moves to the survivor.
	for _, step := range []struct {
		label string
		query string
	}{
		{label: "repoint organization contacts", query: "UPDATE contacts SET org_id = ? WHERE org_id = ?"},
		{label: "repoint organization interactions", query: "UPDATE interactions SET org_id = ? WHERE org_id = ?"},
		{label: "repoint organization deals", query: "UPDATE deals SET org_id = ? WHERE org_id = ?"},
	} {
		if err := execMergeStatement(
			ctx,
			transaction,
			step.label,
			step.query,
			winnerID,
			loserID,
		); err != nil {
			return nil, err
		}
	}

	// Step 5 is already established by step 1; verify before committing.
	if err := verifyMergeLoserArchived(ctx, transaction, "orgs", "organization", "o", loserID); err != nil {
		return nil, err
	}
	if err := transaction.Commit(); err != nil {
		return nil, fmt.Errorf("commit organization merge: %w", err)
	}

	// Step 6: re-read only after commit to avoid the one-connection deadlock.
	return repository.FindByID(ctx, winnerID)
}

func contactMergeRecord(
	ctx context.Context,
	transaction *sql.Tx,
	id int64,
) (*model.Contact, error) {
	contact, err := scanContact(transaction.QueryRowContext(
		ctx,
		"SELECT "+contactColumns+" FROM contacts WHERE id = ?",
		id,
	))
	if errors.Is(err, sql.ErrNoRows) {
		return nil, model.NewExitError(model.ErrNotFound, "contact c%d not found", id)
	}
	if err != nil {
		return nil, fmt.Errorf("load contact c%d for merge: %w", id, err)
	}

	return contact, nil
}

func orgMergeRecord(
	ctx context.Context,
	transaction *sql.Tx,
	id int64,
) (*model.Org, error) {
	organization, err := scanOrg(transaction.QueryRowContext(
		ctx,
		"SELECT "+orgColumns+" FROM orgs WHERE id = ?",
		id,
	))
	if errors.Is(err, sql.ErrNoRows) {
		return nil, model.NewExitError(model.ErrNotFound, "organization o%d not found", id)
	}
	if err != nil {
		return nil, fmt.Errorf("load organization o%d for merge: %w", id, err)
	}

	return organization, nil
}

func coalesceString(winner, loser *string) *string {
	if winner != nil {
		return winner
	}

	return loser
}

func coalesceInt64(winner, loser *int64) *int64 {
	if winner != nil {
		return winner
	}

	return loser
}

func concatenateProvenance(winner, loser *string) *string {
	values := make([]string, 0, 2)
	for _, value := range []*string{winner, loser} {
		if value != nil && *value != "" {
			values = append(values, *value)
		}
	}
	if len(values) == 0 {
		return nil
	}
	combined := strings.Join(values, " || ")

	return &combined
}

func execMergeStatement(
	ctx context.Context,
	transaction *sql.Tx,
	label string,
	query string,
	arguments ...any,
) error {
	if _, err := transaction.ExecContext(ctx, query, arguments...); err != nil {
		return fmt.Errorf("%s: %w", label, err)
	}

	return nil
}

func verifyMergeLoserArchived(
	ctx context.Context,
	transaction *sql.Tx,
	table string,
	noun string,
	prefix string,
	id int64,
) error {
	var archivedAt sql.NullString
	query := fmt.Sprintf("SELECT archived_at FROM %s WHERE id = ?", table)
	if err := transaction.QueryRowContext(ctx, query, id).Scan(&archivedAt); err != nil {
		return fmt.Errorf("verify merged %s %s%d archive state: %w", noun, prefix, id, err)
	}
	if !archivedAt.Valid {
		return fmt.Errorf("verify merged %s %s%d archive state: archived_at is null", noun, prefix, id)
	}

	return nil
}
