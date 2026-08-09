package cli

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestScenarioImportTwice(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "crm.db")
	mustCRM(t, databasePath, "init")
	orgsPath := importFixturePath(t, "orgs.csv")
	contactsPath := importFixturePath(t, "contacts.csv")

	importOK(t, databasePath, "orgs", orgsPath, "test")
	importOK(t, databasePath, "contacts", contactsPath, "test")
	wantOrgCount := importTableCount(t, databasePath, "orgs")
	wantContactCount := importTableCount(t, databasePath, "contacts")

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
		"",
		"Imported: 0, updated: 0, skipped: 2, errors: 0\n",
		0,
	)
	stdout, stderr, code = crm(
		t,
		databasePath,
		"import", "contacts", contactsPath, "--source", "test",
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
	if got := importTableCount(t, databasePath, "orgs"); got != wantOrgCount {
		t.Fatalf("org count after second run = %d, want %d", got, wantOrgCount)
	}
	if got := importTableCount(t, databasePath, "contacts"); got != wantContactCount {
		t.Fatalf("contact count after second run = %d, want %d", got, wantContactCount)
	}

	updatePath := filepath.Join(t.TempDir(), "contacts-update.csv")
	updateCSV := "name,email,job_title\nAnaïs Martin,anais@elan.example,Managing Partner\n"
	if err := os.WriteFile(updatePath, []byte(updateCSV), 0o600); err != nil {
		t.Fatalf("write update fixture: %v", err)
	}
	stdout, stderr, code = crm(
		t,
		databasePath,
		"import", "contacts", updatePath,
		"--source", "refresh", "--update",
	)
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"",
		"Imported: 0, updated: 1, skipped: 0, errors: 0\n",
		0,
	)
	contacts := importContacts(t, databasePath)
	if contacts[0].JobTitle == nil || *contacts[0].JobTitle != "Managing Partner" {
		t.Fatalf("updated contact = %#v", contacts[0])
	}
	if contacts[0].ProvenanceSources == nil ||
		!strings.HasSuffix(*contacts[0].ProvenanceSources, " || refresh") {
		t.Fatalf("updated provenance = %v, want appended refresh", contacts[0].ProvenanceSources)
	}
}
