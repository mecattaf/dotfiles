package cli

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/mecattaf/crm/internal/db"
	"github.com/mecattaf/crm/internal/model"
)

func TestOrgAddAndListAcceptance(t *testing.T) {
	temporaryDirectory := t.TempDir()
	databasePath := filepath.Join(temporaryDirectory, "crm.db")
	stdout, stderr, code := crm(t, databasePath, "init")
	assertCommandResult(t, stdout, stderr, code, databasePath+"\n", "", 0)

	stdout, stderr, code = crm(
		t,
		databasePath,
		"org",
		"add",
		"Kima Ventures",
		"--category",
		"vc",
		"--website",
		"kima.vc",
		"--source",
		"n.md",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("org add stderr = %q, code = %d", stderr, code)
	}
	added := assertCompactOrgJSON(t, stdout, 1)
	if added[0].Ref != "o1" || added[0].Name != "Kima Ventures" ||
		added[0].NameNorm != "kima ventures" {
		t.Fatalf("added organization identity = %#v", added[0])
	}
	assertStringPointer(t, "category", added[0].Category, "vc")
	assertStringPointer(t, "website", added[0].Website, "kima.vc")
	assertStringPointer(t, "source", added[0].ProvenanceSources, "n.md")
	if added[0].LinkedIn != nil || added[0].Location != nil || added[0].ArchivedAt != nil {
		t.Fatalf("optional fields were not explicit nulls: %#v", added[0])
	}

	stdout, stderr, code = crm(t, databasePath, "org", "add", "Kima Ventures")
	wantDuplicate := "crm: error: duplicate org name \"Kima Ventures\" — " +
		"already on org o1 (Kima Ventures)\n"
	assertCommandResult(t, stdout, stderr, code, "", wantDuplicate, 4)

	stdout, stderr, code = crm(t, databasePath, "org", "add", "Léger Capital")
	if stderr != "" || code != 0 {
		t.Fatalf("accented org add stderr = %q, code = %d", stderr, code)
	}
	accented := assertCompactOrgJSON(t, stdout, 1)
	if accented[0].Ref != "o2" || accented[0].NameNorm != "leger capital" {
		t.Fatalf("accented organization = %#v", accented[0])
	}
	assertStoredNameNorm(t, databasePath, "Léger Capital", "leger capital")

	stdout, stderr, code = crm(t, databasePath, "org", "ls", "--format", "bogus")
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"",
		"crm: error: unsupported format \"bogus\" (accepted: table|json|ids)\n",
		1,
	)

	stdout, stderr, code = crm(t, databasePath, "org", "ls", "--category", "vc")
	if stderr != "" || code != 0 {
		t.Fatalf("org ls stderr = %q, code = %d", stderr, code)
	}
	listed := assertCompactOrgJSON(t, stdout, 1)
	if listed[0].Ref != "o1" {
		t.Fatalf("category listing = %#v", listed)
	}

	stdout, stderr, code = crm(t, databasePath, "org", "ls", "--all", "--limit", "1")
	if stderr != "" || code != 0 {
		t.Fatalf("org ls --all --limit stderr = %q, code = %d", stderr, code)
	}
	limited := assertCompactOrgJSON(t, stdout, 1)
	if limited[0].Ref != "o1" {
		t.Fatalf("limited listing = %#v", limited)
	}

	assertNoSidecars(t, databasePath)
}

func TestOrgListEmptyJSONAndIDs(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "crm.db")
	stdout, stderr, code := crm(t, databasePath, "init")
	assertCommandResult(t, stdout, stderr, code, databasePath+"\n", "", 0)

	stdout, stderr, code = crm(t, databasePath, "org", "ls", "--format", "json")
	assertCommandResult(t, stdout, stderr, code, "[]\n", "", 0)

	stdout, stderr, code = crm(t, databasePath, "org", "add", "Kima Ventures")
	if stderr != "" || code != 0 {
		t.Fatalf("org add stderr = %q, code = %d", stderr, code)
	}
	assertCompactOrgJSON(t, stdout, 1)

	stdout, stderr, code = crm(t, databasePath, "org", "ls", "--format", "ids")
	assertCommandResult(t, stdout, stderr, code, "o1\n", "", 0)
}

func TestOrgListMissingDatabaseGuardEndToEnd(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "absent.db")
	stdout, stderr, code := crm(t, databasePath, "org", "ls")
	want := fmt.Sprintf("crm: error: no database at %s (run 'crm init')\n", databasePath)
	assertCommandResult(t, stdout, stderr, code, "", want, 2)
	if _, err := os.Stat(databasePath); !os.IsNotExist(err) {
		t.Fatalf("reader created absent database or stat failed: %v", err)
	}
}

func TestOrgAddAllFlagsAndProvenanceJoining(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "crm.db")
	stdout, stderr, code := crm(t, databasePath, "init")
	assertCommandResult(t, stdout, stderr, code, databasePath+"\n", "", 0)

	stdout, stderr, code = crm(
		t,
		databasePath,
		"org", "add", "Complete Org",
		"--category", "partner",
		"--website", "https://www.EXAMPLE.COM/Labs?tracking=yes",
		"--linkedin", "https://linkedin.com/company/complete-org/",
		"--location", " New   York ",
		"--focus", "infrastructure",
		"--context", "rolling dossier",
		"--hint", "met at dinner",
		"--source", "one.md",
		"--source", "two.md",
		"--detail", "line 1",
		"--detail", "line 2",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("full org add stderr = %q, code = %d", stderr, code)
	}
	records := assertCompactOrgJSON(t, stdout, 1)
	record := records[0]
	assertStringPointer(t, "category", record.Category, "partner")
	assertStringPointer(t, "website", record.Website, "example.com/Labs")
	assertStringPointer(t, "linkedin", record.LinkedIn, "complete-org")
	assertStringPointer(t, "location", record.Location, "New York")
	assertStringPointer(t, "focus", record.Focus, "infrastructure")
	assertStringPointer(t, "context", record.Context, "rolling dossier")
	assertStringPointer(t, "hint", record.RelationshipHint, "met at dinner")
	assertStringPointer(t, "sources", record.ProvenanceSources, "one.md || two.md")
	assertStringPointer(t, "details", record.ProvenanceDetails, "line 1 || line 2")
}

func assertCompactOrgJSON(t *testing.T, stdout string, wantLength int) []model.Org {
	t.Helper()

	var records []model.Org
	if err := json.Unmarshal([]byte(stdout), &records); err != nil {
		t.Fatalf("decode org output %q: %v", stdout, err)
	}
	if len(records) != wantLength {
		t.Fatalf("org output length = %d, want %d: %#v", len(records), wantLength, records)
	}
	encoded, err := json.Marshal(records)
	if err != nil {
		t.Fatalf("re-encode org output: %v", err)
	}
	if got, want := stdout, string(encoded)+"\n"; got != want {
		t.Fatalf("org output is not compact stable JSON: got %q want %q", got, want)
	}
	for _, record := range records {
		for field, value := range map[string]string{
			"created_at": record.CreatedAt,
			"updated_at": record.UpdatedAt,
		} {
			if _, err := time.Parse(time.RFC3339, value); err != nil {
				t.Fatalf("%s = %q, want RFC3339: %v", field, value, err)
			}
		}
	}

	return records
}

func assertStoredNameNorm(t *testing.T, databasePath string, name string, want string) {
	t.Helper()

	database, err := db.Open(databasePath)
	if err != nil {
		t.Fatalf("open database to inspect name_norm: %v", err)
	}
	defer func() {
		if closeErr := database.Close(); closeErr != nil {
			t.Errorf("close inspected database: %v", closeErr)
		}
	}()

	var got string
	if err := database.QueryRow("SELECT name_norm FROM orgs WHERE name = ?", name).Scan(&got); err != nil {
		t.Fatalf("read stored name_norm: %v", err)
	}
	if got != want {
		t.Fatalf("stored name_norm = %q, want %q", got, want)
	}
}

func assertStringPointer(t *testing.T, field string, got *string, want string) {
	t.Helper()

	if got == nil || *got != want {
		t.Fatalf("%s = %v, want %q", field, got, want)
	}
}

func TestOrgTableWritesOnlyDataToStdout(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "crm.db")
	stdout, stderr, code := crm(t, databasePath, "init")
	assertCommandResult(t, stdout, stderr, code, databasePath+"\n", "", 0)
	stdout, stderr, code = crm(t, databasePath, "org", "add", "Léger", "--format", "table")
	assertCommandResult(t, stdout, stderr, code, "REF  NAME\no1   Léger\n", "", 0)

	stdout, stderr, code = crm(t, databasePath, "org", "ls", "--format", "table")
	if code != 0 || stderr != "" || !strings.HasPrefix(stdout, "REF  NAME\n") {
		t.Fatalf("table listing stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
}

func TestOrgShowResolutionAcceptance(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "crm.db")
	stdout, stderr, code := crm(t, databasePath, "init")
	assertCommandResult(t, stdout, stderr, code, databasePath+"\n", "", 0)

	for _, name := range []string{"Kima Ventures", "Léger Capital", "Kima Partners"} {
		stdout, stderr, code = crm(t, databasePath, "org", "add", name)
		if stderr != "" || code != 0 {
			t.Fatalf("org add %q stdout=%q stderr=%q code=%d", name, stdout, stderr, code)
		}
		assertCompactOrgJSON(t, stdout, 1)
	}

	stdout, stderr, code = crm(t, databasePath, "org", "show", "leger")
	if stderr != "" || code != 0 {
		t.Fatalf("accent-normalized show stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	shown := assertCompactOrgJSON(t, stdout, 1)
	if shown[0].Ref != "o2" || shown[0].Name != "Léger Capital" {
		t.Fatalf("accent-normalized show = %#v", shown)
	}

	stdoutByPrefix, stderr, code := crm(t, databasePath, "org", "show", "o1")
	if stderr != "" || code != 0 {
		t.Fatalf("prefixed show stdout=%q stderr=%q code=%d", stdoutByPrefix, stderr, code)
	}
	stdoutByID, stderr, code := crm(t, databasePath, "org", "show", "1")
	assertCommandResult(t, stdoutByID, stderr, code, stdoutByPrefix, "", 0)

	stdout, stderr, code = crm(t, databasePath, "org", "show", "kima")
	if stdout != "" || code != 3 {
		t.Fatalf("ambiguous show stdout=%q stderr=%q code=%d, want empty/3", stdout, stderr, code)
	}
	if !strings.HasPrefix(stderr, "crm: error: ambiguous org \"kima\":\n") ||
		!strings.Contains(stderr, "\no1  Kima Ventures\n") ||
		!strings.Contains(stderr, "\no3  Kima Partners\n") {
		t.Fatalf("ambiguous stderr lacks pasteable candidates: %q", stderr)
	}

	stdout, stderr, code = crm(t, databasePath, "org", "show", "nosuchorg")
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"",
		"crm: error: no org \"nosuchorg\" — try: crm find nosuchorg\n",
		2,
	)

	stdout, stderr, code = crm(t, databasePath, "org", "show", "c1")
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"",
		"crm: error: ref \"c1\" names a contact, not an org\n",
		2,
	)
}

func TestOrgShowArchivedReachabilityUsesOnlyIDRungs(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "crm.db")
	stdout, stderr, code := crm(t, databasePath, "init")
	assertCommandResult(t, stdout, stderr, code, databasePath+"\n", "", 0)
	stdout, stderr, code = crm(t, databasePath, "org", "add", "Archive Only")
	if stderr != "" || code != 0 {
		t.Fatalf("org add stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}

	database, err := db.Open(databasePath)
	if err != nil {
		t.Fatalf("open database to archive fixture: %v", err)
	}
	if _, err := database.Exec(
		"UPDATE orgs SET archived_at = ? WHERE id = 1",
		"2026-07-31T12:00:00Z",
	); err != nil {
		_ = database.Close()
		t.Fatalf("archive fixture: %v", err)
	}
	if err := database.Close(); err != nil {
		t.Fatalf("close archived fixture database: %v", err)
	}

	stdout, stderr, code = crm(t, databasePath, "org", "show", "o1")
	if stderr != "" || code != 0 {
		t.Fatalf("show archived id stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	shown := assertCompactOrgJSON(t, stdout, 1)
	if shown[0].ArchivedAt == nil {
		t.Fatalf("show archived id returned live record: %#v", shown[0])
	}

	stdout, stderr, code = crm(t, databasePath, "org", "show", "archive")
	if stdout != "" || code != 2 || !strings.Contains(stderr, "try: crm find archive") {
		t.Fatalf("show archived name stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
}

func TestOrgEditTruePatchAcceptance(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "crm.db")
	stdout, stderr, code := crm(t, databasePath, "init")
	assertCommandResult(t, stdout, stderr, code, databasePath+"\n", "", 0)
	stdout, stderr, code = crm(
		t,
		databasePath,
		"org", "add", "Kima Ventures",
		"--website", "kima.vc",
		"--context", "prior dossier",
		"--source", "n.md",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("org add stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}

	stdout, stderr, code = crm(t, databasePath, "org", "edit", "o1", "--focus", "pre-seed")
	if stderr != "" || code != 0 {
		t.Fatalf("first edit stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	firstEdit := assertCompactOrgJSON(t, stdout, 1)[0]
	assertStringPointer(t, "focus", firstEdit.Focus, "pre-seed")
	assertStringPointer(t, "website", firstEdit.Website, "kima.vc")

	stdout, stderr, code = crm(t, databasePath, "org", "edit", "o1", "--focus", "pre-seed")
	if stderr != "" || code != 0 {
		t.Fatalf("idempotent edit stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	secondEdit := assertCompactOrgJSON(t, stdout, 1)[0]
	if secondEdit.UpdatedAt != firstEdit.UpdatedAt {
		t.Fatalf("idempotent edit updated_at = %q, want %q", secondEdit.UpdatedAt, firstEdit.UpdatedAt)
	}

	stdout, stderr, code = crm(t, databasePath, "org", "edit", "o1", "--website", "")
	if stderr != "" || code != 0 {
		t.Fatalf("clear website stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	cleared := assertCompactOrgJSON(t, stdout, 1)[0]
	if cleared.Website != nil {
		t.Fatalf("cleared website = %q, want JSON null", *cleared.Website)
	}

	stdout, stderr, code = crm(
		t,
		databasePath,
		"org", "edit", "o1",
		"--context-append", "new intelligence",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("append context stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	appended := assertCompactOrgJSON(t, stdout, 1)[0]
	assertStringPointer(t, "context", appended.Context, "prior dossier\n\nnew intelligence")

	stdout, stderr, code = crm(t, databasePath, "org", "edit", "o1", "--source", "b.md")
	if stderr != "" || code != 0 {
		t.Fatalf("append source stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	provenance := assertCompactOrgJSON(t, stdout, 1)[0]
	assertStringPointer(t, "sources", provenance.ProvenanceSources, "n.md || b.md")

	stdout, stderr, code = crm(t, databasePath, "org", "edit", "o1")
	if stderr != "" || code != 0 {
		t.Fatalf("empty edit stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	noPatch := assertCompactOrgJSON(t, stdout, 1)[0]
	if noPatch.UpdatedAt != provenance.UpdatedAt {
		t.Fatalf("empty edit updated_at = %q, want %q", noPatch.UpdatedAt, provenance.UpdatedAt)
	}
}
