package cli

import (
	"path/filepath"
	"testing"
	"time"

	"github.com/mecattaf/crm/internal/db"
)

func TestDealEditIsTruePatchAndKeepsAnAnchor(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "crm.db")
	stdout, stderr, code := crm(t, databasePath, "init")
	assertCommandResult(t, stdout, stderr, code, databasePath+"\n", "", 0)
	for _, command := range [][]string{
		{"org", "add", "Kima Ventures"},
		{"contact", "add", "Nick Dupont", "--email", "nick@kima.vc"},
		{"pipeline", "add", "Seed raise"},
		{"stage", "add", "p1", "sourced"},
		{"stage", "add", "p1", "pitched"},
		{"deal", "add", "Seed ticket", "--pipeline", "p1", "--org", "kima"},
	} {
		stdout, stderr, code = crm(t, databasePath, command...)
		if stderr != "" || code != 0 {
			t.Fatalf("fixture command %v stdout=%q stderr=%q code=%d", command, stdout, stderr, code)
		}
	}

	const oldUpdatedAt = "2020-01-02T03:04:05Z"
	database, err := db.Open(databasePath)
	if err != nil {
		t.Fatalf("open edit fixture: %v", err)
	}
	if _, err := database.Exec("UPDATE deals SET updated_at = ? WHERE id = 1", oldUpdatedAt); err != nil {
		_ = database.Close()
		t.Fatalf("backdate deal updated_at: %v", err)
	}
	if err := database.Close(); err != nil {
		t.Fatalf("close edit fixture: %v", err)
	}

	stdout, stderr, code = crm(t, databasePath, "deal", "edit", "d1", "--title", "Seed ticket")
	if stderr != "" || code != 0 {
		t.Fatalf("no-op deal edit stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	unchanged := decodeDealRows(t, stdout, 1)[0]
	if unchanged.UpdatedAt != oldUpdatedAt || unchanged.Stage != "sourced" || unchanged.Status != "open" {
		t.Fatalf("no-op deal edit changed protected fields: %#v", unchanged)
	}

	stdout, stderr, code = crm(
		t,
		databasePath,
		"deal", "edit", "d1", "--title", "Nick seed ticket", "--org", "", "--contact", "nick",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("deal anchor edit stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	edited := decodeDealRows(t, stdout, 1)[0]
	if edited.Title != "Nick seed ticket" || edited.TitleNorm != "nick seed ticket" ||
		edited.OrgID != nil || edited.ContactID == nil || *edited.ContactID != 1 ||
		edited.Stage != "sourced" || edited.Status != "open" {
		t.Fatalf("edited deal = %#v", edited)
	}

	stdout, stderr, code = crm(t, databasePath, "deal", "edit", "d1", "--contact", "")
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"",
		"crm: error: deal d1 must keep at least one of org or contact\n",
		4,
	)

	stdout, stderr, code = crm(t, databasePath, "deal", "ls", "--status", "closed")
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"",
		"crm: error: invalid deal status \"closed\" (accepted: open,won,lost)\n",
		1,
	)
	stdout, stderr, code = crm(t, databasePath, "deal", "ls", "--status", "")
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"",
		"crm: error: --status filter must not be empty\n",
		1,
	)
	assertNoSidecars(t, databasePath)
}

func TestDealRottingOrdersMostOverdueAndExcludesClosed(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "crm.db")
	stdout, stderr, code := crm(t, databasePath, "init")
	assertCommandResult(t, stdout, stderr, code, databasePath+"\n", "", 0)
	for _, command := range [][]string{
		{"org", "add", "Kima Ventures"},
		{"pipeline", "add", "Seed raise"},
		{"stage", "add", "p1", "pitched", "--rot", "2"},
		{"deal", "add", "Old ticket", "--pipeline", "p1", "--org", "kima"},
		{"deal", "add", "Newer ticket", "--pipeline", "p1", "--org", "kima"},
		{"deal", "add", "Closed ticket", "--pipeline", "p1", "--org", "kima"},
	} {
		stdout, stderr, code = crm(t, databasePath, command...)
		if stderr != "" || code != 0 {
			t.Fatalf("fixture command %v stdout=%q stderr=%q code=%d", command, stdout, stderr, code)
		}
	}

	backdateDealStage(t, databasePath, "d1", 10*24*time.Hour)
	backdateDealStage(t, databasePath, "d2", 5*24*time.Hour)
	backdateDealStage(t, databasePath, "d3", 20*24*time.Hour)
	stdout, stderr, code = crm(t, databasePath, "deal", "lose", "d3", "--reason", "passed")
	if stderr != "" || code != 0 {
		t.Fatalf("close rot fixture stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}

	stdout, stderr, code = crm(t, databasePath, "deal", "ls", "--rotting", "--format", "json")
	if stderr != "" || code != 0 {
		t.Fatalf("rotting order stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	rows := decodeDealRows(t, stdout, 2)
	if rows[0].Ref != "d1" || rows[1].Ref != "d2" ||
		rows[0].DaysInStage <= rows[1].DaysInStage {
		t.Fatalf("rotting order = %#v", rows)
	}
	assertNoSidecars(t, databasePath)
}
