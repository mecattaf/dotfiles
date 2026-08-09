package cli

import (
	"encoding/json"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/mecattaf/crm/internal/model"
)

func TestContactAcceptance(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "crm.db")
	stdout, stderr, code := crm(t, databasePath, "init")
	assertCommandResult(t, stdout, stderr, code, databasePath+"\n", "", 0)

	stdout, stderr, code = crm(t, databasePath, "org", "add", "Kima Ventures")
	if stderr != "" || code != 0 {
		t.Fatalf("org add stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	assertCompactOrgJSON(t, stdout, 1)

	stdout, stderr, code = crm(
		t,
		databasePath,
		"contact", "add", "Nick Dupont",
		"--org", "kima",
		"--email", "Nick@Kima.VC",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("contact add stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	nickOutput := stdout
	nick := assertCompactContactJSON(t, stdout, 1)[0]
	if nick.Ref != "c1" || nick.Name != "Nick Dupont" || nick.NameNorm != "nick dupont" {
		t.Fatalf("Nick identity = %#v", nick)
	}
	assertInt64Pointer(t, "org_id", nick.OrgID, 1)
	assertStringPointer(t, "email", nick.Email, "nick@kima.vc")

	stdout, stderr, code = crm(t, databasePath, "contact", "add", "X", "--org", "nosuchorg")
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"",
		"crm: error: no org \"nosuchorg\" — try: crm org add \"nosuchorg\"\n",
		2,
	)

	stdoutByContact, stderr, code := crm(t, databasePath, "contact", "show", "nick@kima.vc")
	assertCommandResult(t, stdoutByContact, stderr, code, nickOutput, "", 0)

	stdout, stderr, code = crm(
		t,
		databasePath,
		"contact", "add", "Other Guy",
		"--email", "nick@kima.vc",
	)
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"",
		"crm: error: duplicate email \"nick@kima.vc\" — already on contact 1 (Nick Dupont)\n",
		4,
	)

	stdout, stderr, code = crm(
		t,
		databasePath,
		"contact", "edit", "nick",
		"--email", "NICK@KIMA.VC",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("idempotent contact edit stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	unchanged := assertCompactContactJSON(t, stdout, 1)[0]
	if unchanged.UpdatedAt != nick.UpdatedAt {
		t.Fatalf("no-op edit updated_at = %q, want %q", unchanged.UpdatedAt, nick.UpdatedAt)
	}

	stdout, stderr, code = crm(
		t,
		databasePath,
		"contact", "add", "Ana",
		"--linkedin", "https://linkedin.com/in/ana-x/",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("LinkedIn contact add stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	ana := assertCompactContactJSON(t, stdout, 1)[0]
	assertStringPointer(t, "linkedin", ana.LinkedIn, "ana-x")

	stdoutByHandle, stderr, code := crm(t, databasePath, "contact", "show", "ana-x")
	if stderr != "" || code != 0 {
		t.Fatalf("LinkedIn show stdout=%q stderr=%q code=%d", stdoutByHandle, stderr, code)
	}
	if shown := assertCompactContactJSON(t, stdoutByHandle, 1)[0]; shown.Ref != "c2" {
		t.Fatalf("LinkedIn show = %#v, want c2", shown)
	}

	stdout, stderr, code = crm(t, databasePath, "show", "c1")
	assertCommandResult(t, stdout, stderr, code, stdoutByContact, "", 0)

	stdoutByOrg, stderr, code := crm(t, databasePath, "org", "show", "o1")
	if stderr != "" || code != 0 {
		t.Fatalf("org show stdout=%q stderr=%q code=%d", stdoutByOrg, stderr, code)
	}
	stdout, stderr, code = crm(t, databasePath, "show", "o1")
	assertCommandResult(t, stdout, stderr, code, stdoutByOrg, "", 0)

	stdout, stderr, code = crm(t, databasePath, "show", "nick")
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"",
		"crm: error: show requires a prefixed ref (for example c12 or o4)\n",
		1,
	)

	stdout, stderr, code = crm(t, databasePath, "contact", "show", "o1")
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"",
		"crm: error: ref \"o1\" names an org, not a contact\n",
		2,
	)

	stdout, stderr, code = crm(t, databasePath, "c", "ls", "--org", "kima", "--format", "ids")
	assertCommandResult(t, stdout, stderr, code, "c1\n", "", 0)

	stdout, stderr, code = crm(t, databasePath, "contacts", "list", "--org", "o1", "--format", "ids")
	assertCommandResult(t, stdout, stderr, code, "c1\n", "", 0)

	stdout, stderr, code = crm(t, databasePath, "o", "show", "o1")
	assertCommandResult(t, stdout, stderr, code, stdoutByOrg, "", 0)
	stdout, stderr, code = crm(t, databasePath, "orgs", "show", "o1")
	assertCommandResult(t, stdout, stderr, code, stdoutByOrg, "", 0)

	assertNoSidecars(t, databasePath)
}

func TestContactAddAndEditAllFlags(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "crm.db")
	stdout, stderr, code := crm(t, databasePath, "init")
	assertCommandResult(t, stdout, stderr, code, databasePath+"\n", "", 0)
	for _, name := range []string{"Kima Ventures", "Acme Labs"} {
		stdout, stderr, code = crm(t, databasePath, "org", "add", name)
		if stderr != "" || code != 0 {
			t.Fatalf("org add %q stdout=%q stderr=%q code=%d", name, stdout, stderr, code)
		}
	}

	stdout, stderr, code = crm(
		t,
		databasePath,
		"contact", "add", "Complete Contact",
		"--org", "kima",
		"--title", "Partner",
		"--email", "Complete@Example.COM",
		"--phone", "+33 6 12 34 56 78",
		"--linkedin", "https://www.linkedin.com/in/complete-contact/",
		"--location", " Paris,   France ",
		"--context", "rolling dossier",
		"--hint", "intro from Jean",
		"--source", "one.md",
		"--source", "two.md",
		"--detail", "line 1",
		"--detail", "line 2",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("full contact add stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	created := assertCompactContactJSON(t, stdout, 1)[0]
	assertInt64Pointer(t, "org_id", created.OrgID, 1)
	assertStringPointer(t, "job_title", created.JobTitle, "Partner")
	assertStringPointer(t, "email", created.Email, "complete@example.com")
	assertStringPointer(t, "phone", created.Phone, "+33612345678")
	assertStringPointer(t, "linkedin", created.LinkedIn, "complete-contact")
	assertStringPointer(t, "location", created.Location, "Paris, France")
	assertStringPointer(t, "context", created.Context, "rolling dossier")
	assertStringPointer(t, "hint", created.RelationshipHint, "intro from Jean")
	assertStringPointer(t, "sources", created.ProvenanceSources, "one.md || two.md")
	assertStringPointer(t, "details", created.ProvenanceDetails, "line 1 || line 2")

	stdout, stderr, code = crm(
		t,
		databasePath,
		"contact", "edit", "c1",
		"--org", "acme",
		"--title", "Principal",
		"--email", "other@EXAMPLE.com",
		"--phone", "(212) 555-1234",
		"--linkedin", "@other-contact",
		"--location", " New   York ",
		"--context-append", "prefers WhatsApp",
		"--hint", "met at DLD",
		"--source", "three.md",
		"--detail", "line 3",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("full contact edit stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	updated := assertCompactContactJSON(t, stdout, 1)[0]
	assertInt64Pointer(t, "org_id", updated.OrgID, 2)
	assertStringPointer(t, "job_title", updated.JobTitle, "Principal")
	assertStringPointer(t, "email", updated.Email, "other@example.com")
	assertStringPointer(t, "phone", updated.Phone, "2125551234")
	assertStringPointer(t, "linkedin", updated.LinkedIn, "other-contact")
	assertStringPointer(t, "location", updated.Location, "New York")
	assertStringPointer(t, "context", updated.Context, "rolling dossier\n\nprefers WhatsApp")
	assertStringPointer(t, "hint", updated.RelationshipHint, "met at DLD")
	assertStringPointer(t, "sources", updated.ProvenanceSources, "one.md || two.md || three.md")
	assertStringPointer(t, "details", updated.ProvenanceDetails, "line 1 || line 2 || line 3")

	stdout, stderr, code = crm(
		t,
		databasePath,
		"contact", "edit", "c1",
		"--org", "",
		"--title", "",
		"--email", "",
		"--phone", "",
		"--linkedin", "",
		"--location", "",
		"--context", "",
		"--hint", "",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("clear contact fields stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	cleared := assertCompactContactJSON(t, stdout, 1)[0]
	if cleared.OrgID != nil || cleared.JobTitle != nil || cleared.Email != nil ||
		cleared.Phone != nil || cleared.LinkedIn != nil || cleared.Location != nil ||
		cleared.Context != nil || cleared.RelationshipHint != nil {
		t.Fatalf("cleared contact fields = %#v, want explicit nulls", cleared)
	}
	if cleared.ProvenanceSources == nil || cleared.ProvenanceDetails == nil {
		t.Fatalf("clearing scalar fields removed provenance: %#v", cleared)
	}
}

func TestContactListRejectsBadInputs(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "crm.db")
	stdout, stderr, code := crm(t, databasePath, "init")
	assertCommandResult(t, stdout, stderr, code, databasePath+"\n", "", 0)

	stdout, stderr, code = crm(t, databasePath, "contact", "ls", "--limit", "-1")
	assertCommandResult(t, stdout, stderr, code, "", "crm: error: limit must not be negative\n", 1)

	stdout, stderr, code = crm(t, databasePath, "contact", "ls", "--format", "csv")
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"",
		"crm: error: unsupported format \"csv\" (accepted: table|json|ids)\n",
		1,
	)

	stdout, stderr, code = crm(t, databasePath, "contact", "ls", "--format", "json")
	assertCommandResult(t, stdout, stderr, code, "[]\n", "", 0)
}

func assertCompactContactJSON(t *testing.T, stdout string, wantLength int) []model.Contact {
	t.Helper()

	var records []model.Contact
	if err := json.Unmarshal([]byte(stdout), &records); err != nil {
		t.Fatalf("decode contact output %q: %v", stdout, err)
	}
	if len(records) != wantLength {
		t.Fatalf("contact output length = %d, want %d: %#v", len(records), wantLength, records)
	}
	encoded, err := json.Marshal(records)
	if err != nil {
		t.Fatalf("re-encode contact output: %v", err)
	}
	if got, want := stdout, string(encoded)+"\n"; got != want {
		t.Fatalf("contact output is not compact stable JSON: got %q want %q", got, want)
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

func assertInt64Pointer(t *testing.T, field string, got *int64, want int64) {
	t.Helper()

	if got == nil || *got != want {
		t.Fatalf("%s = %v, want %d", field, got, want)
	}
}

func assertContainsLines(t *testing.T, text string, lines ...string) {
	t.Helper()

	for _, line := range lines {
		if !strings.Contains(text, line) {
			t.Fatalf("text %q does not contain line %q", text, line)
		}
	}
}
