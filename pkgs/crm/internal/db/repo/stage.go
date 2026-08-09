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

const stageColumns = `id, pipeline_id, name, name_norm, position, rot_days,
created_at, updated_at, archived_at`

// StageRepo owns pipeline-stage persistence.
type StageRepo struct {
	database *sql.DB
}

// NewStageRepo constructs a stage repository.
func NewStageRepo(database *sql.DB) *StageRepo {
	return &StageRepo{database: database}
}

func scanStage(row scanner) (*model.Stage, error) {
	var stage model.Stage
	var rotDays sql.NullInt64
	var archivedAt sql.NullString
	if err := row.Scan(
		&stage.ID,
		&stage.PipelineID,
		&stage.Name,
		&stage.NameNorm,
		&stage.Position,
		&rotDays,
		&stage.CreatedAt,
		&stage.UpdatedAt,
		&archivedAt,
	); err != nil {
		return nil, err
	}

	stage.Ref = fmt.Sprintf("s%d", stage.ID)
	if rotDays.Valid {
		value := int(rotDays.Int64)
		stage.RotDays = &value
	}
	stage.ArchivedAt = nullString(archivedAt)

	return &stage, nil
}

// Create inserts a stage at the requested position, shifting later live
// stages in the same transaction before returning the committed record.
func (repository *StageRepo) Create(
	ctx context.Context,
	input model.CreateStageInput,
) (*model.Stage, error) {
	if input.PipelineID <= 0 {
		return nil, model.NewExitError(model.ErrValidation, "pipeline id must be positive")
	}
	if input.First && input.AfterStageID != nil {
		return nil, model.NewExitError(
			model.ErrValidation,
			"stage placement accepts only one of first or after",
		)
	}
	if input.RotDays != nil && *input.RotDays <= 0 {
		return nil, model.NewExitError(
			model.ErrValidation,
			"rot days must be a positive integer or none",
		)
	}

	name := strings.TrimSpace(input.Name)
	nameNorm, ok := model.TryNormalizeName(name)
	if !ok {
		return nil, model.NewExitError(model.ErrValidation, "stage name must not be empty")
	}

	now := time.Now().UTC().Format(time.RFC3339)
	transaction, err := repository.database.BeginTx(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("begin stage create: %w", err)
	}
	defer func() {
		_ = transaction.Rollback()
	}()

	position, err := stageInsertPosition(ctx, transaction, input)
	if err != nil {
		return nil, err
	}
	if _, err := transaction.ExecContext(
		ctx,
		`UPDATE stages
         SET position = position + 1, updated_at = ?
         WHERE pipeline_id = ? AND archived_at IS NULL AND position >= ?`,
		now,
		input.PipelineID,
		position,
	); err != nil {
		return nil, fmt.Errorf("shift stages for insertion: %w", err)
	}

	var rotDays any
	if input.RotDays != nil {
		rotDays = *input.RotDays
	}
	result, err := transaction.ExecContext(
		ctx,
		`INSERT INTO stages (
            pipeline_id, name, name_norm, position, rot_days, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?)`,
		input.PipelineID,
		name,
		nameNorm,
		position,
		rotDays,
		now,
		now,
	)
	if err != nil {
		if isUniqueConstraint(err) {
			if rollbackErr := transaction.Rollback(); rollbackErr != nil {
				return nil, errors.Join(
					fmt.Errorf("insert stage: %w", err),
					fmt.Errorf("rollback stage create: %w", rollbackErr),
				)
			}

			return repository.translateDuplicateName(
				ctx,
				input.PipelineID,
				name,
				nameNorm,
				err,
			)
		}

		return nil, fmt.Errorf("insert stage: %w", err)
	}

	id, err := result.LastInsertId()
	if err != nil {
		return nil, fmt.Errorf("read inserted stage id: %w", err)
	}
	if err := transaction.Commit(); err != nil {
		return nil, fmt.Errorf("commit stage create: %w", err)
	}

	// The transaction is complete before re-reading: SetMaxOpenConns(1) makes
	// a pool read while the transaction owns the connection self-deadlock.
	return repository.FindByID(ctx, id)
}

func stageInsertPosition(
	ctx context.Context,
	transaction *sql.Tx,
	input model.CreateStageInput,
) (int, error) {
	if input.First {
		return 1, nil
	}
	if input.AfterStageID != nil {
		var position int
		err := transaction.QueryRowContext(
			ctx,
			`SELECT position FROM stages
             WHERE id = ? AND pipeline_id = ? AND archived_at IS NULL`,
			*input.AfterStageID,
			input.PipelineID,
		).Scan(&position)
		if errors.Is(err, sql.ErrNoRows) {
			return 0, model.NewExitError(
				model.ErrNotFound,
				"stage s%d is not a live stage in pipeline p%d",
				*input.AfterStageID,
				input.PipelineID,
			)
		}
		if err != nil {
			return 0, fmt.Errorf("find stage insertion anchor: %w", err)
		}

		return position + 1, nil
	}

	var position int
	if err := transaction.QueryRowContext(
		ctx,
		`SELECT COALESCE(MAX(position), 0) + 1 FROM stages
         WHERE pipeline_id = ? AND archived_at IS NULL`,
		input.PipelineID,
	).Scan(&position); err != nil {
		return 0, fmt.Errorf("find appended stage position: %w", err)
	}

	return position, nil
}

// Rename changes a stage's display and normalized names together.
func (repository *StageRepo) Rename(
	ctx context.Context,
	id int64,
	nameInput string,
) (*model.Stage, error) {
	current, err := repository.FindByID(ctx, id)
	if err != nil {
		return nil, err
	}
	name := strings.TrimSpace(nameInput)
	nameNorm, ok := model.TryNormalizeName(name)
	if !ok {
		return nil, model.NewExitError(model.ErrValidation, "stage name must not be empty")
	}
	if current.Name == name && current.NameNorm == nameNorm {
		return current, nil
	}

	result, err := repository.database.ExecContext(
		ctx,
		"UPDATE stages SET name = ?, name_norm = ?, updated_at = ? WHERE id = ?",
		name,
		nameNorm,
		time.Now().UTC().Format(time.RFC3339),
		id,
	)
	if err != nil {
		if isUniqueConstraint(err) {
			return repository.translateDuplicateName(
				ctx,
				current.PipelineID,
				name,
				nameNorm,
				err,
			)
		}

		return nil, fmt.Errorf("rename stage s%d: %w", id, err)
	}
	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return nil, fmt.Errorf("read renamed stage row count: %w", err)
	}
	if rowsAffected == 0 {
		return nil, model.NewExitError(model.ErrNotFound, "stage s%d not found", id)
	}

	return repository.FindByID(ctx, id)
}

// SetRot changes a stage's staleness threshold. Nil means the stage never
// rots; an unchanged value is a true no-op.
func (repository *StageRepo) SetRot(
	ctx context.Context,
	id int64,
	rotDays *int,
) (*model.Stage, error) {
	if rotDays != nil && *rotDays <= 0 {
		return nil, model.NewExitError(
			model.ErrValidation,
			"rot days must be a positive integer or none",
		)
	}
	current, err := repository.FindByID(ctx, id)
	if err != nil {
		return nil, err
	}
	if equalOptionalInts(current.RotDays, rotDays) {
		return current, nil
	}

	var argument any
	if rotDays != nil {
		argument = *rotDays
	}
	result, err := repository.database.ExecContext(
		ctx,
		"UPDATE stages SET rot_days = ?, updated_at = ? WHERE id = ?",
		argument,
		time.Now().UTC().Format(time.RFC3339),
		id,
	)
	if err != nil {
		return nil, fmt.Errorf("set rot threshold on stage s%d: %w", id, err)
	}
	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return nil, fmt.Errorf("read stage rot update row count: %w", err)
	}
	if rowsAffected == 0 {
		return nil, model.NewExitError(model.ErrNotFound, "stage s%d not found", id)
	}

	return repository.FindByID(ctx, id)
}

func equalOptionalInts(left, right *int) bool {
	if left == nil || right == nil {
		return left == nil && right == nil
	}

	return *left == *right
}

// Reorder assigns dense 1-based positions to the supplied live stage ids in
// one transaction and returns the committed order.
func (repository *StageRepo) Reorder(
	ctx context.Context,
	pipelineID int64,
	orderedIDs []int64,
) ([]model.Stage, error) {
	now := time.Now().UTC().Format(time.RFC3339)
	transaction, err := repository.database.BeginTx(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("begin stage reorder: %w", err)
	}
	defer func() {
		_ = transaction.Rollback()
	}()

	for index, id := range orderedIDs {
		result, updateErr := transaction.ExecContext(
			ctx,
			`UPDATE stages SET position = ?, updated_at = ?
             WHERE id = ? AND pipeline_id = ? AND archived_at IS NULL`,
			index+1,
			now,
			id,
			pipelineID,
		)
		if updateErr != nil {
			return nil, fmt.Errorf("reorder stage s%d: %w", id, updateErr)
		}
		rowsAffected, rowsErr := result.RowsAffected()
		if rowsErr != nil {
			return nil, fmt.Errorf("read reordered stage s%d row count: %w", id, rowsErr)
		}
		if rowsAffected == 0 {
			return nil, model.NewExitError(
				model.ErrNotFound,
				"stage s%d is not a live stage in pipeline p%d",
				id,
				pipelineID,
			)
		}
	}
	if err := transaction.Commit(); err != nil {
		return nil, fmt.Errorf("commit stage reorder: %w", err)
	}

	// Re-read only after commit to avoid contending with the transaction for
	// the configured single database connection.
	return repository.ListByPipeline(ctx, pipelineID, false)
}

// FindByID returns one stage by numeric id, including archived stages.
func (repository *StageRepo) FindByID(ctx context.Context, id int64) (*model.Stage, error) {
	row := repository.database.QueryRowContext(
		ctx,
		"SELECT "+stageColumns+" FROM stages WHERE id = ?",
		id,
	)
	stage, err := scanStage(row)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, model.NewExitError(model.ErrNotFound, "stage s%d not found", id)
	}
	if err != nil {
		return nil, fmt.Errorf("find stage s%d: %w", id, err)
	}

	return stage, nil
}

// ListByPipeline returns stages in deterministic pipeline order.
func (repository *StageRepo) ListByPipeline(
	ctx context.Context,
	pipelineID int64,
	includeArchived bool,
) ([]model.Stage, error) {
	query := "SELECT " + stageColumns + " FROM stages WHERE pipeline_id = ?"
	if !includeArchived {
		query += " AND archived_at IS NULL"
	}
	query += " ORDER BY position ASC, id ASC"
	rows, err := repository.database.QueryContext(ctx, query, pipelineID)
	if err != nil {
		return nil, fmt.Errorf("list stages for pipeline p%d: %w", pipelineID, err)
	}

	stages := make([]model.Stage, 0)
	for rows.Next() {
		stage, scanErr := scanStage(rows)
		if scanErr != nil {
			_ = rows.Close()
			return nil, fmt.Errorf("scan stage for pipeline p%d: %w", pipelineID, scanErr)
		}
		stages = append(stages, *stage)
	}
	if err := rows.Err(); err != nil {
		_ = rows.Close()
		return nil, fmt.Errorf("iterate stages for pipeline p%d: %w", pipelineID, err)
	}
	if err := rows.Close(); err != nil {
		return nil, fmt.Errorf("close stages for pipeline p%d: %w", pipelineID, err)
	}

	return stages, nil
}

func loadStagesForPipelines(
	ctx context.Context,
	database *sql.DB,
	pipelineIDs []int64,
) (map[int64][]model.Stage, error) {
	stagesByPipeline := make(map[int64][]model.Stage, len(pipelineIDs))
	for _, id := range pipelineIDs {
		stagesByPipeline[id] = make([]model.Stage, 0)
	}
	if len(pipelineIDs) == 0 {
		return stagesByPipeline, nil
	}

	placeholders := strings.TrimSuffix(strings.Repeat("?,", len(pipelineIDs)), ",")
	query := "SELECT " + stageColumns + " FROM stages WHERE archived_at IS NULL" +
		" AND pipeline_id IN (" + placeholders + ")" +
		" ORDER BY pipeline_id ASC, position ASC, id ASC"
	arguments := make([]any, len(pipelineIDs))
	for index, id := range pipelineIDs {
		arguments[index] = id
	}
	rows, err := database.QueryContext(ctx, query, arguments...)
	if err != nil {
		return nil, fmt.Errorf("load pipeline stages: %w", err)
	}
	for rows.Next() {
		stage, scanErr := scanStage(rows)
		if scanErr != nil {
			_ = rows.Close()
			return nil, fmt.Errorf("scan pipeline stage: %w", scanErr)
		}
		stagesByPipeline[stage.PipelineID] = append(
			stagesByPipeline[stage.PipelineID],
			*stage,
		)
	}
	if err := rows.Err(); err != nil {
		_ = rows.Close()
		return nil, fmt.Errorf("iterate pipeline stages: %w", err)
	}
	if err := rows.Close(); err != nil {
		return nil, fmt.Errorf("close pipeline stages: %w", err)
	}

	return stagesByPipeline, nil
}

func (repository *StageRepo) translateDuplicateName(
	ctx context.Context,
	pipelineID int64,
	inputName string,
	nameNorm string,
	constraintError error,
) (*model.Stage, error) {
	row := repository.database.QueryRowContext(
		ctx,
		"SELECT "+stageColumns+" FROM stages "+
			"WHERE pipeline_id = ? AND name_norm = ? AND archived_at IS NULL",
		pipelineID,
		nameNorm,
	)
	owner, err := scanStage(row)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, fmt.Errorf("insert or rename stage: %w", constraintError)
	}
	if err != nil {
		return nil, fmt.Errorf("find stage owning duplicate name: %w", err)
	}

	return nil, model.NewExitError(
		model.ErrConflict,
		"duplicate stage name %q — already on stage %s (%s) in pipeline p%d",
		inputName,
		owner.Reference(),
		owner.Name,
		pipelineID,
	)
}
