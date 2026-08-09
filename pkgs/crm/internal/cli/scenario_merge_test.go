package cli

import (
	"path/filepath"
	"testing"

	"github.com/mecattaf/crm/internal/db"
	"github.com/mecattaf/crm/internal/model"
)

func TestScenarioMerge(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "crm.db")
	stdout, stderr, code := crm(t, databasePath, "init")
	assertCommandResult(t, stdout, stderr, code, databasePath+"\n", "", 0)

	for _, name := range []string{"Marta Legrand", "Martha Legrand", "Third Person"} {
		stdout, stderr, code = crm(t, databasePath, "contact", "add", name)
		if stderr != "" || code != 0 {
			t.Fatalf("add %q stdout=%q stderr=%q code=%d", name, stdout, stderr, code)
		}
	}

	links := [][]string{
		{"c1", "c2", "duplicate"},
		{"c2", "c1", "duplicate"},
		{"c1", "c3", "colleague"},
		{"c2", "c3", "colleague"},
		{"c3", "c2", "mentor"},
	}
	for _, link := range links {
		stdout, stderr, code = crm(
			t,
			databasePath,
			"contact", "relate", link[0], link[1], "--type", link[2],
		)
		if stderr != "" || code != 0 {
			t.Fatalf("relate %v stdout=%q stderr=%q code=%d", link, stdout, stderr, code)
		}
	}

	stdout, stderr, code = crm(t, databasePath, "contact", "merge", "c1", "c2")
	if stderr != "" || code != 0 {
		t.Fatalf("persona merge stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	survivor := assertCompactContactJSON(t, stdout, 1)[0]
	assertScenarioMergedLinks(t, survivor)

	stdout, stderr, code = crm(t, databasePath, "contact", "show", "c2", "--format", "json")
	if stderr != "" || code != 0 {
		t.Fatalf("show persona loser stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	absorbed := assertCompactContactJSON(t, stdout, 1)[0]
	if absorbed.ArchivedAt == nil || len(absorbed.Links) != 0 {
		t.Fatalf("absorbed contact = %#v, want archived with no links", absorbed)
	}

	stdout, stderr, code = crm(t, databasePath, "contact", "show", "c3", "--format", "json")
	if stderr != "" || code != 0 {
		t.Fatalf("show third contact stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	third := assertCompactContactJSON(t, stdout, 1)[0]
	if len(third.Links) != 2 {
		t.Fatalf("third contact links = %#v, want two links to survivor", third.Links)
	}
	for _, link := range third.Links {
		if link.Contact.Reference() != "c1" {
			t.Fatalf("third contact retains absorbed ref: %#v", third.Links)
		}
	}

	database, err := db.Open(databasePath)
	if err != nil {
		t.Fatalf("open persona database: %v", err)
	}
	var linkCount int
	var loserReferences int
	var selfLinks int
	if err := database.QueryRow("SELECT COUNT(*) FROM contact_links").Scan(&linkCount); err != nil {
		_ = database.Close()
		t.Fatalf("count merged links: %v", err)
	}
	if err := database.QueryRow(
		"SELECT COUNT(*) FROM contact_links WHERE contact_id = 2 OR related_contact_id = 2",
	).Scan(&loserReferences); err != nil {
		_ = database.Close()
		t.Fatalf("count absorbed link references: %v", err)
	}
	if err := database.QueryRow(
		"SELECT COUNT(*) FROM contact_links WHERE contact_id = related_contact_id",
	).Scan(&selfLinks); err != nil {
		_ = database.Close()
		t.Fatalf("count self links: %v", err)
	}
	if err := database.Close(); err != nil {
		t.Fatalf("close persona database: %v", err)
	}
	if linkCount != 2 || loserReferences != 0 || selfLinks != 0 {
		t.Fatalf(
			"final link graph count=%d loser_refs=%d self_links=%d",
			linkCount,
			loserReferences,
			selfLinks,
		)
	}

	assertNoSidecars(t, databasePath)
}

func assertScenarioMergedLinks(t *testing.T, contact model.Contact) {
	t.Helper()
	if contact.Reference() != "c1" || len(contact.Links) != 2 {
		t.Fatalf("merged survivor = %#v, want c1 with two links", contact)
	}
	want := map[string]string{
		"outgoing:colleague": "c3",
		"incoming:mentor":    "c3",
	}
	for _, link := range contact.Links {
		key := link.Direction + ":" + link.Type
		if want[key] != link.Contact.Reference() {
			t.Fatalf("unexpected merged link %#v; want=%v", link, want)
		}
		delete(want, key)
	}
	if len(want) != 0 {
		t.Fatalf("merged links omit %v", want)
	}
}
