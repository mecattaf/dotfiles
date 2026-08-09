package cli

import (
	"encoding/json"
	"path/filepath"
	"strings"
	"testing"
)

type findJSONRow struct {
	Type   string  `json:"type"`
	Ref    string  `json:"ref"`
	Name   string  `json:"name"`
	Detail string  `json:"detail"`
	Rank   float64 `json:"rank"`
}

func TestFindAcceptance(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "crm.db")
	stdout, stderr, code := crm(t, databasePath, "init")
	assertCommandResult(t, stdout, stderr, code, databasePath+"\n", "", 0)

	stdout, stderr, code = crm(
		t,
		databasePath,
		"org", "add", "Kima Ventures",
		"--category", "vc",
		"--location", "Paris",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("org add stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	stdout, stderr, code = crm(
		t,
		databasePath,
		"contact", "add", "Nick Dupont",
		"--org", "kima",
		"--email", "nick@kima.vc",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("contact add stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	stdout, stderr, code = crm(
		t,
		databasePath,
		"log",
		"--kind", "meeting",
		"--with", "nick",
		"--org", "kima",
		"--date", "2026-07-30",
		"--summary", "reviewed the Kima dataroom with Nick",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("log stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}

	stdout, stderr, code = crm(t, databasePath, "find", "nick kima", "--format", "json")
	if stderr != "" || code != 0 {
		t.Fatalf("find phrase stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	rows := decodeFindRows(t, stdout)
	if len(rows) < 2 {
		t.Fatalf("find phrase rows = %#v, want mixed results", rows)
	}
	assertFindJSONShape(t, stdout)

	stdout, stderr, code = crm(t, databasePath, "find", "nick@kima.vc")
	if stderr != "" || code != 0 {
		t.Fatalf("find email stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	rows = decodeFindRows(t, stdout)
	if len(rows) != 1 || rows[0].Ref != "c1" {
		t.Fatalf("find email rows = %#v, want c1", rows)
	}

	stdout, stderr, code = crm(
		t,
		databasePath,
		"find", "dataroom", "--type", "interaction", "--limit", "5",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("find interaction stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	rows = decodeFindRows(t, stdout)
	if len(rows) != 1 || rows[0].Type != "interaction" || rows[0].Ref != "i1" {
		t.Fatalf("find interaction rows = %#v", rows)
	}
	if rows[0].Detail != "2026-07-30 · meeting" {
		t.Fatalf("interaction detail = %q", rows[0].Detail)
	}

	stdout, stderr, code = crm(t, databasePath, "find", "kima", "--format", "ids")
	if stderr != "" || code != 0 {
		t.Fatalf("find ids stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	refs := strings.Fields(stdout)
	if len(refs) < 3 || !containsString(refs, "o1") ||
		!containsString(refs, "c1") || !containsString(refs, "i1") {
		t.Fatalf("find ids = %q, want mixed o1/c1/i1 refs", stdout)
	}

	stdout, stderr, code = crm(t, databasePath, "find", "kima", "--format", "csv")
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"",
		"crm: error: unsupported format \"csv\" (accepted: table|json|ids)\n",
		1,
	)

	stdout, stderr, code = crm(t, databasePath, "find", "kima", "--limit", "1")
	if stderr != "" || code != 0 {
		t.Fatalf("limited find stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	if rows = decodeFindRows(t, stdout); len(rows) != 1 {
		t.Fatalf("limited find rows = %#v, want one", rows)
	}

	assertNoSidecars(t, databasePath)
}

func TestFindValidatesTypeBeforeDatabaseAccess(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "missing.db")
	stdout, stderr, code := crm(
		t,
		databasePath,
		"find", "dataroom", "--type", "meeting",
	)
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"",
		"crm: error: invalid find type \"meeting\" (accepted: org,contact,interaction,deal)\n",
		1,
	)
}

func TestFindInteractionEditRemovesOldFTSTerm(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "crm.db")
	stdout, stderr, code := crm(t, databasePath, "init")
	assertCommandResult(t, stdout, stderr, code, databasePath+"\n", "", 0)
	stdout, stderr, code = crm(t, databasePath, "contact", "add", "Nick")
	if stderr != "" || code != 0 {
		t.Fatalf("contact add stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	stdout, stderr, code = crm(
		t,
		databasePath,
		"log", "--kind", "note", "--with", "nick", "--summary", "legacyterm memo",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("log stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	stdout, stderr, code = crm(
		t,
		databasePath,
		"interaction", "edit", "i1", "--summary", "replacementterm memo",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("interaction edit stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}

	stdout, stderr, code = crm(
		t,
		databasePath,
		"find", "legacyterm", "--type", "interaction",
	)
	assertCommandResult(t, stdout, stderr, code, "[]\n", "", 0)
	stdout, stderr, code = crm(
		t,
		databasePath,
		"find", "replacementterm", "--type", "interaction",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("find replacement stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	rows := decodeFindRows(t, stdout)
	if len(rows) != 1 || rows[0].Ref != "i1" {
		t.Fatalf("replacement rows = %#v", rows)
	}
}

func decodeFindRows(t *testing.T, output string) []findJSONRow {
	t.Helper()

	var rows []findJSONRow
	if err := json.Unmarshal([]byte(output), &rows); err != nil {
		t.Fatalf("decode find JSON %q: %v", output, err)
	}
	return rows
}

func assertFindJSONShape(t *testing.T, output string) {
	t.Helper()

	var rows []map[string]json.RawMessage
	if err := json.Unmarshal([]byte(output), &rows); err != nil {
		t.Fatalf("decode find shape %q: %v", output, err)
	}
	for index, row := range rows {
		if len(row) != 5 {
			t.Fatalf("find row %d keys = %v, want exactly five", index, row)
		}
		for _, key := range []string{"type", "ref", "name", "detail", "rank"} {
			if _, exists := row[key]; !exists {
				t.Fatalf("find row %d omits %q: %v", index, key, row)
			}
		}
	}
}

func containsString(values []string, wanted string) bool {
	for _, value := range values {
		if value == wanted {
			return true
		}
	}
	return false
}
