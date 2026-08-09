package repo

import (
	"context"
	"database/sql"
	"fmt"
	"strconv"
	"strings"

	"github.com/mecattaf/crm/internal/model"
)

type doctorFTSTable struct {
	contentTable string
	ftsTable     string
	docsizeTable string
}

var doctorFTSTables = []doctorFTSTable{
	{contentTable: "orgs", ftsTable: "orgs_fts", docsizeTable: "orgs_fts_docsize"},
	{contentTable: "contacts", ftsTable: "contacts_fts", docsizeTable: "contacts_fts_docsize"},
	{
		contentTable: "interactions",
		ftsTable:     "interactions_fts",
		docsizeTable: "interactions_fts_docsize",
	},
	{contentTable: "deals", ftsTable: "deals_fts", docsizeTable: "deals_fts_docsize"},
}

// DoctorRepo owns the database-backed integrity checks and FTS repair path.
type DoctorRepo struct {
	database *sql.DB
}

// NewDoctorRepo constructs the integrity-report repository.
func NewDoctorRepo(database *sql.DB) *DoctorRepo {
	return &DoctorRepo{database: database}
}

// IntegrityCheck runs SQLite's full database integrity check.
func (repository *DoctorRepo) IntegrityCheck(ctx context.Context) model.DoctorCheck {
	results, err := queryStringColumn(ctx, repository.database, "PRAGMA integrity_check")
	if err != nil {
		return failedDoctorCheck("query failed: %v", err)
	}
	if len(results) == 1 && strings.EqualFold(results[0], "ok") {
		return passedDoctorCheck("ok")
	}
	if len(results) == 0 {
		return failedDoctorCheck("returned no result")
	}

	return failedDoctorCheck("%s", strings.Join(results, "; "))
}

// ForeignKeyCheck reports every row returned by PRAGMA foreign_key_check.
func (repository *DoctorRepo) ForeignKeyCheck(ctx context.Context) model.DoctorCheck {
	rows, err := repository.database.QueryContext(ctx, "PRAGMA foreign_key_check")
	if err != nil {
		return failedDoctorCheck("query failed: %v", err)
	}

	violations := make([]string, 0)
	for rows.Next() {
		var table string
		var rowID sql.NullInt64
		var parent string
		var foreignKeyID int64
		if err := rows.Scan(&table, &rowID, &parent, &foreignKeyID); err != nil {
			_ = rows.Close()
			return failedDoctorCheck("scan failed: %v", err)
		}
		row := "unknown"
		if rowID.Valid {
			row = strconv.FormatInt(rowID.Int64, 10)
		}
		violations = append(
			violations,
			fmt.Sprintf("%s row %s references %s (fk %d)", table, row, parent, foreignKeyID),
		)
	}
	if err := rows.Err(); err != nil {
		_ = rows.Close()
		return failedDoctorCheck("iteration failed: %v", err)
	}
	if err := rows.Close(); err != nil {
		return failedDoctorCheck("close failed: %v", err)
	}
	if len(violations) == 0 {
		return passedDoctorCheck("0 violations")
	}

	return failedDoctorCheck("%s", strings.Join(violations, "; "))
}

// FTSCheck runs the FTS5 external-content integrity command and compares the
// content row count with the docsize shadow-table count for every index.
// SELECT COUNT(*) FROM an external-content FTS table is deliberately not used:
// it reads the content table and can look healthy while the index is empty.
func (repository *DoctorRepo) FTSCheck(ctx context.Context) model.DoctorFTSCheck {
	check := model.DoctorFTSCheck{
		OK:     true,
		Tables: make([]model.DoctorFTSTableCheck, 0, len(doctorFTSTables)),
	}
	for _, table := range doctorFTSTables {
		tableCheck := repository.checkFTSTable(ctx, table)
		check.Tables = append(check.Tables, tableCheck)
		check.OK = check.OK && tableCheck.OK
	}

	return check
}

func (repository *DoctorRepo) checkFTSTable(
	ctx context.Context,
	table doctorFTSTable,
) model.DoctorFTSTableCheck {
	check := model.DoctorFTSTableCheck{Table: table.contentTable}
	issues := make([]string, 0, 3)

	contentQuery := fmt.Sprintf("SELECT COUNT(*) FROM %s", table.contentTable)
	if err := repository.database.QueryRowContext(ctx, contentQuery).Scan(&check.ContentRows); err != nil {
		issues = append(issues, fmt.Sprintf("content count failed: %v", err))
	}
	indexQuery := fmt.Sprintf("SELECT COUNT(*) FROM %s", table.docsizeTable)
	if err := repository.database.QueryRowContext(ctx, indexQuery).Scan(&check.IndexRows); err != nil {
		issues = append(issues, fmt.Sprintf("index count failed: %v", err))
	}
	if check.ContentRows != check.IndexRows {
		issues = append(
			issues,
			fmt.Sprintf("row count content=%d index=%d", check.ContentRows, check.IndexRows),
		)
	}

	// rank=1 tells FTS5 to compare an external-content table with its index,
	// rather than checking only the index's internal structure.
	integrityStatement := fmt.Sprintf(
		"INSERT INTO %s(%s, rank) VALUES('integrity-check', 1)",
		table.ftsTable,
		table.ftsTable,
	)
	if _, err := repository.database.ExecContext(ctx, integrityStatement); err != nil {
		issues = append(issues, fmt.Sprintf("integrity-check failed: %v", err))
	}

	check.OK = len(issues) == 0
	check.Detail = "ok"
	if !check.OK {
		check.Detail = strings.Join(issues, "; ")
	}

	return check
}

// JournalModeCheck asserts the repository's real file-backed journal mode.
func (repository *DoctorRepo) JournalModeCheck(ctx context.Context) model.DoctorCheck {
	var mode string
	if err := repository.database.QueryRowContext(ctx, "PRAGMA journal_mode").Scan(&mode); err != nil {
		return failedDoctorCheck("query failed: %v", err)
	}
	if !strings.EqualFold(mode, "delete") {
		return failedDoctorCheck("got %q, want %q", mode, "delete")
	}

	return passedDoctorCheck(strings.ToLower(mode))
}

// TranscriptPaths returns every non-null stored transcript path in stable
// interaction order. Filesystem resolution remains a command-layer concern.
func (repository *DoctorRepo) TranscriptPaths(
	ctx context.Context,
) ([]model.DoctorTranscript, error) {
	rows, err := repository.database.QueryContext(
		ctx,
		`SELECT id, transcript_path
		 FROM interactions
		 WHERE transcript_path IS NOT NULL
		 ORDER BY id ASC`,
	)
	if err != nil {
		return nil, fmt.Errorf("load transcript paths: %w", err)
	}

	transcripts := make([]model.DoctorTranscript, 0)
	for rows.Next() {
		var transcript model.DoctorTranscript
		if err := rows.Scan(&transcript.InteractionID, &transcript.Path); err != nil {
			_ = rows.Close()
			return nil, fmt.Errorf("scan transcript path: %w", err)
		}
		transcripts = append(transcripts, transcript)
	}
	if err := rows.Err(); err != nil {
		_ = rows.Close()
		return nil, fmt.Errorf("iterate transcript paths: %w", err)
	}
	if err := rows.Close(); err != nil {
		return nil, fmt.Errorf("close transcript paths: %w", err)
	}

	return transcripts, nil
}

// DealStagesCheck reports deals whose stage belongs to another pipeline (or
// is missing after an out-of-band write with foreign keys disabled).
func (repository *DoctorRepo) DealStagesCheck(ctx context.Context) model.DoctorCheck {
	rows, err := repository.database.QueryContext(
		ctx,
		`SELECT d.id, d.pipeline_id, d.stage_id, s.pipeline_id
		 FROM deals d
		 LEFT JOIN stages s ON s.id = d.stage_id
		 WHERE s.id IS NULL OR s.pipeline_id <> d.pipeline_id
		 ORDER BY d.id ASC`,
	)
	if err != nil {
		return failedDoctorCheck("query failed: %v", err)
	}

	violations := make([]string, 0)
	for rows.Next() {
		var dealID int64
		var dealPipelineID int64
		var stageID int64
		var stagePipelineID sql.NullInt64
		if err := rows.Scan(&dealID, &dealPipelineID, &stageID, &stagePipelineID); err != nil {
			_ = rows.Close()
			return failedDoctorCheck("scan failed: %v", err)
		}
		if !stagePipelineID.Valid {
			violations = append(
				violations,
				fmt.Sprintf("d%d uses missing stage s%d", dealID, stageID),
			)
			continue
		}
		violations = append(
			violations,
			fmt.Sprintf(
				"d%d pipeline p%d uses stage s%d from p%d",
				dealID,
				dealPipelineID,
				stageID,
				stagePipelineID.Int64,
			),
		)
	}
	if err := rows.Err(); err != nil {
		_ = rows.Close()
		return failedDoctorCheck("iteration failed: %v", err)
	}
	if err := rows.Close(); err != nil {
		return failedDoctorCheck("close failed: %v", err)
	}
	if len(violations) == 0 {
		return passedDoctorCheck("all deals consistent")
	}

	return failedDoctorCheck("%s", strings.Join(violations, "; "))
}

// InteractionLinksCheck reports interactions with no participant, org, or
// deal link after an out-of-band write.
func (repository *DoctorRepo) InteractionLinksCheck(ctx context.Context) model.DoctorCheck {
	rows, err := repository.database.QueryContext(
		ctx,
		`SELECT i.id
		 FROM interactions i
		 WHERE i.org_id IS NULL
		   AND i.deal_id IS NULL
		   AND NOT EXISTS (
		       SELECT 1
		       FROM interaction_people ip
		       WHERE ip.interaction_id = i.id
		   )
		 ORDER BY i.id ASC`,
	)
	if err != nil {
		return failedDoctorCheck("query failed: %v", err)
	}

	violations := make([]string, 0)
	for rows.Next() {
		var interactionID int64
		if err := rows.Scan(&interactionID); err != nil {
			_ = rows.Close()
			return failedDoctorCheck("scan failed: %v", err)
		}
		violations = append(violations, fmt.Sprintf("i%d", interactionID))
	}
	if err := rows.Err(); err != nil {
		_ = rows.Close()
		return failedDoctorCheck("iteration failed: %v", err)
	}
	if err := rows.Close(); err != nil {
		return failedDoctorCheck("close failed: %v", err)
	}
	if len(violations) == 0 {
		return passedDoctorCheck("all interactions linked")
	}

	return failedDoctorCheck("unlinked: %s", strings.Join(violations, ", "))
}

// UserVersionCheck reports and validates the migration ordinal stored by
// SQLite against the highest migration embedded in the running binary.
func (repository *DoctorRepo) UserVersionCheck(
	ctx context.Context,
	expected int,
) model.DoctorCheck {
	var version int64
	if err := repository.database.QueryRowContext(ctx, "PRAGMA user_version").Scan(&version); err != nil {
		return failedDoctorCheck("query failed: %v", err)
	}
	if version != int64(expected) {
		return failedDoctorCheck("got %d, want %d", version, expected)
	}

	return passedDoctorCheck(strconv.FormatInt(version, 10))
}

// RebuildFTS rebuilds every external-content index atomically.
func (repository *DoctorRepo) RebuildFTS(ctx context.Context) error {
	transaction, err := repository.database.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin FTS rebuild: %w", err)
	}
	defer func() {
		_ = transaction.Rollback()
	}()

	for _, table := range doctorFTSTables {
		statement := fmt.Sprintf(
			"INSERT INTO %s(%s) VALUES('rebuild')",
			table.ftsTable,
			table.ftsTable,
		)
		if _, err := transaction.ExecContext(ctx, statement); err != nil {
			return fmt.Errorf("rebuild %s: %w", table.ftsTable, err)
		}
	}
	if err := transaction.Commit(); err != nil {
		return fmt.Errorf("commit FTS rebuild: %w", err)
	}

	return nil
}

func queryStringColumn(
	ctx context.Context,
	database *sql.DB,
	query string,
) ([]string, error) {
	rows, err := database.QueryContext(ctx, query)
	if err != nil {
		return nil, err
	}

	values := make([]string, 0)
	for rows.Next() {
		var value string
		if err := rows.Scan(&value); err != nil {
			_ = rows.Close()
			return nil, err
		}
		values = append(values, value)
	}
	if err := rows.Err(); err != nil {
		_ = rows.Close()
		return nil, err
	}
	if err := rows.Close(); err != nil {
		return nil, err
	}

	return values, nil
}

func passedDoctorCheck(detail string) model.DoctorCheck {
	return model.DoctorCheck{OK: true, Detail: detail}
}

func failedDoctorCheck(message string, arguments ...any) model.DoctorCheck {
	return model.DoctorCheck{OK: false, Detail: fmt.Sprintf(message, arguments...)}
}
