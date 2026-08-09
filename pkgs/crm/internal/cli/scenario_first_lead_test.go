package cli

import (
	"path/filepath"
	"strings"
	"testing"
)

func TestScenarioFirstLead(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "crm.db")
	stdout, stderr, code := crm(t, databasePath, "init")
	assertCommandResult(t, stdout, stderr, code, databasePath+"\n", "", 0)

	stdout, stderr, code = crm(
		t,
		databasePath,
		"org", "add", "Kima Ventures",
		"--category", "vc",
		"--hint", "met at DLD",
		"--source", "notes/first-lead.md",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("first-lead org add stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	stdout, stderr, code = crm(
		t,
		databasePath,
		"contact", "add", "Nick Dupont",
		"--org", "kima",
		"--title", "Partner",
		"--email", "nick@kima.vc",
		"--hint", "intro from Jean",
		"--source", "notes/first-lead.md",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("first-lead contact add stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	stdout, stderr, code = crm(
		t,
		databasePath,
		"log", "--kind", "call", "--with", "nick",
		"--date", "2026-07-29", "--summary", "asked for the deck",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("first-lead log stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}

	stdout, stderr, code = crm(t, databasePath, "context", "nick", "--format", "table")
	if stderr != "" || code != 0 {
		t.Fatalf("first-lead contact context stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	if !strings.HasPrefix(stdout, "# Nick Dupont (c1)\n") ||
		!strings.Contains(stdout, "Timeline (1):") ||
		!strings.Contains(stdout, "i1  2026-07-29  call  asked for the deck") {
		t.Fatalf("first-lead contact briefing = %q", stdout)
	}

	stdout, stderr, code = crm(t, databasePath, "context", "o1", "--format", "json")
	if stderr != "" || code != 0 {
		t.Fatalf("first-lead org context stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	orgBriefing := decodeContextObject(t, stdout)
	assertJSONArrayLength(t, orgBriefing, "timeline", 1)
	assertNoSidecars(t, databasePath)
}
