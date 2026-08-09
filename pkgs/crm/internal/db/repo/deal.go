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

const dealColumns = `d.id, d.title, d.title_norm, d.org_id, d.contact_id,
d.pipeline_id, p.name, d.stage_id, s.name, d.status, d.outcome_reason,
d.closed_at, d.stage_changed_at,
CAST(julianday('now', 'utc') - julianday(d.stage_changed_at, 'utc') AS INTEGER),
s.rot_days, d.created_at, d.updated_at, d.archived_at`

const dealFrom = `deals d
JOIN pipelines p ON p.id = d.pipeline_id
JOIN stages s ON s.id = d.stage_id`

const rottingDealPredicate = `d.status = 'open' AND s.rot_days IS NOT NULL
AND (julianday('now', 'utc') - julianday(d.stage_changed_at, 'utc')) > s.rot_days`

// DealRepo owns deal persistence, real-columned stage history, and the
// merged deal timeline.
type DealRepo struct {
	database *sql.DB
}

// NewDealRepo constructs a deal repository.
func NewDealRepo(database *sql.DB) *DealRepo {
	return &DealRepo{database: database}
}

func scanDeal(row scanner) (*model.Deal, error) {
	var deal model.Deal
	var orgID sql.NullInt64
	var contactID sql.NullInt64
	var outcomeReason sql.NullString
	var closedAt sql.NullString
	var rotDays sql.NullInt64
	var archivedAt sql.NullString
	if err := row.Scan(
		&deal.ID,
		&deal.Title,
		&deal.TitleNorm,
		&orgID,
		&contactID,
		&deal.PipelineID,
		&deal.Pipeline,
		&deal.StageID,
		&deal.Stage,
		&deal.Status,
		&outcomeReason,
		&closedAt,
		&deal.StageChangedAt,
		&deal.DaysInStage,
		&rotDays,
		&deal.CreatedAt,
		&deal.UpdatedAt,
		&archivedAt,
	); err != nil {
		return nil, err
	}

	deal.Ref = fmt.Sprintf("d%d", deal.ID)
	deal.OrgID = nullInt64(orgID)
	deal.ContactID = nullInt64(contactID)
	deal.OutcomeReason = nullString(outcomeReason)
	deal.ClosedAt = nullString(closedAt)
	if rotDays.Valid {
		value := int(rotDays.Int64)
		deal.RotDays = &value
	}
	deal.ArchivedAt = nullString(archivedAt)

	return &deal, nil
}

// Create inserts a deal and its opening stage move atomically. All refs are
// resolved before this method is called; the stage/pipeline relationship is
// revalidated before the transaction as defense in depth.
func (repository *DealRepo) Create(
	ctx context.Context,
	input model.CreateDealInput,
) (*model.Deal, error) {
	title := strings.TrimSpace(input.Title)
	titleNorm, ok := model.TryNormalizeName(title)
	if !ok {
		return nil, model.NewExitError(model.ErrValidation, "deal title must not be empty")
	}
	if input.PipelineID <= 0 || input.StageID <= 0 {
		return nil, model.NewExitError(
			model.ErrValidation,
			"deal pipeline and stage ids must be positive",
		)
	}
	if input.OrgID == nil && input.ContactID == nil {
		return nil, model.NewExitError(
			model.ErrValidation,
			"deal add requires at least one of --org or --contact",
		)
	}
	if err := repository.validateLiveStage(ctx, input.PipelineID, input.StageID); err != nil {
		return nil, err
	}

	now := time.Now().UTC().Format(time.RFC3339)
	transaction, err := repository.database.BeginTx(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("begin deal create: %w", err)
	}
	defer func() {
		_ = transaction.Rollback()
	}()

	result, err := transaction.ExecContext(
		ctx,
		`INSERT INTO deals (
            title, title_norm, org_id, contact_id, pipeline_id, stage_id,
            status, stage_changed_at, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, 'open', ?, ?, ?)`,
		title,
		titleNorm,
		optionalInt64Argument(input.OrgID),
		optionalInt64Argument(input.ContactID),
		input.PipelineID,
		input.StageID,
		now,
		now,
		now,
	)
	if err != nil {
		return nil, fmt.Errorf("insert deal: %w", err)
	}
	id, err := result.LastInsertId()
	if err != nil {
		return nil, fmt.Errorf("read inserted deal id: %w", err)
	}
	if _, err := transaction.ExecContext(
		ctx,
		`INSERT INTO stage_moves (deal_id, from_stage_id, to_stage_id, moved_at, note)
         VALUES (?, NULL, ?, ?, NULL)`,
		id,
		input.StageID,
		now,
	); err != nil {
		return nil, fmt.Errorf("insert opening stage move for deal d%d: %w", id, err)
	}
	if err := transaction.Commit(); err != nil {
		return nil, fmt.Errorf("commit deal create: %w", err)
	}

	// Re-read only after commit: the configured pool has one connection.
	return repository.FindByID(ctx, id)
}

// FindByID returns one deal by numeric id, including archived rows.
func (repository *DealRepo) FindByID(ctx context.Context, id int64) (*model.Deal, error) {
	row := repository.database.QueryRowContext(
		ctx,
		"SELECT "+dealColumns+" FROM "+dealFrom+" WHERE d.id = ?",
		id,
	)
	deal, err := scanDeal(row)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, model.NewExitError(model.ErrNotFound, "deal d%d not found", id)
	}
	if err != nil {
		return nil, fmt.Errorf("find deal d%d: %w", id, err)
	}

	return deal, nil
}

// DetailByID returns one deal with its chronological stage history and its
// newest-first timeline of stage moves interleaved with linked interactions.
func (repository *DealRepo) DetailByID(
	ctx context.Context,
	id int64,
) (*model.DealDetail, error) {
	deal, err := repository.FindByID(ctx, id)
	if err != nil {
		return nil, err
	}
	moves, err := repository.loadStageMoves(ctx, id)
	if err != nil {
		return nil, err
	}
	interactions, err := repository.loadInteractions(ctx, id)
	if err != nil {
		return nil, err
	}

	timeline := make([]model.DealTimelineEntry, 0, len(moves)+len(interactions))
	for index := range moves {
		timeline = append(timeline, model.DealTimelineEntry{
			Type:       "stage_move",
			OccurredAt: moves[index].MovedAt,
			StageMove:  &moves[index],
		})
	}
	for index := range interactions {
		timeline = append(timeline, model.DealTimelineEntry{
			Type:        "interaction",
			OccurredAt:  interactions[index].OccurredOn,
			Interaction: &interactions[index],
		})
	}
	sort.SliceStable(timeline, func(left, right int) bool {
		if timeline[left].OccurredAt != timeline[right].OccurredAt {
			return timeline[left].OccurredAt > timeline[right].OccurredAt
		}
		if timeline[left].Type != timeline[right].Type {
			return timeline[left].Type < timeline[right].Type
		}

		return timelineEntryID(timeline[left]) > timelineEntryID(timeline[right])
	})

	return &model.DealDetail{
		Deal:       *deal,
		StageMoves: moves,
		Timeline:   timeline,
	}, nil
}

func timelineEntryID(entry model.DealTimelineEntry) int64 {
	if entry.StageMove != nil {
		return entry.StageMove.ID
	}
	if entry.Interaction != nil {
		return entry.Interaction.ID
	}

	return 0
}

// List returns deals in deterministic title order, except rot listings which
// are ordered by exact overdue duration (most overdue first).
func (repository *DealRepo) List(
	ctx context.Context,
	filters model.DealFilters,
) ([]model.Deal, error) {
	if filters.Limit < 0 {
		return nil, model.NewExitError(model.ErrValidation, "limit must not be negative")
	}
	if filters.StageID != nil && filters.PipelineID == nil {
		return nil, model.NewExitError(
			model.ErrValidation,
			"--stage requires --pipeline because stage names are pipeline-scoped",
		)
	}
	if filters.Status != nil && !model.ValidDealStatus(*filters.Status) {
		return nil, model.NewExitError(
			model.ErrValidation,
			"invalid deal status %q (accepted: %s)",
			*filters.Status,
			strings.Join(model.DealStatuses, ","),
		)
	}

	query := "SELECT " + dealColumns + " FROM " + dealFrom + " WHERE 1 = 1"
	arguments := make([]any, 0, 5)
	if !filters.All {
		query += " AND d.archived_at IS NULL"
	}
	if filters.PipelineID != nil {
		query += " AND d.pipeline_id = ?"
		arguments = append(arguments, *filters.PipelineID)
	}
	if filters.StageID != nil {
		query += " AND d.stage_id = ?"
		arguments = append(arguments, *filters.StageID)
	}
	if filters.Status != nil {
		query += " AND d.status = ?"
		arguments = append(arguments, *filters.Status)
	}
	if filters.Rotting {
		query += " AND " + rottingDealPredicate
		query += ` ORDER BY
            ((julianday('now', 'utc') - julianday(d.stage_changed_at, 'utc')) - s.rot_days) DESC,
            d.id ASC`
	} else {
		query += " ORDER BY d.title_norm ASC, d.id ASC"
	}
	if filters.Limit > 0 {
		query += " LIMIT ?"
		arguments = append(arguments, filters.Limit)
	}

	rows, err := repository.database.QueryContext(ctx, query, arguments...)
	if err != nil {
		return nil, fmt.Errorf("list deals: %w", err)
	}
	deals := make([]model.Deal, 0)
	for rows.Next() {
		deal, scanErr := scanDeal(rows)
		if scanErr != nil {
			_ = rows.Close()
			return nil, fmt.Errorf("scan deal: %w", scanErr)
		}
		deals = append(deals, *deal)
	}
	if err := rows.Err(); err != nil {
		_ = rows.Close()
		return nil, fmt.Errorf("iterate deals: %w", err)
	}
	if err := rows.Close(); err != nil {
		return nil, fmt.Errorf("close deals: %w", err)
	}

	return deals, nil
}

// Update applies a true PATCH without exposing stage or status. It preserves
// updated_at when every supplied value normalizes to the current value.
func (repository *DealRepo) Update(
	ctx context.Context,
	id int64,
	input model.UpdateDealInput,
) (*model.Deal, error) {
	current, err := repository.FindByID(ctx, id)
	if err != nil {
		return nil, err
	}

	setClauses := make([]string, 0, 4)
	arguments := make([]any, 0, 5)
	if input.Title != nil {
		title := strings.TrimSpace(*input.Title)
		titleNorm, ok := model.TryNormalizeName(title)
		if !ok {
			return nil, model.NewExitError(model.ErrValidation, "deal title must not be empty")
		}
		if title != current.Title || titleNorm != current.TitleNorm {
			setClauses = append(setClauses, "title = ?", "title_norm = ?")
			arguments = append(arguments, title, titleNorm)
		}
	}

	nextOrgID := current.OrgID
	if input.OrgID != nil {
		nextOrgID = *input.OrgID
		if !equalOptionalInt64s(current.OrgID, nextOrgID) {
			setClauses = append(setClauses, "org_id = ?")
			arguments = append(arguments, optionalInt64Argument(nextOrgID))
		}
	}
	nextContactID := current.ContactID
	if input.ContactID != nil {
		nextContactID = *input.ContactID
		if !equalOptionalInt64s(current.ContactID, nextContactID) {
			setClauses = append(setClauses, "contact_id = ?")
			arguments = append(arguments, optionalInt64Argument(nextContactID))
		}
	}
	if nextOrgID == nil && nextContactID == nil {
		return nil, model.NewExitError(
			model.ErrConflict,
			"deal d%d must keep at least one of org or contact",
			id,
		)
	}
	if len(setClauses) == 0 {
		return current, nil
	}

	setClauses = append(setClauses, "updated_at = ?")
	arguments = append(arguments, time.Now().UTC().Format(time.RFC3339), id)
	result, err := repository.database.ExecContext(
		ctx,
		"UPDATE deals SET "+strings.Join(setClauses, ", ")+" WHERE id = ?",
		arguments...,
	)
	if err != nil {
		return nil, fmt.Errorf("update deal d%d: %w", id, err)
	}
	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return nil, fmt.Errorf("read updated deal row count: %w", err)
	}
	if rowsAffected == 0 {
		return nil, model.NewExitError(model.ErrNotFound, "deal d%d not found", id)
	}

	return repository.FindByID(ctx, id)
}

// Move changes stage_id and stage_changed_at and records the corresponding
// stage_moves row in the same transaction.
func (repository *DealRepo) Move(
	ctx context.Context,
	id int64,
	targetStageID int64,
	noteInput string,
) (*model.Deal, error) {
	current, err := repository.FindByID(ctx, id)
	if err != nil {
		return nil, err
	}
	if err := repository.validateLiveStage(ctx, current.PipelineID, targetStageID); err != nil {
		return nil, err
	}
	target, err := NewStageRepo(repository.database).FindByID(ctx, targetStageID)
	if err != nil {
		return nil, err
	}
	if current.StageID == targetStageID {
		return nil, model.NewExitError(
			model.ErrConflict,
			"deal %s already in stage %s",
			current.Reference(),
			current.Stage,
		)
	}

	now := time.Now().UTC().Format(time.RFC3339)
	note := trimmedOptional(noteInput)
	transaction, err := repository.database.BeginTx(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("begin stage move for deal %s: %w", current.Reference(), err)
	}
	defer func() {
		_ = transaction.Rollback()
	}()

	result, err := transaction.ExecContext(
		ctx,
		`UPDATE deals
         SET stage_id = ?, stage_changed_at = ?, updated_at = ?
         WHERE id = ?`,
		target.ID,
		now,
		now,
		id,
	)
	if err != nil {
		return nil, fmt.Errorf("move deal %s to stage %s: %w", current.Reference(), target.Reference(), err)
	}
	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return nil, fmt.Errorf("read moved deal row count: %w", err)
	}
	if rowsAffected == 0 {
		return nil, model.NewExitError(model.ErrNotFound, "deal d%d not found", id)
	}
	if _, err := transaction.ExecContext(
		ctx,
		`INSERT INTO stage_moves (
            deal_id, from_stage_id, to_stage_id, moved_at, note
        ) VALUES (?, ?, ?, ?, ?)`,
		id,
		current.StageID,
		target.ID,
		now,
		optionalStringArgument(note),
	); err != nil {
		return nil, fmt.Errorf("record stage move for deal %s: %w", current.Reference(), err)
	}
	if err := transaction.Commit(); err != nil {
		return nil, fmt.Errorf("commit stage move for deal %s: %w", current.Reference(), err)
	}

	return repository.FindByID(ctx, id)
}

// Close marks a deal won or lost, overwriting the last outcome reason and
// setting closed_at to the same UTC instant as updated_at.
func (repository *DealRepo) Close(
	ctx context.Context,
	id int64,
	status string,
	reasonInput string,
) (*model.Deal, error) {
	if status != "won" && status != "lost" {
		return nil, model.NewExitError(
			model.ErrValidation,
			"deal close status must be won or lost",
		)
	}
	if _, err := repository.FindByID(ctx, id); err != nil {
		return nil, err
	}

	now := time.Now().UTC().Format(time.RFC3339)
	reason := trimmedOptional(reasonInput)
	result, err := repository.database.ExecContext(
		ctx,
		`UPDATE deals
         SET status = ?, outcome_reason = ?, closed_at = ?, updated_at = ?
         WHERE id = ?`,
		status,
		optionalStringArgument(reason),
		now,
		now,
		id,
	)
	if err != nil {
		return nil, fmt.Errorf("mark deal d%d %s: %w", id, status, err)
	}
	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return nil, fmt.Errorf("read closed deal row count: %w", err)
	}
	if rowsAffected == 0 {
		return nil, model.NewExitError(model.ErrNotFound, "deal d%d not found", id)
	}

	return repository.FindByID(ctx, id)
}

// Reopen returns a closed deal to open and clears closed_at while preserving
// outcome_reason as the record of the last outcome.
func (repository *DealRepo) Reopen(ctx context.Context, id int64) (*model.Deal, error) {
	current, err := repository.FindByID(ctx, id)
	if err != nil {
		return nil, err
	}
	if current.Status == "open" {
		return nil, model.NewExitError(
			model.ErrConflict,
			"deal %s is already open",
			current.Reference(),
		)
	}

	result, err := repository.database.ExecContext(
		ctx,
		`UPDATE deals
         SET status = 'open', closed_at = NULL, updated_at = ?
         WHERE id = ?`,
		time.Now().UTC().Format(time.RFC3339),
		id,
	)
	if err != nil {
		return nil, fmt.Errorf("reopen deal d%d: %w", id, err)
	}
	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return nil, fmt.Errorf("read reopened deal row count: %w", err)
	}
	if rowsAffected == 0 {
		return nil, model.NewExitError(model.ErrNotFound, "deal d%d not found", id)
	}

	return repository.FindByID(ctx, id)
}

func (repository *DealRepo) validateLiveStage(
	ctx context.Context,
	pipelineID int64,
	stageID int64,
) error {
	var stageName string
	err := repository.database.QueryRowContext(
		ctx,
		`SELECT s.name
         FROM stages s
         JOIN pipelines p ON p.id = s.pipeline_id
         WHERE s.id = ? AND s.pipeline_id = ?
           AND s.archived_at IS NULL AND p.archived_at IS NULL`,
		stageID,
		pipelineID,
	).Scan(&stageName)
	if errors.Is(err, sql.ErrNoRows) {
		return model.NewExitError(
			model.ErrConflict,
			"stage s%d is not a live stage in pipeline p%d",
			stageID,
			pipelineID,
		)
	}
	if err != nil {
		return fmt.Errorf("validate stage s%d in pipeline p%d: %w", stageID, pipelineID, err)
	}

	return nil
}

func (repository *DealRepo) loadStageMoves(
	ctx context.Context,
	dealID int64,
) ([]model.StageMove, error) {
	rows, err := repository.database.QueryContext(
		ctx,
		`SELECT sm.id, sm.deal_id, sm.from_stage_id, from_stage.name,
                sm.to_stage_id, to_stage.name, sm.moved_at, sm.note
         FROM stage_moves sm
         LEFT JOIN stages from_stage ON from_stage.id = sm.from_stage_id
         JOIN stages to_stage ON to_stage.id = sm.to_stage_id
         WHERE sm.deal_id = ?
         ORDER BY sm.moved_at ASC, sm.id ASC`,
		dealID,
	)
	if err != nil {
		return nil, fmt.Errorf("load stage history for deal d%d: %w", dealID, err)
	}
	moves := make([]model.StageMove, 0)
	for rows.Next() {
		var move model.StageMove
		var fromStageID sql.NullInt64
		var fromStageName sql.NullString
		var note sql.NullString
		if err := rows.Scan(
			&move.ID,
			&move.DealID,
			&fromStageID,
			&fromStageName,
			&move.ToStageID,
			&move.ToStageName,
			&move.MovedAt,
			&note,
		); err != nil {
			_ = rows.Close()
			return nil, fmt.Errorf("scan stage history for deal d%d: %w", dealID, err)
		}
		move.FromStageID = nullInt64(fromStageID)
		move.FromStageName = nullString(fromStageName)
		move.Note = nullString(note)
		moves = append(moves, move)
	}
	if err := rows.Err(); err != nil {
		_ = rows.Close()
		return nil, fmt.Errorf("iterate stage history for deal d%d: %w", dealID, err)
	}
	if err := rows.Close(); err != nil {
		return nil, fmt.Errorf("close stage history for deal d%d: %w", dealID, err)
	}

	return moves, nil
}

func (repository *DealRepo) loadInteractions(
	ctx context.Context,
	dealID int64,
) ([]model.Interaction, error) {
	rows, err := repository.database.QueryContext(
		ctx,
		"SELECT "+interactionColumns+` FROM interactions i
         WHERE i.deal_id = ? AND i.archived_at IS NULL
         ORDER BY i.occurred_on DESC, i.id DESC`,
		dealID,
	)
	if err != nil {
		return nil, fmt.Errorf("load interactions for deal d%d: %w", dealID, err)
	}
	interactions := make([]model.Interaction, 0)
	for rows.Next() {
		interaction, scanErr := scanInteraction(rows)
		if scanErr != nil {
			_ = rows.Close()
			return nil, fmt.Errorf("scan interaction for deal d%d: %w", dealID, scanErr)
		}
		interactions = append(interactions, *interaction)
	}
	if err := rows.Err(); err != nil {
		_ = rows.Close()
		return nil, fmt.Errorf("iterate interactions for deal d%d: %w", dealID, err)
	}
	if err := rows.Close(); err != nil {
		return nil, fmt.Errorf("close interactions for deal d%d: %w", dealID, err)
	}

	// Drain and close before the participant batch query: the DB pool has one
	// connection and querying while rows are open would self-deadlock.
	if err := NewInteractionRepo(repository.database).loadContactIDs(ctx, interactions); err != nil {
		return nil, err
	}

	return interactions, nil
}
