package cli

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/mecattaf/crm/internal/db"
	"github.com/mecattaf/crm/internal/model"
	"github.com/spf13/cobra"
)

func TestLogAcceptanceAndTranscriptPaths(t *testing.T) {
	temporaryDirectory := t.TempDir()
	databasePath := filepath.Join(temporaryDirectory, "crm.db")
	stdout, stderr, code := crm(t, databasePath, "init")
	assertCommandResult(t, stdout, stderr, code, databasePath+"\n", "", 0)

	stdout, stderr, code = crm(t, databasePath, "contact", "add", "Nick Dupont")
	if stderr != "" || code != 0 {
		t.Fatalf("contact add stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}

	stdout, stderr, code = crm(
		t,
		databasePath,
		"log",
		"--with", "nick",
		"--with", "nick",
		"--kind", "call",
		"--summary", "intro",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("canonical log stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	first := assertCompactInteractionJSON(t, stdout, 1)[0]
	if first.Ref != "i1" || first.Kind != "call" || first.Summary != "intro" {
		t.Fatalf("logged interaction = %#v", first)
	}
	if first.OccurredOn != time.Now().Format("2006-01-02") {
		t.Fatalf("default occurred_on = %q, want local today", first.OccurredOn)
	}
	if !reflect.DeepEqual(first.ContactIDs, []int64{1}) {
		t.Fatalf("deduplicated contact ids = %v, want [1]", first.ContactIDs)
	}
	assertInteractionPeopleCount(t, databasePath, first.ID, 1)

	stdout, stderr, code = crm(t, databasePath, "log", "call", "nick", "quick sync")
	if stderr != "" || code != 0 {
		t.Fatalf("positional log stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	sugar := assertCompactInteractionJSON(t, stdout, 1)[0]
	if sugar.Kind != "call" || sugar.Summary != "quick sync" ||
		!reflect.DeepEqual(sugar.ContactIDs, []int64{1}) {
		t.Fatalf("positional sugar = %#v", sugar)
	}

	stdout, stderr, code = crm(
		t,
		databasePath,
		"log", "--kind", "call", "--summary", "orphan",
	)
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"",
		"crm: error: log requires at least one of --with, --org, or --deal\n",
		1,
	)

	stdout, stderr, code = crm(
		t,
		databasePath,
		"log", "--with", "nosuchone", "--kind", "call", "--summary", "x",
	)
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"",
		"crm: error: no contact \"nosuchone\" — try: crm contact add \"nosuchone\"\n",
		2,
	)

	stdout, stderr, code = crm(
		t,
		databasePath,
		"log", "--with", "nick", "--kind", "zoom", "--summary", "x",
	)
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"",
		"crm: error: invalid interaction kind \"zoom\" (accepted: call,meeting,email,message,note)\n",
		1,
	)

	transcriptRelative := filepath.Join("transcripts", "2026", "x.md")
	transcriptAbsolute := filepath.Join(temporaryDirectory, transcriptRelative)
	if err := os.MkdirAll(filepath.Dir(transcriptAbsolute), 0o700); err != nil {
		t.Fatalf("create transcript directory: %v", err)
	}
	if err := os.WriteFile(transcriptAbsolute, []byte("# Transcript\n"), 0o600); err != nil {
		t.Fatalf("write transcript: %v", err)
	}

	for _, transcriptArgument := range []string{transcriptRelative, transcriptAbsolute} {
		stdout, stderr, code = crm(
			t,
			databasePath,
			"log", "--with", "nick", "--kind", "call", "--summary", "x",
			"--transcript", transcriptArgument,
		)
		if stderr != "" || code != 0 {
			t.Fatalf("log transcript %q stdout=%q stderr=%q code=%d", transcriptArgument, stdout, stderr, code)
		}
		interaction := assertCompactInteractionJSON(t, stdout, 1)[0]
		assertStringPointer(t, "transcript_path", interaction.TranscriptPath, transcriptRelative)
	}

	stdout, stderr, code = crm(
		t,
		databasePath,
		"log", "--with", "nick", "--kind", "call", "--summary", "outside",
		"--transcript", "/etc/hosts",
	)
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"",
		fmt.Sprintf(
			"crm: error: transcript path %q is outside transcript base %q\n",
			"/etc/hosts",
			temporaryDirectory,
		),
		1,
	)

	stdout, stderr, code = crm(
		t,
		databasePath,
		"log", "--with", "nick", "--kind", "call", "--summary", "missing",
		"--transcript", "nope.md",
	)
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"",
		"crm: error: transcript path \"nope.md\" not found — create the file and retry\n",
		2,
	)

	missingBody := filepath.Join(temporaryDirectory, "nope.txt")
	stdout, stderr, code = crm(
		t,
		databasePath,
		"log", "--with", "nick", "--kind", "call", "--summary", "missing",
		"--body-file", missingBody,
	)
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"",
		fmt.Sprintf(
			"crm: error: body file %q not found — check the path and retry\n",
			missingBody,
		),
		2,
	)

	bodyPath := filepath.Join(temporaryDirectory, "body.txt")
	if err := os.WriteFile(bodyPath, []byte("long body\nwith detail\n"), 0o600); err != nil {
		t.Fatalf("write body file: %v", err)
	}
	stdout, stderr, code = crm(
		t,
		databasePath,
		"log", "--with", "nick", "--kind", "note", "--summary", "body path",
		"--body-file", bodyPath,
	)
	if stderr != "" || code != 0 {
		t.Fatalf("log body file stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	withBody := assertCompactInteractionJSON(t, stdout, 1)[0]
	assertStringPointer(t, "body", withBody.Body, "long body\nwith detail\n")

	stdout, stderr, code = crmWithStdin(
		t,
		databasePath,
		"body from stdin\n",
		"log", "--with", "nick", "--kind", "note", "--summary", "stdin body",
		"--body-file", "-",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("log stdin body stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	fromStdin := assertCompactInteractionJSON(t, stdout, 1)[0]
	assertStringPointer(t, "body", fromStdin.Body, "body from stdin\n")

	stdout, stderr, code = crm(
		t,
		databasePath,
		"interaction", "ls", "--with", "nick", "--format", "json",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("interaction list stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	listed := assertCompactInteractionJSON(t, stdout, 6)
	for index := 1; index < len(listed); index++ {
		previous := listed[index-1]
		current := listed[index]
		if previous.OccurredOn < current.OccurredOn ||
			(previous.OccurredOn == current.OccurredOn && previous.ID < current.ID) {
			t.Fatalf("interaction list is not occurred_on DESC, id DESC: %#v", listed)
		}
	}

	canonicalShow, stderr, code := crm(t, databasePath, "interaction", "show", "i1")
	if stderr != "" || code != 0 {
		t.Fatalf("interaction show stdout=%q stderr=%q code=%d", canonicalShow, stderr, code)
	}
	stdout, stderr, code = crm(t, databasePath, "i", "show", "i1")
	assertCommandResult(t, stdout, stderr, code, canonicalShow, "", 0)
	stdout, stderr, code = crm(t, databasePath, "interactions", "list", "--limit", "1")
	if stderr != "" || code != 0 || len(assertCompactInteractionJSON(t, stdout, 1)) != 1 {
		t.Fatalf("interaction plural/list alias stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	stdout, stderr, code = crm(t, databasePath, "show", "i1")
	assertCommandResult(t, stdout, stderr, code, canonicalShow, "", 0)

	stdout, stderr, code = crm(
		t,
		databasePath,
		"log", "--deal", "d1", "--kind", "call", "--summary", "deal before deals",
	)
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"",
		"crm: error: no deal \"d1\" — try: crm deal add \"d1\"\n",
		2,
	)

	stdout, stderr, code = crm(t, databasePath, "log", "--help")
	if code != 0 || stderr != "" {
		t.Fatalf("log help stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	if !strings.Contains(stdout, "call,meeting,email,message,note") {
		t.Fatalf("log help does not use the interaction enum: %q", stdout)
	}

	assertNoSidecars(t, databasePath)
}

func TestInteractionEditFullPatchAndLinkInvariant(t *testing.T) {
	temporaryDirectory := t.TempDir()
	databasePath := filepath.Join(temporaryDirectory, "crm.db")
	stdout, stderr, code := crm(t, databasePath, "init")
	assertCommandResult(t, stdout, stderr, code, databasePath+"\n", "", 0)
	stdout, stderr, code = crm(t, databasePath, "org", "add", "Kima Ventures")
	if stderr != "" || code != 0 {
		t.Fatalf("org add stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	for _, name := range []string{"Nick Dupont", "Jean Martin"} {
		stdout, stderr, code = crm(t, databasePath, "contact", "add", name)
		if stderr != "" || code != 0 {
			t.Fatalf("contact add %q stdout=%q stderr=%q code=%d", name, stdout, stderr, code)
		}
	}
	stdout, stderr, code = crm(
		t,
		databasePath,
		"log", "--with", "nick", "--kind", "call", "--summary", "intro",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("initial log stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}

	stdout, stderr, code = crm(t, databasePath, "interaction", "edit", "i1", "--rm-with", "nick")
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"",
		"crm: error: interaction i1 must keep at least one link — patch would leave participants=0, org=none, deal=none\n",
		4,
	)

	transcriptRelative := filepath.Join("transcripts", "2026", "repair.md")
	transcriptAbsolute := filepath.Join(temporaryDirectory, transcriptRelative)
	if err := os.MkdirAll(filepath.Dir(transcriptAbsolute), 0o700); err != nil {
		t.Fatalf("create transcript directory: %v", err)
	}
	if err := os.WriteFile(transcriptAbsolute, []byte("repair transcript\n"), 0o600); err != nil {
		t.Fatalf("write repair transcript: %v", err)
	}
	bodyPath := filepath.Join(temporaryDirectory, "repair-body.txt")
	if err := os.WriteFile(bodyPath, []byte("corrected body\n"), 0o600); err != nil {
		t.Fatalf("write repair body: %v", err)
	}

	stdout, stderr, code = crm(
		t,
		databasePath,
		"interaction", "edit", "i1",
		"--summary", "corrected",
		"--date", "2026-07-30",
		"--kind", "meeting",
		"--transcript", transcriptRelative,
		"--body-file", bodyPath,
		"--add-with", "jean",
		"--add-with", "jean",
		"--rm-with", "nick",
		"--org", "kima",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("full interaction edit stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	updated := assertCompactInteractionJSON(t, stdout, 1)[0]
	if updated.Kind != "meeting" || updated.OccurredOn != "2026-07-30" ||
		updated.Summary != "corrected" {
		t.Fatalf("updated scalar fields = %#v", updated)
	}
	assertStringPointer(t, "body", updated.Body, "corrected body\n")
	assertStringPointer(t, "transcript", updated.TranscriptPath, transcriptRelative)
	assertInt64Pointer(t, "org_id", updated.OrgID, 1)
	if !reflect.DeepEqual(updated.ContactIDs, []int64{2}) {
		t.Fatalf("updated contact ids = %v, want [2]", updated.ContactIDs)
	}

	stdout, stderr, code = crm(
		t,
		databasePath,
		"interaction", "ls", "--org", "kima", "--kind", "meeting", "--format", "json",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("filtered interaction ls stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	filtered := assertCompactInteractionJSON(t, stdout, 1)
	if filtered[0].Ref != "i1" {
		t.Fatalf("filtered interaction = %#v", filtered)
	}

	unchangedAt := updated.UpdatedAt
	stdout, stderr, code = crm(
		t,
		databasePath,
		"interaction", "edit", "i1",
		"--summary", "corrected",
		"--date", "2026-07-30",
		"--kind", "meeting",
		"--transcript", transcriptAbsolute,
		"--body-file", bodyPath,
		"--add-with", "jean",
		"--rm-with", "nick",
		"--org", "kima",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("idempotent interaction edit stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	idempotent := assertCompactInteractionJSON(t, stdout, 1)[0]
	if idempotent.UpdatedAt != unchangedAt {
		t.Fatalf("idempotent edit updated_at = %q, want %q", idempotent.UpdatedAt, unchangedAt)
	}

	stdout, stderr, code = crm(
		t,
		databasePath,
		"interaction", "edit", "i1", "--org", "", "--transcript", "",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("clear interaction links stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	cleared := assertCompactInteractionJSON(t, stdout, 1)[0]
	if cleared.OrgID != nil || cleared.TranscriptPath != nil {
		t.Fatalf("cleared interaction fields = %#v", cleared)
	}
	if !reflect.DeepEqual(cleared.ContactIDs, []int64{2}) {
		t.Fatalf("clear scalar patch changed participants: %v", cleared.ContactIDs)
	}

	stdout, stderr, code = crm(
		t,
		databasePath,
		"interaction", "edit", "i1", "--add-with", "nosuchone",
	)
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"",
		"crm: error: no contact \"nosuchone\" — try: crm contact add \"nosuchone\"\n",
		2,
	)
	stdout, stderr, code = crm(t, databasePath, "interaction", "show", "i1")
	if stderr != "" || code != 0 {
		t.Fatalf("show after failed edit stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	afterFailure := assertCompactInteractionJSON(t, stdout, 1)[0]
	if !reflect.DeepEqual(afterFailure.ContactIDs, []int64{2}) {
		t.Fatalf("failed pre-transaction resolution changed participants: %v", afterFailure.ContactIDs)
	}

	stdout, stderr, code = crm(t, databasePath, "interaction", "ls", "--limit", "-1")
	assertCommandResult(t, stdout, stderr, code, "", "crm: error: limit must not be negative\n", 1)
	stdout, stderr, code = crm(t, databasePath, "interaction", "ls", "--kind", "zoom")
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"",
		"crm: error: invalid interaction kind \"zoom\" (accepted: call,meeting,email,message,note)\n",
		1,
	)

	assertNoSidecars(t, databasePath)
}

func TestInteractionKindFlagsUseSharedHelpAndCompletion(t *testing.T) {
	t.Parallel()

	root := NewRootCmd("test")
	for _, commandPath := range [][]string{
		{"log"},
		{"interaction", "ls"},
		{"interaction", "edit"},
	} {
		command, _, err := root.Find(commandPath)
		if err != nil {
			t.Fatalf("find command %v: %v", commandPath, err)
		}
		kindFlag := command.Flags().Lookup("kind")
		if kindFlag == nil {
			t.Fatalf("command %v has no --kind flag", commandPath)
		}
		wantKinds := strings.Join(model.InteractionKinds, ",")
		if !strings.Contains(kindFlag.Usage, wantKinds) {
			t.Fatalf("command %v kind help %q omits %q", commandPath, kindFlag.Usage, wantKinds)
		}

		complete, found := command.GetFlagCompletionFunc("kind")
		if !found {
			t.Fatalf("command %v has no kind completion", commandPath)
		}
		completed, directive := complete(command, nil, "")
		if !reflect.DeepEqual(completed, model.InteractionKinds) {
			t.Fatalf("command %v completion = %v, want %v", commandPath, completed, model.InteractionKinds)
		}
		if directive != cobra.ShellCompDirectiveNoFileComp {
			t.Fatalf("command %v completion directive = %v", commandPath, directive)
		}
	}
}

func assertCompactInteractionJSON(
	t *testing.T,
	stdout string,
	wantLength int,
) []model.Interaction {
	t.Helper()

	var records []model.Interaction
	if err := json.Unmarshal([]byte(stdout), &records); err != nil {
		t.Fatalf("decode interaction output %q: %v", stdout, err)
	}
	if len(records) != wantLength {
		t.Fatalf("interaction output length = %d, want %d: %#v", len(records), wantLength, records)
	}
	encoded, err := json.Marshal(records)
	if err != nil {
		t.Fatalf("re-encode interaction output: %v", err)
	}
	if got, want := stdout, string(encoded)+"\n"; got != want {
		t.Fatalf("interaction output is not compact stable JSON: got %q want %q", got, want)
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
		if record.ContactIDs == nil {
			t.Fatalf("contact_ids for %s encoded as null, want []", record.Reference())
		}
	}

	return records
}

func assertInteractionPeopleCount(
	t *testing.T,
	databasePath string,
	interactionID int64,
	want int,
) {
	t.Helper()

	database, err := db.Open(databasePath)
	if err != nil {
		t.Fatalf("open database to count interaction people: %v", err)
	}
	defer func() {
		if closeErr := database.Close(); closeErr != nil {
			t.Errorf("close inspected database: %v", closeErr)
		}
	}()

	var got int
	if err := database.QueryRow(
		"SELECT COUNT(*) FROM interaction_people WHERE interaction_id = ?",
		interactionID,
	).Scan(&got); err != nil {
		t.Fatalf("count interaction people: %v", err)
	}
	if got != want {
		t.Fatalf("interaction people count = %d, want %d", got, want)
	}
}
