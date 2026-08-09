package cli

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestContextDefaultCapAndAll(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "crm.db")
	stdout, stderr, code := crm(t, databasePath, "init")
	assertCommandResult(t, stdout, stderr, code, databasePath+"\n", "", 0)
	stdout, stderr, code = crm(t, databasePath, "contact", "add", "Nick Dupont")
	if stderr != "" || code != 0 {
		t.Fatalf("contact add stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}

	for index := 1; index <= 21; index++ {
		stdout, stderr, code = crm(
			t,
			databasePath,
			"log", "--with", "nick", "--kind", "note",
			"--date", "2026-07-31", "--summary", fmt.Sprintf("touch %02d", index),
		)
		if stderr != "" || code != 0 {
			t.Fatalf("log %d stdout=%q stderr=%q code=%d", index, stdout, stderr, code)
		}
	}

	stdout, stderr, code = crm(t, databasePath, "context", "nick", "--format", "json")
	if stderr != "" || code != 0 {
		t.Fatalf("default context stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	assertJSONArrayLength(t, decodeContextObject(t, stdout), "timeline", 20)

	stdout, stderr, code = crm(t, databasePath, "context", "nick", "--format", "table")
	if stderr != "" || code != 0 {
		t.Fatalf("default document context stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	if !strings.Contains(stdout, "Timeline (21):") || strings.Count(stdout, "\n  i") != 20 {
		t.Fatalf("default document cap/count = %q", stdout)
	}

	stdout, stderr, code = crm(
		t,
		databasePath,
		"context", "nick", "--all", "--format", "json",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("all context stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	assertJSONArrayLength(t, decodeContextObject(t, stdout), "timeline", 21)
	assertNoSidecars(t, databasePath)
}

func TestContextAcceptance(t *testing.T) {
	temporaryDirectory := t.TempDir()
	databasePath := filepath.Join(temporaryDirectory, "crm.db")
	stdout, stderr, code := crm(t, databasePath, "init")
	assertCommandResult(t, stdout, stderr, code, databasePath+"\n", "", 0)

	stdout, stderr, code = crm(
		t,
		databasePath,
		"org", "add", "Kima Ventures",
		"--category", "vc",
		"--website", "kima.vc",
		"--location", "Paris",
		"--focus", "pre-seed",
		"--context", "Runs a high-tempo seed process.",
		"--hint", "met at DLD",
		"--source", "notes/2026-07-12.md",
		"--detail", "warm introduction",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("org add stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	stdout, stderr, code = crm(
		t,
		databasePath,
		"contact", "add", "Nick Dupont",
		"--org", "kima",
		"--title", "Partner",
		"--email", "nick@kima.vc",
		"--linkedin", "nickdupont",
		"--location", "Paris",
		"--context", "Prefers concise updates.",
		"--hint", "intro from Jean",
		"--source", "notes/2026-07-12.md",
		"--detail", "Jean made the introduction",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("contact add stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}

	transcriptRelative := filepath.Join("transcripts", "2026", "2026-07-30-nick-call.md")
	transcriptAbsolute := filepath.Join(temporaryDirectory, transcriptRelative)
	if err := os.MkdirAll(filepath.Dir(transcriptAbsolute), 0o700); err != nil {
		t.Fatalf("create transcript directory: %v", err)
	}
	if err := os.WriteFile(transcriptAbsolute, []byte("# Call transcript\n"), 0o600); err != nil {
		t.Fatalf("write transcript: %v", err)
	}

	for _, fixture := range []struct {
		date       string
		kind       string
		summary    string
		transcript string
	}{
		{date: "2026-07-28", kind: "note", summary: "first participant-only touch"},
		{date: "2026-07-29", kind: "email", summary: "sent the deck"},
		{
			date:       "2026-07-30",
			kind:       "call",
			summary:    "partner meeting booked",
			transcript: transcriptRelative,
		},
	} {
		arguments := []string{
			"log", "--with", "nick", "--kind", fixture.kind,
			"--date", fixture.date, "--summary", fixture.summary,
		}
		if fixture.transcript != "" {
			arguments = append(arguments, "--transcript", fixture.transcript)
		}
		stdout, stderr, code = crm(t, databasePath, arguments...)
		if stderr != "" || code != 0 {
			t.Fatalf("log %s stdout=%q stderr=%q code=%d", fixture.date, stdout, stderr, code)
		}
	}

	stdout, stderr, code = crm(
		t,
		databasePath,
		"context", "nick", "--limit", "2", "--format", "table",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("contact context stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	if !strings.HasPrefix(stdout, "# Nick Dupont (c1)\n") {
		t.Fatalf("contact context header missing: %q", stdout)
	}
	assertOrderedSubstrings(
		t,
		stdout,
		"Relationship: intro from Jean",
		"Provenance: notes/2026-07-12.md",
		"Email: nick@kima.vc",
		"Dossier:\nPrefers concise updates.",
		"Organization:\n  Kima Ventures (o1)",
		"Timeline (3):",
		"i3  2026-07-30  call  partner meeting booked",
		"Transcript: "+transcriptRelative,
		"i2  2026-07-29  email  sent the deck",
	)
	if strings.Contains(stdout, "i1  ") {
		t.Fatalf("limited context includes oldest interaction: %q", stdout)
	}
	if strings.Contains(stdout, "Links (") || strings.Contains(stdout, "Deals (") {
		t.Fatalf("empty context sections were not omitted: %q", stdout)
	}

	stdout, stderr, code = crm(t, databasePath, "context", "nick", "--format", "json")
	if stderr != "" || code != 0 {
		t.Fatalf("contact JSON context stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	contactBriefing := decodeContextObject(t, stdout)
	assertContextKeys(t, contactBriefing, "contact", "org", "links", "deals", "timeline")
	assertJSONArrayLength(t, contactBriefing, "links", 0)
	assertJSONArrayLength(t, contactBriefing, "deals", 0)
	assertJSONArrayLength(t, contactBriefing, "timeline", 3)

	// None of the interactions above was tagged with --org. The organization
	// timeline must still include all three through Nick's participation.
	stdout, stderr, code = crm(t, databasePath, "context", "kima", "--format", "json")
	if stderr != "" || code != 0 {
		t.Fatalf("org JSON context stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	orgBriefing := decodeContextObject(t, stdout)
	assertContextKeys(t, orgBriefing, "org", "links", "deals", "timeline")
	assertJSONArrayLength(t, orgBriefing, "timeline", 3)

	stdout, stderr, code = crm(t, databasePath, "context", "o1", "--format", "table")
	if stderr != "" || code != 0 {
		t.Fatalf("prefixed org context stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	if !strings.HasPrefix(stdout, "# Kima Ventures (o1)\n") ||
		!strings.Contains(stdout, "Timeline (3):") {
		t.Fatalf("prefixed org document = %q", stdout)
	}

	stdout, stderr, code = crm(t, databasePath, "context", "nick", "--format", "ids")
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"",
		"crm: error: unsupported format \"ids\" (accepted: table|json)\n",
		1,
	)
	assertNoSidecars(t, databasePath)
}

func decodeContextObject(t *testing.T, output string) map[string]json.RawMessage {
	t.Helper()

	if strings.HasPrefix(output, "[") {
		t.Fatalf("context JSON is an array, want one object: %q", output)
	}
	var object map[string]json.RawMessage
	if err := json.Unmarshal([]byte(output), &object); err != nil {
		t.Fatalf("decode context JSON %q: %v", output, err)
	}
	return object
}

func assertContextKeys(t *testing.T, object map[string]json.RawMessage, keys ...string) {
	t.Helper()

	if len(object) != len(keys) {
		t.Fatalf("context keys = %v, want exactly %v", object, keys)
	}
	for _, key := range keys {
		if _, found := object[key]; !found {
			t.Fatalf("context omitted %q: %v", key, object)
		}
	}
}

func assertJSONArrayLength(
	t *testing.T,
	object map[string]json.RawMessage,
	key string,
	want int,
) {
	t.Helper()

	var values []json.RawMessage
	if err := json.Unmarshal(object[key], &values); err != nil {
		t.Fatalf("decode context %s %q: %v", key, object[key], err)
	}
	if len(values) != want {
		t.Fatalf("context %s length = %d, want %d; values=%s", key, len(values), want, object[key])
	}
}

func assertOrderedSubstrings(t *testing.T, value string, parts ...string) {
	t.Helper()

	position := 0
	for _, part := range parts {
		index := strings.Index(value[position:], part)
		if index < 0 {
			t.Fatalf("%q not found in order within %q", part, value)
		}
		position += index + len(part)
	}
}
