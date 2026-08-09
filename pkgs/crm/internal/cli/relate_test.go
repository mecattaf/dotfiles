package cli

import (
	"encoding/json"
	"path/filepath"
	"strings"
	"testing"

	"github.com/mecattaf/crm/internal/model"
)

func TestContactRelateAcceptance(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "crm.db")
	stdout, stderr, code := crm(t, databasePath, "init")
	assertCommandResult(t, stdout, stderr, code, databasePath+"\n", "", 0)

	for _, name := range []string{"Nick Dupont", "Jean Martin"} {
		stdout, stderr, code = crm(t, databasePath, "contact", "add", name)
		if stderr != "" || code != 0 {
			t.Fatalf("contact add %q stdout=%q stderr=%q code=%d", name, stdout, stderr, code)
		}
	}

	stdout, stderr, code = crm(
		t,
		databasePath,
		"contact", "relate", "nick", "jean",
		"--type", "referred by",
		"--note", "Jean made the intro",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("contact relate stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	related := assertCompactContactJSON(t, stdout, 1)[0]
	assertContactLink(
		t,
		related,
		"outgoing",
		"referred by",
		"Jean made the intro",
		"c2",
		"Jean Martin",
	)

	stdout, stderr, code = crm(
		t,
		databasePath,
		"contact", "relate", "nick", "jean", "--type", "referred by",
	)
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"",
		"crm: error: duplicate contact link c1 -> c2 with type \"referred by\"\n",
		4,
	)

	stdout, stderr, code = crm(
		t,
		databasePath,
		"contact", "relate", "nick", "c1", "--type", "peer",
	)
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"",
		"crm: error: cannot relate a contact to itself\n",
		1,
	)

	stdout, stderr, code = crm(
		t,
		databasePath,
		"contact", "show", "jean", "--format", "json",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("far-end contact show stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	shown := assertCompactContactJSON(t, stdout, 1)[0]
	assertContactLink(
		t,
		shown,
		"incoming",
		"referred by",
		"Jean made the intro",
		"c1",
		"Nick Dupont",
	)

	stdout, stderr, code = crm(
		t,
		databasePath,
		"contact", "show", "jean", "--format", "table",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("far-end contact table stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	for _, fragment := range []string{"LINKS", "c1 Nick Dupont", "incoming", "referred by"} {
		if !strings.Contains(stdout, fragment) {
			t.Fatalf("far-end contact table %q omits %q", stdout, fragment)
		}
	}

	stdout, stderr, code = crm(t, databasePath, "context", "jean", "--format", "table")
	if stderr != "" || code != 0 {
		t.Fatalf("far-end context stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	if !strings.Contains(stdout, "Links (1):") ||
		!strings.Contains(stdout, "c1  Nick Dupont  incoming  referred by — Jean made the intro") {
		t.Fatalf("far-end context link = %q", stdout)
	}

	stdout, stderr, code = crm(t, databasePath, "context", "nick", "--format", "json")
	if stderr != "" || code != 0 {
		t.Fatalf("origin context stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	var briefing struct {
		Links []model.ContextLink `json:"links"`
	}
	if err := json.Unmarshal([]byte(stdout), &briefing); err != nil {
		t.Fatalf("decode origin context %q: %v", stdout, err)
	}
	if len(briefing.Links) != 1 || briefing.Links[0].Direction != "outgoing" {
		t.Fatalf("origin context links = %#v", briefing.Links)
	}

	stdout, stderr, code = crm(
		t,
		databasePath,
		"contact", "relate", "jean", "nick", "--type", "mentor",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("reverse contact relate stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}

	stdout, stderr, code = crm(t, databasePath, "contact", "unrelate", "nick", "jean")
	if stderr != "" || code != 0 {
		t.Fatalf("contact unrelate stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	unrelated := assertCompactContactJSON(t, stdout, 1)[0]
	if len(unrelated.Links) != 0 {
		t.Fatalf("unrelate first contact links = %#v, want none", unrelated.Links)
	}

	stdout, stderr, code = crm(
		t,
		databasePath,
		"contact", "show", "jean", "--format", "json",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("show after unrelate stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	if remaining := assertCompactContactJSON(t, stdout, 1)[0].Links; len(remaining) != 0 {
		t.Fatalf("far-end links after unrelate = %#v, want none", remaining)
	}

	assertNoSidecars(t, databasePath)
}

func TestContactRelateValidatesType(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "crm.db")
	stdout, stderr, code := crm(t, databasePath, "init")
	assertCommandResult(t, stdout, stderr, code, databasePath+"\n", "", 0)
	for _, name := range []string{"Nick", "Jean"} {
		stdout, stderr, code = crm(t, databasePath, "contact", "add", name)
		if stderr != "" || code != 0 {
			t.Fatalf("contact add %q stdout=%q stderr=%q code=%d", name, stdout, stderr, code)
		}
	}

	stdout, stderr, code = crm(t, databasePath, "contact", "relate", "nick", "jean")
	assertCommandResult(t, stdout, stderr, code, "", "crm: error: --type is required\n", 1)

	stdout, stderr, code = crm(
		t,
		databasePath,
		"contact", "relate", "nick", "jean", "--type", "   ",
	)
	assertCommandResult(t, stdout, stderr, code, "", "crm: error: --type must not be empty\n", 1)
}

func assertContactLink(
	t *testing.T,
	contact model.Contact,
	direction string,
	linkType string,
	note string,
	counterpartRef string,
	counterpartName string,
) {
	t.Helper()

	if len(contact.Links) != 1 {
		t.Fatalf("contact links = %#v, want one", contact.Links)
	}
	link := contact.Links[0]
	if link.Direction != direction || link.Type != linkType ||
		link.Contact.Reference() != counterpartRef || link.Contact.Name != counterpartName {
		t.Fatalf("contact link = %#v", link)
	}
	if link.Note == nil || *link.Note != note {
		t.Fatalf("contact link note = %v, want %q", link.Note, note)
	}
}
