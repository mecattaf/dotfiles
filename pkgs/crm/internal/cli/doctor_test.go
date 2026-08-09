package cli

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/mecattaf/crm/internal/db"
	"github.com/mecattaf/crm/internal/model"
)

func TestDoctorHealthyReportHasEightStableKeys(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "crm.db")
	stdout, stderr, code := crm(t, databasePath, "init")
	assertCommandResult(t, stdout, stderr, code, databasePath+"\n", "", 0)

	stdout, stderr, code = crm(t, databasePath, "doctor")
	wantJSON := `{"integrity_check":{"ok":true,"detail":"ok"},` +
		`"foreign_key_check":{"ok":true,"detail":"0 violations"},` +
		`"fts":{"ok":true,"tables":[` +
		`{"table":"orgs","ok":true,"content_rows":0,"index_rows":0,"detail":"ok"},` +
		`{"table":"contacts","ok":true,"content_rows":0,"index_rows":0,"detail":"ok"},` +
		`{"table":"interactions","ok":true,"content_rows":0,"index_rows":0,"detail":"ok"},` +
		`{"table":"deals","ok":true,"content_rows":0,"index_rows":0,"detail":"ok"}]},` +
		`"journal_mode":{"ok":true,"detail":"delete"},` +
		`"transcript_paths":{"ok":true,"detail":"0 checked"},` +
		`"deal_stages":{"ok":true,"detail":"all deals consistent"},` +
		`"interaction_links":{"ok":true,"detail":"all interactions linked"},` +
		`"user_version":{"ok":true,"detail":"1"}}` + "\n"
	assertCommandResult(t, stdout, stderr, code, wantJSON, "", 0)
	report := decodeDoctorReport(t, stdout)
	if !report.Healthy() {
		t.Fatalf("healthy doctor report = %#v", report)
	}
	if report.UserVersion.Detail != "1" {
		t.Fatalf("doctor user_version = %#v, want 1", report.UserVersion)
	}
	assertDoctorJSONKeys(t, stdout)
	assertDoctorFTSTables(t, report, map[string][2]int64{
		"orgs":         {0, 0},
		"contacts":     {0, 0},
		"interactions": {0, 0},
		"deals":        {0, 0},
	})

	explicitJSON, explicitErr, explicitCode := crm(
		t,
		databasePath,
		"doctor", "--format", "json",
	)
	assertCommandResult(t, explicitJSON, explicitErr, explicitCode, stdout, "", 0)

	table, tableErr, tableCode := crm(t, databasePath, "doctor", "--format", "table")
	if tableErr != "" || tableCode != 0 {
		t.Fatalf("doctor table stdout=%q stderr=%q code=%d", table, tableErr, tableCode)
	}
	if lineCount := strings.Count(table, "\n"); lineCount != 9 {
		t.Fatalf("doctor table has %d lines, want header plus eight checks:\n%s", lineCount, table)
	}
	for _, check := range doctorCheckKeys() {
		if !strings.Contains(table, check) {
			t.Fatalf("doctor table omits %q:\n%s", check, table)
		}
	}
	assertNoSidecars(t, databasePath)
}

func TestDoctorValidatesFormatBeforeDatabaseAccess(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "missing.db")
	stdout, stderr, code := crm(t, databasePath, "doctor", "--format", "ids")
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"",
		"crm: error: unsupported format \"ids\" (accepted: table|json)\n",
		1,
	)
}

func TestDoctorNamesMissingTranscriptInteraction(t *testing.T) {
	base := t.TempDir()
	databasePath := filepath.Join(base, "crm.db")
	transcriptPath := filepath.Join("transcripts", "2026", "x.md")
	absoluteTranscriptPath := filepath.Join(base, transcriptPath)
	if err := os.MkdirAll(filepath.Dir(absoluteTranscriptPath), 0o700); err != nil {
		t.Fatalf("create transcript directory: %v", err)
	}
	if err := os.WriteFile(absoluteTranscriptPath, []byte("# call\n"), 0o600); err != nil {
		t.Fatalf("write transcript: %v", err)
	}
	runReportFixture(
		t,
		databasePath,
		[]string{"init"},
		[]string{"contact", "add", "Nick"},
		[]string{
			"log", "--kind", "call", "--with", "nick", "--summary", "sync",
			"--transcript", transcriptPath,
		},
	)
	if err := os.Remove(absoluteTranscriptPath); err != nil {
		t.Fatalf("remove transcript fixture: %v", err)
	}

	stdout, stderr, code := crm(t, databasePath, "doctor")
	if code != 1 || stderr != "crm: error: doctor found integrity drift\n" {
		t.Fatalf("doctor stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	report := decodeDoctorReport(t, stdout)
	if report.TranscriptPaths.OK {
		t.Fatalf("transcript check unexpectedly passed: %#v", report.TranscriptPaths)
	}
	for _, fragment := range []string{"i1", transcriptPath} {
		if !strings.Contains(report.TranscriptPaths.Detail, fragment) {
			t.Fatalf("transcript detail %q omits %q", report.TranscriptPaths.Detail, fragment)
		}
	}
	if !report.IntegrityCheck.OK || !report.ForeignKeyCheck.OK || !report.FTS.OK ||
		!report.JournalMode.OK || !report.DealStages.OK ||
		!report.InteractionLinks.OK || !report.UserVersion.OK {
		t.Fatalf("missing transcript affected another check: %#v", report)
	}
}

func TestDoctorRebuildsCorruptedFTS(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "crm.db")
	runReportFixture(
		t,
		databasePath,
		[]string{"init"},
		[]string{"org", "add", "Haystack Org"},
		[]string{"contact", "add", "Needle Person", "--org", "haystack"},
		[]string{"log", "--kind", "note", "--with", "needle", "--summary", "Beacon memo"},
		[]string{"pipeline", "add", "Sales"},
		[]string{"stage", "add", "p1", "sourced"},
		[]string{"deal", "add", "Signal Deal", "--pipeline", "p1", "--org", "haystack"},
	)
	for _, table := range []string{"orgs_fts", "contacts_fts", "interactions_fts", "deals_fts"} {
		execDoctorSQL(
			t,
			databasePath,
			fmt.Sprintf("INSERT INTO %s(%s) VALUES('delete-all')", table, table),
		)
	}

	stdout, stderr, code := crm(t, databasePath, "find", "needle", "--type", "contact")
	assertCommandResult(t, stdout, stderr, code, "[]\n", "", 0)

	stdout, stderr, code = crm(t, databasePath, "doctor")
	if code != 1 || stderr != "crm: error: doctor found integrity drift\n" {
		t.Fatalf("corrupt doctor stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	corruptReport := decodeDoctorReport(t, stdout)
	for _, table := range []string{"orgs", "contacts", "interactions", "deals"} {
		check := findDoctorFTSTable(t, corruptReport, table)
		if check.OK || check.ContentRows != 1 || check.IndexRows != 0 {
			t.Fatalf("corrupt %s FTS check = %#v", table, check)
		}
		if !strings.Contains(check.Detail, "integrity-check failed") {
			t.Fatalf("corrupt %s detail = %q", table, check.Detail)
		}
	}

	stdout, stderr, code = crm(t, databasePath, "doctor", "--rebuild-fts")
	if stderr != "" || code != 0 {
		t.Fatalf("rebuild doctor stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	rebuiltReport := decodeDoctorReport(t, stdout)
	assertDoctorFTSTables(t, rebuiltReport, map[string][2]int64{
		"orgs":         {1, 1},
		"contacts":     {1, 1},
		"interactions": {1, 1},
		"deals":        {1, 1},
	})

	stdout, stderr, code = crm(t, databasePath, "find", "needle", "--type", "contact")
	if stderr != "" || code != 0 || !strings.Contains(stdout, `"ref":"c1"`) {
		t.Fatalf("find after rebuild stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	stdout, stderr, code = crm(t, databasePath, "doctor")
	if stderr != "" || code != 0 || !decodeDoctorReport(t, stdout).Healthy() {
		t.Fatalf("doctor after rebuild stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	assertNoSidecars(t, databasePath)
}

func TestDoctorReportsDealStageFromAnotherPipeline(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "crm.db")
	runReportFixture(
		t,
		databasePath,
		[]string{"init"},
		[]string{"pipeline", "add", "First"},
		[]string{"stage", "add", "p1", "sourced"},
		[]string{"pipeline", "add", "Second"},
		[]string{"stage", "add", "p2", "pitched"},
		[]string{"org", "add", "Kima"},
		[]string{"deal", "add", "Kima ticket", "--pipeline", "p1", "--org", "kima"},
	)
	execDoctorSQL(t, databasePath, "UPDATE deals SET stage_id = 2 WHERE id = 1")

	stdout, stderr, code := crm(t, databasePath, "doctor")
	if code != 1 || stderr != "crm: error: doctor found integrity drift\n" {
		t.Fatalf("doctor stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	check := decodeDoctorReport(t, stdout).DealStages
	if check.OK {
		t.Fatalf("deal-stage check unexpectedly passed: %#v", check)
	}
	for _, fragment := range []string{"d1", "p1", "s2", "p2"} {
		if !strings.Contains(check.Detail, fragment) {
			t.Fatalf("deal-stage detail %q omits %q", check.Detail, fragment)
		}
	}
}

func TestDoctorReportsInteractionWithoutLinks(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "crm.db")
	runReportFixture(
		t,
		databasePath,
		[]string{"init"},
		[]string{"contact", "add", "Nick"},
		[]string{"log", "--kind", "note", "--with", "nick", "--summary", "memo"},
	)
	execDoctorSQL(t, databasePath, "DELETE FROM interaction_people WHERE interaction_id = 1")

	stdout, stderr, code := crm(t, databasePath, "doctor")
	if code != 1 || stderr != "crm: error: doctor found integrity drift\n" {
		t.Fatalf("doctor stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	check := decodeDoctorReport(t, stdout).InteractionLinks
	if check.OK || !strings.Contains(check.Detail, "i1") {
		t.Fatalf("interaction-links check = %#v", check)
	}
}

func TestDoctorReportsForeignKeyViolation(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "crm.db")
	runReportFixture(
		t,
		databasePath,
		[]string{"init"},
		[]string{"contact", "add", "Orphan"},
	)
	execDoctorRawSQL(
		t,
		databasePath,
		"PRAGMA foreign_keys = OFF",
		"UPDATE contacts SET org_id = 999 WHERE id = 1",
	)

	stdout, stderr, code := crm(t, databasePath, "doctor")
	if code != 1 || stderr != "crm: error: doctor found integrity drift\n" {
		t.Fatalf("doctor stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	check := decodeDoctorReport(t, stdout).ForeignKeyCheck
	if check.OK || !strings.Contains(check.Detail, "contacts row 1 references orgs") {
		t.Fatalf("foreign-key check = %#v", check)
	}
}

func TestDoctorReportsUnexpectedUserVersion(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "crm.db")
	stdout, stderr, code := crm(t, databasePath, "init")
	assertCommandResult(t, stdout, stderr, code, databasePath+"\n", "", 0)
	execDoctorSQL(t, databasePath, "PRAGMA user_version = 99")

	stdout, stderr, code = crm(t, databasePath, "doctor")
	if code != 1 || stderr != "crm: error: doctor found integrity drift\n" {
		t.Fatalf("doctor stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	check := decodeDoctorReport(t, stdout).UserVersion
	if check.OK || check.Detail != "got 99, want 1" {
		t.Fatalf("user-version check = %#v", check)
	}
}

func TestDoctorRejectsPersistentWALWithoutNormalizingIt(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "crm.db")
	stdout, stderr, code := crm(t, databasePath, "init")
	assertCommandResult(t, stdout, stderr, code, databasePath+"\n", "", 0)
	if mode := setDoctorJournalMode(t, databasePath, "WAL"); mode != "wal" {
		t.Fatalf("forced journal mode = %q, want wal", mode)
	}

	stdout, stderr, code = crm(t, databasePath, "doctor")
	if code != 1 || stderr != "crm: error: doctor found integrity drift\n" {
		t.Fatalf("WAL doctor stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	report := decodeDoctorReport(t, stdout)
	assertDoctorJSONKeys(t, stdout)
	if report.JournalMode.OK || report.JournalMode.Detail != `got "wal", want "delete"` {
		t.Fatalf("WAL journal check = %#v", report.JournalMode)
	}
	if report.IntegrityCheck.Detail != "not run: unsafe journal mode prevented database open" {
		t.Fatalf("WAL unavailable check = %#v", report.IntegrityCheck)
	}
	if mode := readDoctorJournalMode(t, databasePath); mode != "wal" {
		t.Fatalf("journal mode after failed doctor = %q, want wal", mode)
	}
	if mode := setDoctorJournalMode(t, databasePath, "DELETE"); mode != "delete" {
		t.Fatalf("restored journal mode = %q, want delete", mode)
	}
	assertNoSidecars(t, databasePath)
}

func decodeDoctorReport(t *testing.T, output string) model.DoctorReport {
	t.Helper()

	var report model.DoctorReport
	if err := json.Unmarshal([]byte(output), &report); err != nil {
		t.Fatalf("decode doctor report %q: %v", output, err)
	}

	return report
}

func assertDoctorJSONKeys(t *testing.T, output string) {
	t.Helper()

	var object map[string]json.RawMessage
	if err := json.Unmarshal([]byte(output), &object); err != nil {
		t.Fatalf("decode doctor JSON shape %q: %v", output, err)
	}
	if len(object) != len(doctorCheckKeys()) {
		t.Fatalf("doctor keys = %v, want exactly eight", object)
	}
	for _, key := range doctorCheckKeys() {
		if _, exists := object[key]; !exists {
			t.Fatalf("doctor JSON omits %q: %v", key, object)
		}
	}
}

func doctorCheckKeys() []string {
	return []string{
		"integrity_check",
		"foreign_key_check",
		"fts",
		"journal_mode",
		"transcript_paths",
		"deal_stages",
		"interaction_links",
		"user_version",
	}
}

func assertDoctorFTSTables(
	t *testing.T,
	report model.DoctorReport,
	want map[string][2]int64,
) {
	t.Helper()

	if len(report.FTS.Tables) != len(want) {
		t.Fatalf("FTS table checks = %#v, want %d", report.FTS.Tables, len(want))
	}
	for name, counts := range want {
		check := findDoctorFTSTable(t, report, name)
		if !check.OK || check.ContentRows != counts[0] || check.IndexRows != counts[1] {
			t.Fatalf("FTS table %s = %#v, want counts %v", name, check, counts)
		}
	}
}

func findDoctorFTSTable(
	t *testing.T,
	report model.DoctorReport,
	table string,
) model.DoctorFTSTableCheck {
	t.Helper()

	for _, check := range report.FTS.Tables {
		if check.Table == table {
			return check
		}
	}
	t.Fatalf("doctor FTS report omits %q: %#v", table, report.FTS.Tables)

	return model.DoctorFTSTableCheck{}
}

func execDoctorSQL(t *testing.T, databasePath, statement string, arguments ...any) {
	t.Helper()

	database, err := db.Open(databasePath)
	if err != nil {
		t.Fatalf("open doctor fixture database: %v", err)
	}
	if _, err := database.Exec(statement, arguments...); err != nil {
		_ = database.Close()
		t.Fatalf("execute doctor fixture SQL %q: %v", statement, err)
	}
	if err := database.Close(); err != nil {
		t.Fatalf("close doctor fixture database: %v", err)
	}
}

func execDoctorRawSQL(t *testing.T, databasePath string, statements ...string) {
	t.Helper()

	database, err := sql.Open("sqlite", databasePath)
	if err != nil {
		t.Fatalf("open raw doctor fixture database: %v", err)
	}
	database.SetMaxOpenConns(1)
	for _, statement := range statements {
		if _, err := database.Exec(statement); err != nil {
			_ = database.Close()
			t.Fatalf("execute raw doctor fixture SQL %q: %v", statement, err)
		}
	}
	if err := database.Close(); err != nil {
		t.Fatalf("close raw doctor fixture database: %v", err)
	}
}

func setDoctorJournalMode(t *testing.T, databasePath, requested string) string {
	t.Helper()

	database, err := sql.Open("sqlite", databasePath)
	if err != nil {
		t.Fatalf("open journal fixture database: %v", err)
	}
	database.SetMaxOpenConns(1)
	var mode string
	statement := fmt.Sprintf("PRAGMA journal_mode = %s", requested)
	if err := database.QueryRow(statement).Scan(&mode); err != nil {
		_ = database.Close()
		t.Fatalf("set journal mode %s: %v", requested, err)
	}
	if err := database.Close(); err != nil {
		t.Fatalf("close journal fixture database: %v", err)
	}

	return mode
}

func readDoctorJournalMode(t *testing.T, databasePath string) string {
	t.Helper()

	database, err := sql.Open("sqlite", databasePath)
	if err != nil {
		t.Fatalf("open journal fixture database: %v", err)
	}
	database.SetMaxOpenConns(1)
	var mode string
	if err := database.QueryRow("PRAGMA journal_mode").Scan(&mode); err != nil {
		_ = database.Close()
		t.Fatalf("read journal mode: %v", err)
	}
	if err := database.Close(); err != nil {
		t.Fatalf("close journal fixture database: %v", err)
	}

	return mode
}
