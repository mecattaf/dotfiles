package cli

import (
	"path/filepath"
	"strings"
	"testing"

	"github.com/mecattaf/crm/internal/db"
)

func TestContactMergeAcceptanceAndAmbiguousRefRefusal(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "crm.db")
	stdout, stderr, code := crm(t, databasePath, "init")
	assertCommandResult(t, stdout, stderr, code, databasePath+"\n", "", 0)

	stdout, stderr, code = crm(
		t,
		databasePath,
		"contact", "add", "Winner Person",
		"--phone", "+33123456789",
		"--context", "winner dossier",
		"--source", "winner.md",
		"--detail", "winner detail",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("winner add stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	stdout, stderr, code = crm(
		t,
		databasePath,
		"contact", "add", "Loser Person",
		"--title", "Partner",
		"--email", "loser@example.com",
		"--location", "Paris",
		"--context", "loser dossier",
		"--hint", "introduced by Ana",
		"--source", "loser.md",
		"--detail", "loser detail",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("loser add stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}

	stdout, stderr, code = crm(t, databasePath, "pipeline", "add", "Merge pipeline")
	if stderr != "" || code != 0 {
		t.Fatalf("pipeline add stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	stdout, stderr, code = crm(t, databasePath, "stage", "add", "p1", "open")
	if stderr != "" || code != 0 {
		t.Fatalf("stage add stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	stdout, stderr, code = crm(
		t,
		databasePath,
		"deal", "add", "Loser deal", "--pipeline", "p1", "--contact", "c2",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("deal add stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	stdout, stderr, code = crm(
		t,
		databasePath,
		"log", "--with", "c1", "--with", "c2", "--kind", "note", "--summary", "both duplicates",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("interaction add stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}

	stdout, stderr, code = crm(t, databasePath, "contact", "merge", "c1", "c2")
	if stderr != "" || code != 0 {
		t.Fatalf("contact merge stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	merged := assertCompactContactJSON(t, stdout, 1)[0]
	if merged.Reference() != "c1" || merged.Name != "Winner Person" {
		t.Fatalf("merged survivor identity = %#v", merged)
	}
	assertStringPointer(t, "winner phone", merged.Phone, "+33123456789")
	assertStringPointer(t, "loser title", merged.JobTitle, "Partner")
	assertStringPointer(t, "loser email", merged.Email, "loser@example.com")
	assertStringPointer(t, "loser location", merged.Location, "Paris")
	assertStringPointer(t, "winner context", merged.Context, "winner dossier")
	assertStringPointer(t, "loser hint", merged.RelationshipHint, "introduced by Ana")
	assertStringPointer(t, "merged provenance sources", merged.ProvenanceSources, "winner.md || loser.md")
	assertStringPointer(t, "merged provenance details", merged.ProvenanceDetails, "winner detail || loser detail")

	stdout, stderr, code = crm(t, databasePath, "contact", "show", "c2")
	if stderr != "" || code != 0 {
		t.Fatalf("show archived loser stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	loser := assertCompactContactJSON(t, stdout, 1)[0]
	if loser.ArchivedAt == nil {
		t.Fatalf("merged loser archived_at = nil: %#v", loser)
	}

	database, err := db.Open(databasePath)
	if err != nil {
		t.Fatalf("open merged contact database: %v", err)
	}
	var winnerPeople int
	var loserPeople int
	if err := database.QueryRow("SELECT COUNT(*) FROM interaction_people WHERE contact_id = 1").Scan(&winnerPeople); err != nil {
		_ = database.Close()
		t.Fatalf("count winner participants: %v", err)
	}
	if err := database.QueryRow("SELECT COUNT(*) FROM interaction_people WHERE contact_id = 2").Scan(&loserPeople); err != nil {
		_ = database.Close()
		t.Fatalf("count loser participants: %v", err)
	}
	var dealContactID int64
	if err := database.QueryRow("SELECT contact_id FROM deals WHERE id = 1").Scan(&dealContactID); err != nil {
		_ = database.Close()
		t.Fatalf("read repointed deal contact: %v", err)
	}
	if err := database.Close(); err != nil {
		t.Fatalf("close merged contact database: %v", err)
	}
	if winnerPeople != 1 || loserPeople != 0 || dealContactID != 1 {
		t.Fatalf(
			"repointed contact refs: winner people=%d loser people=%d deal contact=%d",
			winnerPeople,
			loserPeople,
			dealContactID,
		)
	}

	for _, name := range []string{"Amb Alpha", "Amb Beta"} {
		stdout, stderr, code = crm(t, databasePath, "contact", "add", name)
		if stderr != "" || code != 0 {
			t.Fatalf("ambiguous fixture %q stdout=%q stderr=%q code=%d", name, stdout, stderr, code)
		}
	}
	stdout, stderr, code = crm(t, databasePath, "contact", "merge", "c1", "amb")
	if stdout != "" || code != 3 || !strings.Contains(stderr, "ambiguous contact \"amb\"") ||
		!strings.Contains(stderr, "c3") || !strings.Contains(stderr, "c4") {
		t.Fatalf("ambiguous merge stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}

	assertNoSidecars(t, databasePath)
}

func TestOrgMergeCoalescesScalarsAndRepointsEveryReference(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "crm.db")
	stdout, stderr, code := crm(t, databasePath, "init")
	assertCommandResult(t, stdout, stderr, code, databasePath+"\n", "", 0)

	stdout, stderr, code = crm(
		t,
		databasePath,
		"org", "add", "Winner Org",
		"--category", "customer",
		"--context", "winner dossier",
		"--source", "winner-org.md",
		"--detail", "winner org detail",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("winner org add stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	stdout, stderr, code = crm(
		t,
		databasePath,
		"org", "add", "Loser Org",
		"--website", "loser.example",
		"--location", "London",
		"--focus", "enterprise",
		"--context", "loser dossier",
		"--source", "loser-org.md",
		"--detail", "loser org detail",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("loser org add stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	stdout, stderr, code = crm(t, databasePath, "contact", "add", "Attached Person", "--org", "o2")
	if stderr != "" || code != 0 {
		t.Fatalf("attached contact add stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	stdout, stderr, code = crm(t, databasePath, "pipeline", "add", "Org merge pipeline")
	if stderr != "" || code != 0 {
		t.Fatalf("org pipeline add stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	stdout, stderr, code = crm(t, databasePath, "stage", "add", "p1", "open")
	if stderr != "" || code != 0 {
		t.Fatalf("org stage add stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	stdout, stderr, code = crm(
		t,
		databasePath,
		"deal", "add", "Org loser deal", "--pipeline", "p1", "--org", "o2",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("org deal add stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	stdout, stderr, code = crm(
		t,
		databasePath,
		"log", "--org", "o2", "--kind", "note", "--summary", "loser org note",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("org interaction add stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}

	stdout, stderr, code = crm(t, databasePath, "org", "merge", "o1", "o2")
	if stderr != "" || code != 0 {
		t.Fatalf("org merge stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	merged := assertCompactOrgJSON(t, stdout, 1)[0]
	if merged.Reference() != "o1" || merged.Name != "Winner Org" {
		t.Fatalf("merged org survivor identity = %#v", merged)
	}
	assertStringPointer(t, "winner category", merged.Category, "customer")
	assertStringPointer(t, "loser website", merged.Website, "loser.example")
	assertStringPointer(t, "loser location", merged.Location, "London")
	assertStringPointer(t, "loser focus", merged.Focus, "enterprise")
	assertStringPointer(t, "winner dossier", merged.Context, "winner dossier")
	assertStringPointer(t, "merged org sources", merged.ProvenanceSources, "winner-org.md || loser-org.md")
	assertStringPointer(t, "merged org details", merged.ProvenanceDetails, "winner org detail || loser org detail")

	stdout, stderr, code = crm(t, databasePath, "org", "show", "o2")
	if stderr != "" || code != 0 {
		t.Fatalf("show archived org loser stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	if archived := assertCompactOrgJSON(t, stdout, 1)[0]; archived.ArchivedAt == nil {
		t.Fatalf("merged org loser archived_at = nil: %#v", archived)
	}

	database, err := db.Open(databasePath)
	if err != nil {
		t.Fatalf("open merged org database: %v", err)
	}
	for _, query := range []string{
		"SELECT org_id FROM contacts WHERE id = 1",
		"SELECT org_id FROM interactions WHERE id = 1",
		"SELECT org_id FROM deals WHERE id = 1",
	} {
		var orgID int64
		if err := database.QueryRow(query).Scan(&orgID); err != nil {
			_ = database.Close()
			t.Fatalf("read repointed org reference with %q: %v", query, err)
		}
		if orgID != 1 {
			_ = database.Close()
			t.Fatalf("repointed org reference with %q = o%d, want o1", query, orgID)
		}
	}
	if err := database.Close(); err != nil {
		t.Fatalf("close merged org database: %v", err)
	}

	assertNoSidecars(t, databasePath)
}
