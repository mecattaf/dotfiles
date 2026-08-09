package repo_test

import (
	"context"
	"database/sql"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/mecattaf/crm/internal/db/dbtest"
	"github.com/mecattaf/crm/internal/db/repo"
	"github.com/mecattaf/crm/internal/model"
)

func TestContactMergeRollsBackEveryChangeOnMidMergeFailure(t *testing.T) {
	t.Parallel()

	ctx := context.Background()
	database := dbtest.Open(t)
	contacts := repo.NewContactRepo(database)
	winner, err := contacts.Create(ctx, model.CreateContactInput{
		Name:              "Winner",
		Phone:             "+33123456789",
		ProvenanceSources: []string{"winner.md"},
	})
	if err != nil {
		t.Fatalf("create merge winner: %v", err)
	}
	loser, err := contacts.Create(ctx, model.CreateContactInput{
		Name:              "Loser",
		Email:             "loser@example.com",
		ProvenanceSources: []string{"loser.md"},
	})
	if err != nil {
		t.Fatalf("create merge loser: %v", err)
	}

	now := time.Now().UTC().Format(time.RFC3339)
	pipelineID := mustInsertID(t, database, `INSERT INTO pipelines (
		name, name_norm, position, created_at, updated_at
	) VALUES ('Merge pipeline', 'merge pipeline', 1, ?, ?)`, now, now)
	stageID := mustInsertID(t, database, `INSERT INTO stages (
		pipeline_id, name, name_norm, position, created_at, updated_at
	) VALUES (?, 'open', 'open', 1, ?, ?)`, pipelineID, now, now)
	dealID := mustInsertID(t, database, `INSERT INTO deals (
		title, title_norm, contact_id, pipeline_id, stage_id, status,
		stage_changed_at, created_at, updated_at
	) VALUES ('Blocked merge', 'blocked merge', ?, ?, ?, 'open', ?, ?, ?)`,
		loser.ID, pipelineID, stageID, now, now, now)

	trigger := fmt.Sprintf(`CREATE TRIGGER force_contact_merge_failure
		BEFORE UPDATE OF contact_id ON deals
		WHEN OLD.id = %d
		BEGIN
			SELECT RAISE(ABORT, 'forced merge failure');
		END`, dealID)
	if _, err := database.ExecContext(ctx, trigger); err != nil {
		t.Fatalf("create forced-failure trigger: %v", err)
	}

	winnerBefore := *winner
	loserBefore := *loser
	_, err = contacts.Merge(ctx, winner.ID, loser.ID)
	if err == nil || !strings.Contains(err.Error(), "forced merge failure") {
		t.Fatalf("contact merge error = %v, want forced failure", err)
	}

	winnerAfter, err := contacts.FindByID(ctx, winner.ID)
	if err != nil {
		t.Fatalf("read winner after rollback: %v", err)
	}
	loserAfter, err := contacts.FindByID(ctx, loser.ID)
	if err != nil {
		t.Fatalf("read loser after rollback: %v", err)
	}
	if winnerAfter.Email != nil || winnerAfter.UpdatedAt != winnerBefore.UpdatedAt ||
		winnerAfter.ArchivedAt != nil || stringPointerValue(winnerAfter.ProvenanceSources) != "winner.md" {
		t.Fatalf("winner changed despite rollback: before=%#v after=%#v", winnerBefore, *winnerAfter)
	}
	if loserAfter.ArchivedAt != nil || loserAfter.UpdatedAt != loserBefore.UpdatedAt ||
		stringPointerValue(loserAfter.Email) != "loser@example.com" ||
		stringPointerValue(loserAfter.ProvenanceSources) != "loser.md" {
		t.Fatalf("loser changed despite rollback: before=%#v after=%#v", loserBefore, *loserAfter)
	}

	var dealContactID int64
	if err := database.QueryRowContext(
		ctx,
		"SELECT contact_id FROM deals WHERE id = ?",
		dealID,
	).Scan(&dealContactID); err != nil {
		t.Fatalf("read deal contact after rollback: %v", err)
	}
	if dealContactID != loser.ID {
		t.Fatalf("deal contact after rollback = c%d, want c%d", dealContactID, loser.ID)
	}
}

func mustInsertID(t *testing.T, database *sql.DB, query string, args ...any) int64 {
	t.Helper()

	result, err := database.Exec(query, args...)
	if err != nil {
		t.Fatalf("insert fixture: %v", err)
	}
	id, err := result.LastInsertId()
	if err != nil {
		t.Fatalf("read fixture id: %v", err)
	}

	return id
}

func stringPointerValue(value *string) string {
	if value == nil {
		return ""
	}

	return *value
}
