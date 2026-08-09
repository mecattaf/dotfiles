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

type lifecycleTarget struct {
	table    string
	noun     string
	prefix   string
	blockers []deleteBlocker
}

type deleteBlocker struct {
	query    string
	singular string
	plural   string
	twoIDs   bool
}

var (
	orgLifecycle = lifecycleTarget{
		table:  "orgs",
		noun:   "org",
		prefix: "o",
		blockers: []deleteBlocker{
			{
				query:    "SELECT COUNT(*) FROM contacts WHERE org_id = ?",
				singular: "contact",
				plural:   "contacts",
			},
			{
				query:    "SELECT COUNT(*) FROM deals WHERE org_id = ?",
				singular: "deal",
				plural:   "deals",
			},
			{
				query:    "SELECT COUNT(*) FROM interactions WHERE org_id = ?",
				singular: "interaction",
				plural:   "interactions",
			},
		},
	}
	contactLifecycle = lifecycleTarget{
		table:  "contacts",
		noun:   "contact",
		prefix: "c",
		blockers: []deleteBlocker{
			{
				query:    "SELECT COUNT(*) FROM interaction_people WHERE contact_id = ?",
				singular: "interaction",
				plural:   "interactions",
			},
			{
				query:    "SELECT COUNT(*) FROM deals WHERE contact_id = ?",
				singular: "deal",
				plural:   "deals",
			},
			{
				query: "SELECT COUNT(*) FROM contact_links " +
					"WHERE contact_id = ? OR related_contact_id = ?",
				singular: "contact link",
				plural:   "contact links",
				twoIDs:   true,
			},
		},
	}
	interactionLifecycle = lifecycleTarget{
		table:  "interactions",
		noun:   "interaction",
		prefix: "i",
	}
	pipelineLifecycle = lifecycleTarget{
		table:  "pipelines",
		noun:   "pipeline",
		prefix: "p",
		blockers: []deleteBlocker{
			{
				query:    "SELECT COUNT(*) FROM stages WHERE pipeline_id = ?",
				singular: "stage",
				plural:   "stages",
			},
			{
				query:    "SELECT COUNT(*) FROM deals WHERE pipeline_id = ?",
				singular: "deal",
				plural:   "deals",
			},
		},
	}
	stageLifecycle = lifecycleTarget{
		table:  "stages",
		noun:   "stage",
		prefix: "s",
		blockers: []deleteBlocker{
			{
				query:    "SELECT COUNT(*) FROM deals WHERE stage_id = ?",
				singular: "deal",
				plural:   "deals",
			},
			{
				query: "SELECT COUNT(*) FROM stage_moves " +
					"WHERE from_stage_id = ? OR to_stage_id = ?",
				singular: "stage move",
				plural:   "stage moves",
				twoIDs:   true,
			},
		},
	}
	dealLifecycle = lifecycleTarget{
		table:  "deals",
		noun:   "deal",
		prefix: "d",
		blockers: []deleteBlocker{
			{
				query:    "SELECT COUNT(*) FROM interactions WHERE deal_id = ?",
				singular: "interaction",
				plural:   "interactions",
			},
		},
	}
)

// setArchiveState is the one persistence path for soft lifecycle changes.
// The target values above are fixed package constants; table names are never
// derived from user input. A zero-row UPDATE is followed by a state read so a
// retry can distinguish an already-completed transition from a missing row.
func setArchiveState(
	ctx context.Context,
	database *sql.DB,
	target lifecycleTarget,
	id int64,
	archive bool,
) error {
	verb := "archive"
	predicate := "archived_at IS NULL"
	if !archive {
		verb = "unarchive"
		predicate = "archived_at IS NOT NULL"
	}
	now := time.Now().UTC().Format(time.RFC3339)
	var archivedValue any
	if archive {
		archivedValue = now
	}

	query := fmt.Sprintf(
		"UPDATE %s SET archived_at = ?, updated_at = ? WHERE id = ? AND %s",
		target.table,
		predicate,
	)
	result, err := database.ExecContext(ctx, query, archivedValue, now, id)
	if err != nil {
		return fmt.Errorf("%s %s %s%d: %w", verb, target.noun, target.prefix, id, err)
	}
	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf(
			"read %sd %s %s%d row count: %w",
			verb,
			target.noun,
			target.prefix,
			id,
			err,
		)
	}
	if rowsAffected == 1 {
		return nil
	}
	if rowsAffected != 0 {
		return fmt.Errorf(
			"%s %s %s%d affected %d rows",
			verb,
			target.noun,
			target.prefix,
			id,
			rowsAffected,
		)
	}

	var archivedAt sql.NullString
	err = database.QueryRowContext(
		ctx,
		fmt.Sprintf("SELECT archived_at FROM %s WHERE id = ?", target.table),
		id,
	).Scan(&archivedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return model.NewExitError(
			model.ErrNotFound,
			"%s %s%d not found",
			target.noun,
			target.prefix,
			id,
		)
	}
	if err != nil {
		return fmt.Errorf(
			"inspect %s state for %s%d: %w",
			target.noun,
			target.prefix,
			id,
			err,
		)
	}
	if archive && archivedAt.Valid {
		return model.NewExitError(
			model.ErrConflict,
			"%s %s%d is already archived",
			target.noun,
			target.prefix,
			id,
		)
	}
	if !archive && !archivedAt.Valid {
		return model.NewExitError(
			model.ErrConflict,
			"%s %s%d is already unarchived",
			target.noun,
			target.prefix,
			id,
		)
	}

	return model.NewExitError(
		model.ErrConflict,
		"%s %s%d changed state concurrently — retry",
		target.noun,
		target.prefix,
		id,
	)
}

// hardDelete checks every schema-level blocker and removes exactly one row in
// the same transaction. The matrix is fixed above rather than inferred from
// driver errors so users always receive counted, actionable refusals.
func hardDelete(
	ctx context.Context,
	database *sql.DB,
	target lifecycleTarget,
	id int64,
) error {
	transaction, err := database.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin deleting %s %s%d: %w", target.noun, target.prefix, id, err)
	}
	defer func() {
		_ = transaction.Rollback()
	}()

	counts := make([]string, 0, len(target.blockers))
	for _, blocker := range target.blockers {
		arguments := []any{id}
		if blocker.twoIDs {
			arguments = append(arguments, id)
		}

		var count int64
		if err := transaction.QueryRowContext(ctx, blocker.query, arguments...).Scan(&count); err != nil {
			return fmt.Errorf(
				"count %s references for %s%d: %w",
				blocker.plural,
				target.prefix,
				id,
				err,
			)
		}
		if count == 0 {
			continue
		}

		noun := blocker.plural
		if count == 1 {
			noun = blocker.singular
		}
		counts = append(counts, fmt.Sprintf("%d %s", count, noun))
	}
	if len(counts) > 0 {
		return model.NewExitError(
			model.ErrConflict,
			"%s appears in %s — archive instead",
			target.noun,
			joinDeleteCounts(counts),
		)
	}

	result, err := transaction.ExecContext(
		ctx,
		fmt.Sprintf("DELETE FROM %s WHERE id = ?", target.table),
		id,
	)
	if err != nil {
		if strings.Contains(strings.ToLower(err.Error()), "foreign key constraint") {
			return model.NewExitError(
				model.ErrConflict,
				"%s gained a blocking reference during delete — archive instead",
				target.noun,
			)
		}

		return fmt.Errorf("delete %s %s%d: %w", target.noun, target.prefix, id, err)
	}
	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf(
			"read deleted %s %s%d row count: %w",
			target.noun,
			target.prefix,
			id,
			err,
		)
	}
	if rowsAffected == 0 {
		return model.NewExitError(
			model.ErrNotFound,
			"%s %s%d not found",
			target.noun,
			target.prefix,
			id,
		)
	}
	if rowsAffected != 1 {
		return fmt.Errorf(
			"delete %s %s%d affected %d rows",
			target.noun,
			target.prefix,
			id,
			rowsAffected,
		)
	}
	if err := transaction.Commit(); err != nil {
		return fmt.Errorf("commit deleting %s %s%d: %w", target.noun, target.prefix, id, err)
	}

	return nil
}

func joinDeleteCounts(counts []string) string {
	switch len(counts) {
	case 0:
		return ""
	case 1:
		return counts[0]
	case 2:
		return counts[0] + " and " + counts[1]
	default:
		return strings.Join(counts[:len(counts)-1], ", ") + ", and " + counts[len(counts)-1]
	}
}

// Archive marks an organization archived and returns its committed record.
func (repository *OrgRepo) Archive(ctx context.Context, id int64) (*model.Org, error) {
	if err := setArchiveState(ctx, repository.database, orgLifecycle, id, true); err != nil {
		return nil, err
	}

	return repository.FindByID(ctx, id)
}

// Unarchive restores an organization to the live set.
func (repository *OrgRepo) Unarchive(ctx context.Context, id int64) (*model.Org, error) {
	err := setArchiveState(ctx, repository.database, orgLifecycle, id, false)
	if err != nil && isUniqueConstraint(err) {
		organization, findErr := repository.FindByID(ctx, id)
		if findErr != nil {
			return nil, errors.Join(err, findErr)
		}

		return repository.translateDuplicateName(
			ctx,
			organization.Name,
			organization.NameNorm,
			err,
		)
	}
	if err != nil {
		return nil, err
	}

	return repository.FindByID(ctx, id)
}

// Archive marks a contact archived and returns its committed record.
func (repository *ContactRepo) Archive(ctx context.Context, id int64) (*model.Contact, error) {
	if err := setArchiveState(ctx, repository.database, contactLifecycle, id, true); err != nil {
		return nil, err
	}

	return repository.FindByID(ctx, id)
}

// Unarchive restores a contact to the live set.
func (repository *ContactRepo) Unarchive(ctx context.Context, id int64) (*model.Contact, error) {
	err := setArchiveState(ctx, repository.database, contactLifecycle, id, false)
	if err != nil && isUniqueConstraint(err) {
		contact, findErr := repository.findByID(ctx, id)
		if findErr != nil {
			return nil, errors.Join(err, findErr)
		}
		if contact.Email == nil {
			return nil, err
		}

		return repository.translateDuplicateEmail(ctx, *contact.Email, err)
	}
	if err != nil {
		return nil, err
	}

	return repository.FindByID(ctx, id)
}

// Archive marks an interaction archived and returns its committed record.
func (repository *InteractionRepo) Archive(
	ctx context.Context,
	id int64,
) (*model.Interaction, error) {
	if err := setArchiveState(
		ctx,
		repository.database,
		interactionLifecycle,
		id,
		true,
	); err != nil {
		return nil, err
	}

	return repository.FindByID(ctx, id)
}

// Unarchive restores an interaction to the live set.
func (repository *InteractionRepo) Unarchive(
	ctx context.Context,
	id int64,
) (*model.Interaction, error) {
	if err := setArchiveState(
		ctx,
		repository.database,
		interactionLifecycle,
		id,
		false,
	); err != nil {
		return nil, err
	}

	return repository.FindByID(ctx, id)
}

// Archive marks a pipeline archived and returns its committed record.
func (repository *PipelineRepo) Archive(
	ctx context.Context,
	id int64,
) (*model.Pipeline, error) {
	if err := setArchiveState(ctx, repository.database, pipelineLifecycle, id, true); err != nil {
		return nil, err
	}

	return repository.FindByID(ctx, id)
}

// Unarchive restores a pipeline to the live set.
func (repository *PipelineRepo) Unarchive(
	ctx context.Context,
	id int64,
) (*model.Pipeline, error) {
	err := setArchiveState(ctx, repository.database, pipelineLifecycle, id, false)
	if err != nil && isUniqueConstraint(err) {
		pipeline, findErr := repository.FindByID(ctx, id)
		if findErr != nil {
			return nil, errors.Join(err, findErr)
		}

		return repository.translateDuplicateName(
			ctx,
			pipeline.Name,
			pipeline.NameNorm,
			err,
		)
	}
	if err != nil {
		return nil, err
	}

	return repository.FindByID(ctx, id)
}

// Archive marks a stage archived and returns its committed record.
func (repository *StageRepo) Archive(ctx context.Context, id int64) (*model.Stage, error) {
	if err := setArchiveState(ctx, repository.database, stageLifecycle, id, true); err != nil {
		return nil, err
	}

	return repository.FindByID(ctx, id)
}

// Unarchive restores a stage to the live set.
func (repository *StageRepo) Unarchive(ctx context.Context, id int64) (*model.Stage, error) {
	err := setArchiveState(ctx, repository.database, stageLifecycle, id, false)
	if err != nil && isUniqueConstraint(err) {
		stage, findErr := repository.FindByID(ctx, id)
		if findErr != nil {
			return nil, errors.Join(err, findErr)
		}

		return repository.translateDuplicateName(
			ctx,
			stage.PipelineID,
			stage.Name,
			stage.NameNorm,
			err,
		)
	}
	if err != nil {
		return nil, err
	}

	return repository.FindByID(ctx, id)
}

// Archive marks a deal archived and returns its committed record.
func (repository *DealRepo) Archive(ctx context.Context, id int64) (*model.Deal, error) {
	if err := setArchiveState(ctx, repository.database, dealLifecycle, id, true); err != nil {
		return nil, err
	}

	return repository.FindByID(ctx, id)
}

// Unarchive restores a deal to the live set.
func (repository *DealRepo) Unarchive(ctx context.Context, id int64) (*model.Deal, error) {
	if err := setArchiveState(ctx, repository.database, dealLifecycle, id, false); err != nil {
		return nil, err
	}

	return repository.FindByID(ctx, id)
}

// Delete permanently removes an organization after checking every blocker.
func (repository *OrgRepo) Delete(ctx context.Context, id int64) error {
	return hardDelete(ctx, repository.database, orgLifecycle, id)
}

// Delete permanently removes a contact after checking every blocker.
func (repository *ContactRepo) Delete(ctx context.Context, id int64) error {
	return hardDelete(ctx, repository.database, contactLifecycle, id)
}

// Delete permanently removes an interaction. Its junction rows cascade.
func (repository *InteractionRepo) Delete(ctx context.Context, id int64) error {
	return hardDelete(ctx, repository.database, interactionLifecycle, id)
}

// Delete permanently removes a pipeline after checking every blocker.
func (repository *PipelineRepo) Delete(ctx context.Context, id int64) error {
	return hardDelete(ctx, repository.database, pipelineLifecycle, id)
}

// Delete permanently removes a stage after checking every blocker.
func (repository *StageRepo) Delete(ctx context.Context, id int64) error {
	return hardDelete(ctx, repository.database, stageLifecycle, id)
}

// Delete permanently removes a deal after checking interactions. Stage moves
// are owned by the deal and cascade with it.
func (repository *DealRepo) Delete(ctx context.Context, id int64) error {
	return hardDelete(ctx, repository.database, dealLifecycle, id)
}
