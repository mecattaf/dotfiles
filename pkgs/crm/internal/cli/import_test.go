package cli

import (
	"encoding/csv"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/mecattaf/crm/internal/db"
	"github.com/mecattaf/crm/internal/model"
)

func TestImportRequiresSourceAndReportsMissingInput(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "crm.db")
	mustCRM(t, databasePath, "init")
	orgsPath := importFixturePath(t, "orgs.csv")

	stdout, stderr, code := crm(t, databasePath, "import", "orgs", orgsPath)
	assertCommandResult(t, stdout, stderr, code, "", "crm: error: --source is required\n", 1)

	missingPath := filepath.Join(t.TempDir(), "nope.csv")
	stdout, stderr, code = crm(
		t,
		databasePath,
		"import", "orgs", missingPath, "--source", "test",
	)
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"",
		"crm: error: import file "+strconvQuote(missingPath)+" not found — check the path and retry\n",
		2,
	)
}

func TestImportOrgsIsIdempotentAndCreatesRefsOnStdout(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "crm.db")
	mustCRM(t, databasePath, "init")
	orgsPath := importFixturePath(t, "orgs.csv")

	stdout, stderr, code := crm(
		t,
		databasePath,
		"import", "orgs", orgsPath, "--source", "test",
	)
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"o1\no2\n",
		"Imported: 2, updated: 0, skipped: 0, errors: 0\n",
		0,
	)
	organizations := importOrganizations(t, databasePath)
	if len(organizations) != 2 || organizations[0].Name != "Élan Ventures" {
		t.Fatalf("imported organizations = %#v", organizations)
	}
	assertStringPointer(t, "first org provenance", organizations[0].ProvenanceSources, "legacy-export || test")
	assertStringPointer(t, "second org provenance", organizations[1].ProvenanceSources, "test")

	stdout, stderr, code = crm(
		t,
		databasePath,
		"import", "orgs", orgsPath, "--source", "test",
	)
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"",
		"Imported: 0, updated: 0, skipped: 2, errors: 0\n",
		0,
	)
	if got := importTableCount(t, databasePath, "orgs"); got != 2 {
		t.Fatalf("org count after second import = %d, want 2", got)
	}
}

func TestImportContactsDryRunPrintsPlanWithoutWriting(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "crm.db")
	mustCRM(t, databasePath, "init")
	importOK(t, databasePath, "orgs", importFixturePath(t, "orgs.csv"), "test")

	stdout, stderr, code := crm(
		t,
		databasePath,
		"import", "contacts", importFixturePath(t, "contacts.csv"),
		"--source", "test", "--dry-run",
	)
	if code != 0 || stderr != "Imported: 2, updated: 0, skipped: 0, errors: 0\n" {
		t.Fatalf("dry-run stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	for _, planned := range []string{
		"create contact c1 \"Anaïs Martin\"",
		"create contact c2 \"Björn Keller\"",
	} {
		if !strings.Contains(stdout, planned+"\n") {
			t.Fatalf("dry-run plan %q omits %q", stdout, planned)
		}
	}
	if got := importTableCount(t, databasePath, "contacts"); got != 0 {
		t.Fatalf("contact count after dry-run = %d, want 0", got)
	}
}

func TestImportSkipErrorsUsesSavepointsAndWritesRejects(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "crm.db")
	mustCRM(t, databasePath, "init")
	badPath := importFixturePath(t, "bad.csv")

	stdout, stderr, code := crm(
		t,
		databasePath,
		"import", "contacts", badPath, "--source", "test",
	)
	if stdout != "" || code != 1 || !strings.Contains(stderr, "line 3: contact name must not be empty") {
		t.Fatalf("fatal import stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	if got := importTableCount(t, databasePath, "contacts"); got != 0 {
		t.Fatalf("fatal file import committed %d contacts, want 0", got)
	}

	rejectPath := filepath.Join(t.TempDir(), "rejects.csv")
	stdout, stderr, code = crm(
		t,
		databasePath,
		"import", "contacts", badPath,
		"--source", "test", "--skip-errors", "--reject-file", rejectPath,
	)
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"c1\nc2\n",
		"Imported: 2, updated: 0, skipped: 1, errors: 1\n",
		0,
	)
	if got := importTableCount(t, databasePath, "contacts"); got != 2 {
		t.Fatalf("contact count after skip-errors = %d, want 2", got)
	}

	rejectBytes, err := os.ReadFile(rejectPath)
	if err != nil {
		t.Fatalf("read reject file: %v", err)
	}
	rejects, err := csv.NewReader(strings.NewReader(string(rejectBytes))).ReadAll()
	if err != nil {
		t.Fatalf("parse reject file %q: %v", rejectBytes, err)
	}
	if len(rejects) != 2 || len(rejects[0]) < 2 || rejects[0][0] != "line" ||
		rejects[0][1] != "error" || rejects[1][0] != "3" ||
		!strings.Contains(rejects[1][1], "contact name must not be empty") {
		t.Fatalf("reject rows = %#v", rejects)
	}
}

func TestImportContactUnknownOrgRemedyAndCreateMissing(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "crm.db")
	mustCRM(t, databasePath, "init")
	unknownPath := importFixturePath(t, "unknown-org.csv")

	stdout, stderr, code := crm(
		t,
		databasePath,
		"import", "contacts", unknownPath, "--source", "test",
	)
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"",
		"crm: error: line 2: no org \"Unlisted Partners\" — try: crm org add \"Unlisted Partners\" --source \"test\"\n",
		2,
	)
	if got := importTableCount(t, databasePath, "orgs"); got != 0 {
		t.Fatalf("unknown-org failure created %d orgs, want 0", got)
	}

	stdout, stderr, code = crm(
		t,
		databasePath,
		"import", "contacts", unknownPath,
		"--source", "test", "--create-missing",
	)
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"o1\nc1\n",
		"Auto-created org o1 \"Unlisted Partners\"\n"+
			"Imported: 1, updated: 0, skipped: 0, errors: 0\n",
		0,
	)
	organizations := importOrganizations(t, databasePath)
	if len(organizations) != 1 {
		t.Fatalf("auto-created organizations = %#v", organizations)
	}
	assertStringPointer(
		t,
		"auto-created provenance",
		organizations[0].ProvenanceSources,
		"auto-created by crm import",
	)
	contacts := importContacts(t, databasePath)
	if len(contacts) != 1 || contacts[0].OrgID == nil || *contacts[0].OrgID != organizations[0].ID {
		t.Fatalf("imported contacts = %#v; organizations = %#v", contacts, organizations)
	}
	assertStringPointer(t, "contact provenance", contacts[0].ProvenanceSources, "test")
}

func TestExportImportRoundtripPreservesOrgsAndContacts(t *testing.T) {
	sourceDB := filepath.Join(t.TempDir(), "crm.db")
	mustCRM(t, sourceDB, "init")
	mustCRM(
		t,
		sourceDB,
		"org", "add", `Léger, "Labs"`,
		"--category", "vc || advisor",
		"--context", "First line\nSecond, \"quoted\"",
		"--source", "roundtrip",
		"--source", "notes/β.md",
		"--detail", "Renée said hello",
	)
	mustCRM(t, sourceDB, "org", "add", "Null Fields", "--source", "roundtrip")
	mustCRM(
		t,
		sourceDB,
		"contact", "add", "Anaïs 東",
		"--org", "o1",
		"--title", "Partner, Europe",
		"--email", "anais@example.com",
		"--context", "Line one\nLine two",
		"--source", "roundtrip",
		"--source", "notes/γ.md",
		"--detail", "Unicode ✓",
	)
	mustCRM(t, sourceDB, "contact", "add", "Null Contact", "--source", "roundtrip")
	mustCRM(t, sourceDB, "contact", "archive", "c2")
	mustCRM(t, sourceDB, "org", "archive", "o2")

	orgCSV := mustCRM(t, sourceDB, "export", "orgs", "--format", "csv")
	contactCSV := mustCRM(t, sourceDB, "export", "contacts", "--format", "csv")
	exportDirectory := t.TempDir()
	orgPath := filepath.Join(exportDirectory, "orgs.csv")
	contactPath := filepath.Join(exportDirectory, "contacts.csv")
	if err := os.WriteFile(orgPath, []byte(orgCSV), 0o600); err != nil {
		t.Fatalf("write org roundtrip export: %v", err)
	}
	if err := os.WriteFile(contactPath, []byte(contactCSV), 0o600); err != nil {
		t.Fatalf("write contact roundtrip export: %v", err)
	}

	targetDB := filepath.Join(t.TempDir(), "crm.db")
	mustCRM(t, targetDB, "init")
	importOK(t, targetDB, "orgs", orgPath, "roundtrip")
	importOK(t, targetDB, "contacts", contactPath, "roundtrip")

	for _, entity := range []string{"orgs", "contacts"} {
		want := mustCRM(t, sourceDB, "export", entity, "--format", "json")
		got := mustCRM(t, targetDB, "export", entity, "--format", "json")
		if got != want {
			t.Fatalf("%s export/import roundtrip mismatch:\n got: %s\nwant: %s", entity, got, want)
		}
	}
	assertNoSidecars(t, targetDB)
}

func importFixturePath(t *testing.T, name string) string {
	t.Helper()
	projectRoot, err := findProjectRoot()
	if err != nil {
		t.Fatalf("find project root: %v", err)
	}

	return filepath.Join(projectRoot, "testdata", "import", name)
}

func importOK(t *testing.T, databasePath, entity, path, source string, extra ...string) string {
	t.Helper()
	arguments := []string{"import", entity, path, "--source", source}
	arguments = append(arguments, extra...)
	stdout, stderr, code := crm(t, databasePath, arguments...)
	if code != 0 || !strings.HasSuffix(stderr, "errors: 0\n") {
		t.Fatalf("crm %s stdout=%q stderr=%q code=%d", strings.Join(arguments, " "), stdout, stderr, code)
	}

	return stdout
}

func importTableCount(t *testing.T, databasePath, table string) int {
	t.Helper()
	allowed := map[string]bool{"orgs": true, "contacts": true}
	if !allowed[table] {
		t.Fatalf("unsupported count table %q", table)
	}
	database, err := db.Open(databasePath)
	if err != nil {
		t.Fatalf("open import database: %v", err)
	}
	defer func() {
		if closeErr := database.Close(); closeErr != nil {
			t.Errorf("close import database: %v", closeErr)
		}
	}()
	var count int
	if err := database.QueryRow("SELECT COUNT(*) FROM " + table).Scan(&count); err != nil {
		t.Fatalf("count %s: %v", table, err)
	}

	return count
}

func importOrganizations(t *testing.T, databasePath string) []model.Org {
	t.Helper()
	stdout := mustCRM(t, databasePath, "org", "ls", "--all", "--format", "json")
	var organizations []model.Org
	if err := json.Unmarshal([]byte(stdout), &organizations); err != nil {
		t.Fatalf("decode imported organizations %q: %v", stdout, err)
	}

	return organizations
}

func importContacts(t *testing.T, databasePath string) []model.Contact {
	t.Helper()
	stdout := mustCRM(t, databasePath, "contact", "ls", "--all", "--format", "json")
	var contacts []model.Contact
	if err := json.Unmarshal([]byte(stdout), &contacts); err != nil {
		t.Fatalf("decode imported contacts %q: %v", stdout, err)
	}

	return contacts
}

func strconvQuote(value string) string {
	encoded, _ := json.Marshal(value)

	return string(encoded)
}
