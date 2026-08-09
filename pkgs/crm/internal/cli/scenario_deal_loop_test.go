package cli

import (
	"database/sql"
	"encoding/json"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/mecattaf/crm/internal/db"
)

type dealOutput struct {
	Ref            string  `json:"ref"`
	ID             int64   `json:"id"`
	Title          string  `json:"title"`
	TitleNorm      string  `json:"title_norm"`
	OrgID          *int64  `json:"org_id"`
	ContactID      *int64  `json:"contact_id"`
	PipelineID     int64   `json:"pipeline_id"`
	Pipeline       string  `json:"pipeline"`
	StageID        int64   `json:"stage_id"`
	Stage          string  `json:"stage"`
	Status         string  `json:"status"`
	OutcomeReason  *string `json:"outcome_reason"`
	ClosedAt       *string `json:"closed_at"`
	StageChangedAt string  `json:"stage_changed_at"`
	DaysInStage    int     `json:"days_in_stage"`
	RotDays        *int    `json:"rot_days"`
	CreatedAt      string  `json:"created_at"`
	UpdatedAt      string  `json:"updated_at"`
	ArchivedAt     *string `json:"archived_at"`
}

type dealDetailOutput struct {
	dealOutput
	StageMoves []stageMoveOutput    `json:"stage_moves"`
	Timeline   []dealTimelineOutput `json:"timeline"`
}

type stageMoveOutput struct {
	ID            int64   `json:"id"`
	DealID        int64   `json:"deal_id"`
	FromStageID   *int64  `json:"from_stage_id"`
	FromStageName *string `json:"from_stage"`
	ToStageID     int64   `json:"to_stage_id"`
	ToStageName   string  `json:"to_stage"`
	MovedAt       string  `json:"moved_at"`
	Note          *string `json:"note"`
}

type dealTimelineOutput struct {
	Type        string           `json:"type"`
	OccurredAt  string           `json:"occurred_at"`
	StageMove   *stageMoveOutput `json:"stage_move"`
	Interaction json.RawMessage  `json:"interaction"`
}

func TestScenarioDealLoop(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "crm.db")
	stdout, stderr, code := crm(t, databasePath, "init")
	assertCommandResult(t, stdout, stderr, code, databasePath+"\n", "", 0)

	for _, command := range [][]string{
		{"org", "add", "Kima Ventures"},
		{"contact", "add", "Nick Dupont", "--org", "kima", "--email", "nick@kima.vc"},
		{"pipeline", "add", "Seed raise"},
		{"stage", "add", "p1", "sourced"},
		{"stage", "add", "p1", "pitched", "--rot", "2"},
	} {
		stdout, stderr, code = crm(t, databasePath, command...)
		if stderr != "" || code != 0 {
			t.Fatalf("fixture command %v stdout=%q stderr=%q code=%d", command, stdout, stderr, code)
		}
	}

	stdout, stderr, code = crm(t, databasePath, "deal", "add", "No anchor", "--pipeline", "p1")
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"",
		"crm: error: deal add requires at least one of --org or --contact\n",
		1,
	)

	stdout, stderr, code = crm(
		t,
		databasePath,
		"deal", "add", "Kima seed ticket", "--pipeline", "Seed raise",
		"--org", "kima",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("deal add stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	created := decodeDealRows(t, stdout, 1)[0]
	if created.Ref != "d1" || created.TitleNorm != "kima seed ticket" ||
		created.Pipeline != "Seed raise" || created.Stage != "sourced" ||
		created.Status != "open" || created.OrgID == nil || *created.OrgID != 1 ||
		created.ContactID != nil {
		t.Fatalf("created deal = %#v", created)
	}
	assertRFC3339(t, "deal.stage_changed_at", created.StageChangedAt)
	assertOpeningStageMove(t, databasePath, created)

	stdout, stderr, code = crm(
		t,
		databasePath,
		"log", "--deal", "d1", "--kind", "email", "--date", "2026-07-30",
		"--summary", "sent the deck",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("deal log stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	stdout, stderr, code = crm(t, databasePath, "interaction", "ls", "--deal", "Kima seed", "--format", "json")
	if stderr != "" || code != 0 || !strings.Contains(stdout, `"summary":"sent the deck"`) {
		t.Fatalf("interaction deal filter stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}

	stdout, stderr, code = crm(
		t,
		databasePath,
		"deal", "move", "d1", "pitched", "--note", "deck sent",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("deal move stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	moved := decodeDealRows(t, stdout, 1)[0]
	if moved.Stage != "pitched" || moved.StageID != 2 {
		t.Fatalf("moved deal = %#v", moved)
	}
	stdout, stderr, code = crm(t, databasePath, "deal", "move", "d1", "pitched")
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"",
		"crm: error: deal d1 already in stage pitched\n",
		4,
	)

	stdout, stderr, code = crm(t, databasePath, "d", "show", "d1", "--format", "json")
	if stderr != "" || code != 0 {
		t.Fatalf("deal alias show stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	detail := decodeDealDetails(t, stdout, 1)[0]
	if len(detail.StageMoves) != 2 || detail.StageMoves[0].FromStageID != nil ||
		detail.StageMoves[0].ToStageName != "sourced" ||
		detail.StageMoves[1].FromStageName == nil || *detail.StageMoves[1].FromStageName != "sourced" ||
		detail.StageMoves[1].ToStageName != "pitched" ||
		detail.StageMoves[1].Note == nil || *detail.StageMoves[1].Note != "deck sent" {
		t.Fatalf("stage history = %#v", detail.StageMoves)
	}
	if len(detail.Timeline) != 3 || !timelineHasType(detail.Timeline, "interaction") ||
		!timelineHasType(detail.Timeline, "stage_move") {
		t.Fatalf("merged deal timeline = %#v", detail.Timeline)
	}

	backdateDealStage(t, databasePath, "d1", 6*24*time.Hour)
	stdout, stderr, code = crm(t, databasePath, "deal", "ls", "--stage", "pitched")
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"",
		"crm: error: --stage requires --pipeline because stage names are pipeline-scoped\n",
		1,
	)
	stdout, stderr, code = crm(
		t,
		databasePath,
		"deal", "ls", "--pipeline", "p1", "--stage", "pitched", "--format", "json",
	)
	if stderr != "" || code != 0 || len(decodeDealRows(t, stdout, 1)) != 1 {
		t.Fatalf("pipeline-scoped deal ls stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	stdout, stderr, code = crm(t, databasePath, "deal", "ls", "--rotting", "--format", "json")
	if stderr != "" || code != 0 {
		t.Fatalf("rotting deal ls stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	rotting := decodeDealRows(t, stdout, 1)[0]
	if rotting.Ref != "d1" || rotting.DaysInStage < 5 || rotting.RotDays == nil || *rotting.RotDays != 2 {
		t.Fatalf("rotting deal = %#v", rotting)
	}

	stdout, stderr, code = crm(t, databasePath, "context", "nick", "--format", "table")
	if stderr != "" || code != 0 ||
		!strings.Contains(stdout, "d1  Kima seed ticket  pitched  ") ||
		!strings.Contains(stdout, "days in stage") {
		t.Fatalf("contact deal context stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	stdout, stderr, code = crm(t, databasePath, "context", "kima", "--format", "json")
	if stderr != "" || code != 0 {
		t.Fatalf("org deal context stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	assertJSONArrayLength(t, decodeContextObject(t, stdout), "deals", 1)

	stdout, stderr, code = crm(t, databasePath, "deal", "win", "d1", "--reason", "led the round")
	if stderr != "" || code != 0 {
		t.Fatalf("deal win stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	won := decodeDealRows(t, stdout, 1)[0]
	if won.Status != "won" || won.ClosedAt == nil ||
		won.OutcomeReason == nil || *won.OutcomeReason != "led the round" {
		t.Fatalf("won deal = %#v", won)
	}
	assertRFC3339(t, "deal.closed_at", *won.ClosedAt)
	stdout, stderr, code = crm(t, databasePath, "context", "nick", "--format", "json")
	if stderr != "" || code != 0 {
		t.Fatalf("won contact context stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	assertJSONArrayLength(t, decodeContextObject(t, stdout), "deals", 0)

	stdout, stderr, code = crm(t, databasePath, "deal", "reopen", "d1")
	if stderr != "" || code != 0 {
		t.Fatalf("deal reopen stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	reopened := decodeDealRows(t, stdout, 1)[0]
	if reopened.Status != "open" || reopened.ClosedAt != nil ||
		reopened.OutcomeReason == nil || *reopened.OutcomeReason != "led the round" {
		t.Fatalf("reopened deal = %#v", reopened)
	}
	assertNoSidecars(t, databasePath)
}

func decodeDealRows(t *testing.T, output string, want int) []dealOutput {
	t.Helper()

	var rows []dealOutput
	if err := json.Unmarshal([]byte(output), &rows); err != nil {
		t.Fatalf("decode deal output %q: %v", output, err)
	}
	if len(rows) != want {
		t.Fatalf("deal output length = %d, want %d: %#v", len(rows), want, rows)
	}
	assertCompactJSON(t, output, rows)

	return rows
}

func decodeDealDetails(t *testing.T, output string, want int) []dealDetailOutput {
	t.Helper()

	var rows []dealDetailOutput
	if err := json.Unmarshal([]byte(output), &rows); err != nil {
		t.Fatalf("decode deal detail output %q: %v", output, err)
	}
	if len(rows) != want {
		t.Fatalf("deal detail output length = %d, want %d: %#v", len(rows), want, rows)
	}
	if rows[0].StageMoves == nil || rows[0].Timeline == nil {
		t.Fatalf("deal detail collections must encode as arrays: %#v", rows[0])
	}

	return rows
}

func assertOpeningStageMove(t *testing.T, databasePath string, deal dealOutput) {
	t.Helper()

	database, err := db.Open(databasePath)
	if err != nil {
		t.Fatalf("open deal fixture database: %v", err)
	}
	defer func() {
		_ = database.Close()
	}()

	var fromStageID sql.NullInt64
	var toStageID int64
	var movedAt string
	if err := database.QueryRow(
		"SELECT from_stage_id, to_stage_id, moved_at FROM stage_moves WHERE deal_id = ?",
		deal.ID,
	).Scan(&fromStageID, &toStageID, &movedAt); err != nil {
		t.Fatalf("read opening stage move: %v", err)
	}
	if fromStageID.Valid || toStageID != deal.StageID || movedAt != deal.StageChangedAt {
		t.Fatalf(
			"opening move from=%v to=%d at=%q, want NULL to=%d at=%q",
			fromStageID,
			toStageID,
			movedAt,
			deal.StageID,
			deal.StageChangedAt,
		)
	}
}

func backdateDealStage(t *testing.T, databasePath, dealRef string, age time.Duration) {
	t.Helper()

	database, err := db.Open(databasePath)
	if err != nil {
		t.Fatalf("open rot fixture database: %v", err)
	}
	defer func() {
		_ = database.Close()
	}()

	id := strings.TrimPrefix(dealRef, "d")
	timestamp := time.Now().UTC().Add(-age).Format(time.RFC3339)
	if _, err := database.Exec(
		"UPDATE deals SET stage_changed_at = ? WHERE id = ?",
		timestamp,
		id,
	); err != nil {
		t.Fatalf("backdate deal stage: %v", err)
	}
}

func timelineHasType(entries []dealTimelineOutput, wanted string) bool {
	for _, entry := range entries {
		if entry.Type == wanted {
			return true
		}
	}

	return false
}
