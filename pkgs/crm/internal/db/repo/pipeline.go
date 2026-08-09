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

const pipelineColumns = `id, name, name_norm, position, created_at,
updated_at, archived_at`

// PipelineRepo owns pipeline persistence and ordered stage loading.
type PipelineRepo struct {
	database *sql.DB
}

// NewPipelineRepo constructs a pipeline repository.
func NewPipelineRepo(database *sql.DB) *PipelineRepo {
	return &PipelineRepo{database: database}
}

func scanPipeline(row scanner) (*model.Pipeline, error) {
	var pipeline model.Pipeline
	var archivedAt sql.NullString
	if err := row.Scan(
		&pipeline.ID,
		&pipeline.Name,
		&pipeline.NameNorm,
		&pipeline.Position,
		&pipeline.CreatedAt,
		&pipeline.UpdatedAt,
		&archivedAt,
	); err != nil {
		return nil, err
	}

	pipeline.Ref = fmt.Sprintf("p%d", pipeline.ID)
	pipeline.Stages = make([]model.Stage, 0)
	pipeline.ArchivedAt = nullString(archivedAt)

	return &pipeline, nil
}

// Create inserts a pipeline at the end of the global pipeline order and
// returns the committed record. The live name UNIQUE index arbitrates dupes.
func (repository *PipelineRepo) Create(
	ctx context.Context,
	nameInput string,
) (*model.Pipeline, error) {
	name := strings.TrimSpace(nameInput)
	nameNorm, ok := model.TryNormalizeName(name)
	if !ok {
		return nil, model.NewExitError(model.ErrValidation, "pipeline name must not be empty")
	}

	now := time.Now().UTC().Format(time.RFC3339)
	transaction, err := repository.database.BeginTx(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("begin pipeline create: %w", err)
	}
	defer func() {
		_ = transaction.Rollback()
	}()

	var position int
	if err := transaction.QueryRowContext(
		ctx,
		"SELECT COALESCE(MAX(position), 0) + 1 FROM pipelines",
	).Scan(&position); err != nil {
		return nil, fmt.Errorf("find appended pipeline position: %w", err)
	}
	result, err := transaction.ExecContext(
		ctx,
		`INSERT INTO pipelines (
            name, name_norm, position, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?)`,
		name,
		nameNorm,
		position,
		now,
		now,
	)
	if err != nil {
		if isUniqueConstraint(err) {
			if rollbackErr := transaction.Rollback(); rollbackErr != nil {
				return nil, errors.Join(
					fmt.Errorf("insert pipeline: %w", err),
					fmt.Errorf("rollback pipeline create: %w", rollbackErr),
				)
			}

			return repository.translateDuplicateName(ctx, name, nameNorm, err)
		}

		return nil, fmt.Errorf("insert pipeline: %w", err)
	}
	id, err := result.LastInsertId()
	if err != nil {
		return nil, fmt.Errorf("read inserted pipeline id: %w", err)
	}
	if err := transaction.Commit(); err != nil {
		return nil, fmt.Errorf("commit pipeline create: %w", err)
	}

	// The transaction is complete before re-reading: SetMaxOpenConns(1) makes
	// a pool read while the transaction owns the connection self-deadlock.
	return repository.FindByID(ctx, id)
}

// Rename changes a pipeline's display and normalized names together.
func (repository *PipelineRepo) Rename(
	ctx context.Context,
	id int64,
	nameInput string,
) (*model.Pipeline, error) {
	current, err := repository.FindByID(ctx, id)
	if err != nil {
		return nil, err
	}
	name := strings.TrimSpace(nameInput)
	nameNorm, ok := model.TryNormalizeName(name)
	if !ok {
		return nil, model.NewExitError(model.ErrValidation, "pipeline name must not be empty")
	}
	if current.Name == name && current.NameNorm == nameNorm {
		return current, nil
	}

	result, err := repository.database.ExecContext(
		ctx,
		"UPDATE pipelines SET name = ?, name_norm = ?, updated_at = ? WHERE id = ?",
		name,
		nameNorm,
		time.Now().UTC().Format(time.RFC3339),
		id,
	)
	if err != nil {
		if isUniqueConstraint(err) {
			return repository.translateDuplicateName(ctx, name, nameNorm, err)
		}

		return nil, fmt.Errorf("rename pipeline p%d: %w", id, err)
	}
	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return nil, fmt.Errorf("read renamed pipeline row count: %w", err)
	}
	if rowsAffected == 0 {
		return nil, model.NewExitError(model.ErrNotFound, "pipeline p%d not found", id)
	}

	return repository.FindByID(ctx, id)
}

// FindByID returns one pipeline by numeric id, including archived rows, with
// its ordered live stages.
func (repository *PipelineRepo) FindByID(
	ctx context.Context,
	id int64,
) (*model.Pipeline, error) {
	row := repository.database.QueryRowContext(
		ctx,
		"SELECT "+pipelineColumns+" FROM pipelines WHERE id = ?",
		id,
	)
	pipeline, err := scanPipeline(row)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, model.NewExitError(model.ErrNotFound, "pipeline p%d not found", id)
	}
	if err != nil {
		return nil, fmt.Errorf("find pipeline p%d: %w", id, err)
	}

	stagesByPipeline, err := loadStagesForPipelines(ctx, repository.database, []int64{id})
	if err != nil {
		return nil, err
	}
	pipeline.Stages = stagesByPipeline[id]

	return pipeline, nil
}

// List returns pipelines in deterministic position order. It drains and
// closes the pipeline rows before batch-loading stages: with one configured
// connection, querying children inside rows.Next would self-deadlock.
func (repository *PipelineRepo) List(
	ctx context.Context,
	includeArchived bool,
) ([]model.Pipeline, error) {
	query := "SELECT " + pipelineColumns + " FROM pipelines WHERE 1 = 1"
	if !includeArchived {
		query += " AND archived_at IS NULL"
	}
	query += " ORDER BY position ASC, id ASC"
	rows, err := repository.database.QueryContext(ctx, query)
	if err != nil {
		return nil, fmt.Errorf("list pipelines: %w", err)
	}

	pipelines := make([]model.Pipeline, 0)
	pipelineIDs := make([]int64, 0)
	for rows.Next() {
		pipeline, scanErr := scanPipeline(rows)
		if scanErr != nil {
			_ = rows.Close()
			return nil, fmt.Errorf("scan pipeline: %w", scanErr)
		}
		pipelines = append(pipelines, *pipeline)
		pipelineIDs = append(pipelineIDs, pipeline.ID)
	}
	if err := rows.Err(); err != nil {
		_ = rows.Close()
		return nil, fmt.Errorf("iterate pipelines: %w", err)
	}
	if err := rows.Close(); err != nil {
		return nil, fmt.Errorf("close pipelines: %w", err)
	}

	stagesByPipeline, err := loadStagesForPipelines(ctx, repository.database, pipelineIDs)
	if err != nil {
		return nil, err
	}
	for index := range pipelines {
		pipelines[index].Stages = stagesByPipeline[pipelines[index].ID]
	}

	return pipelines, nil
}

func (repository *PipelineRepo) translateDuplicateName(
	ctx context.Context,
	inputName string,
	nameNorm string,
	constraintError error,
) (*model.Pipeline, error) {
	row := repository.database.QueryRowContext(
		ctx,
		"SELECT "+pipelineColumns+" FROM pipelines "+
			"WHERE name_norm = ? AND archived_at IS NULL",
		nameNorm,
	)
	owner, err := scanPipeline(row)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, fmt.Errorf("insert or rename pipeline: %w", constraintError)
	}
	if err != nil {
		return nil, fmt.Errorf("find pipeline owning duplicate name: %w", err)
	}

	return nil, model.NewExitError(
		model.ErrConflict,
		"duplicate pipeline name %q — already on pipeline %s (%s)",
		inputName,
		owner.Reference(),
		owner.Name,
	)
}
