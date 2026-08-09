package cli

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func TestScenarioPostCall(t *testing.T) {
	temporaryDirectory := t.TempDir()
	databasePath := filepath.Join(temporaryDirectory, "crm.db")
	stdout, stderr, code := crm(t, databasePath, "init")
	assertCommandResult(t, stdout, stderr, code, databasePath+"\n", "", 0)

	stdout, stderr, code = crm(
		t,
		databasePath,
		"org", "add", "Kima Ventures", "--category", "vc",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("org add stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	stdout, stderr, code = crm(
		t,
		databasePath,
		"contact", "add", "Nick Dupont",
		"--org", "kima",
		"--email", "nick@kima.vc",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("contact add stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}

	transcriptRelative := filepath.Join(
		"transcripts",
		"2026",
		"2026-07-29-nick-dupont-call.md",
	)
	transcriptAbsolute := filepath.Join(temporaryDirectory, transcriptRelative)
	if err := os.MkdirAll(filepath.Dir(transcriptAbsolute), 0o700); err != nil {
		t.Fatalf("create transcript directory: %v", err)
	}
	if err := os.WriteFile(
		transcriptAbsolute,
		[]byte("# Nick Dupont call\n\n[00:00] Nick: Send the deck before Friday.\n"),
		0o600,
	); err != nil {
		t.Fatalf("write transcript: %v", err)
	}

	stdout, stderr, code = crm(
		t,
		databasePath,
		"log",
		"--kind", "call",
		"--with", "nick",
		"--org", "kima",
		"--date", "2026-07-29",
		"--transcript", transcriptRelative,
		"--summary", "wants the deck before Friday",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("post-call log stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	logged := assertCompactInteractionJSON(t, stdout, 1)[0]
	if logged.Ref != "i1" || logged.Kind != "call" || logged.OccurredOn != "2026-07-29" ||
		logged.Summary != "wants the deck before Friday" {
		t.Fatalf("post-call interaction = %#v", logged)
	}
	if !reflect.DeepEqual(logged.ContactIDs, []int64{1}) {
		t.Fatalf("post-call participants = %v, want [1]", logged.ContactIDs)
	}
	assertInt64Pointer(t, "org_id", logged.OrgID, 1)
	assertStringPointer(t, "transcript_path", logged.TranscriptPath, transcriptRelative)

	stdout, stderr, code = crm(t, databasePath, "interaction", "show", "i1")
	if stderr != "" || code != 0 {
		t.Fatalf("post-call show stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	shown := assertCompactInteractionJSON(t, stdout, 1)[0]
	assertStringPointer(t, "shown transcript_path", shown.TranscriptPath, transcriptRelative)

	stdout, stderr, code = crm(t, databasePath, "interaction", "ls", "--with", "nick")
	if stderr != "" || code != 0 {
		t.Fatalf("post-call final list stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	listed := assertCompactInteractionJSON(t, stdout, 1)
	if listed[0].Ref != "i1" || listed[0].Summary != "wants the deck before Friday" {
		t.Fatalf("post-call final state = %#v", listed)
	}
	assertNoSidecars(t, databasePath)
}
