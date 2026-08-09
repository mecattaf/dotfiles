package cli

import (
	"encoding/json"
	"errors"
	"path/filepath"
	"strings"
	"testing"

	"github.com/mecattaf/crm/internal/model"
	"github.com/mecattaf/crm/internal/resolve"
)

func TestDeleteRequiresConfirmationNonInteractive(t *testing.T) {
	databasePath := newDeleteDatabase(t)
	mustCRM(t, databasePath, "contact", "add", "Nick Dupont")

	stdout, stderr, code := crmWithStdin(
		t,
		databasePath,
		"",
		"contact",
		"delete",
		"nick",
	)
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"",
		"crm: error: refusing to delete without --confirm (non-interactive)\n",
		1,
	)

	stdout, stderr, code = crm(t, databasePath, "contact", "show", "c1")
	if stderr != "" || code != 0 || decodeLifecycleRecord(t, stdout).Ref != "c1" {
		t.Fatalf("refused delete changed contact: stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
}

func TestDeletePipedRefsAreConfirmedPerInvocation(t *testing.T) {
	databasePath := newDeleteDatabase(t)
	mustCRM(t, databasePath, "contact", "add", "Nick Dupont")
	mustCRM(t, databasePath, "contact", "add", "Ana Martin")

	stdout := mustCRM(t, databasePath, "contact", "ls", "--format", "ids")
	refs := strings.Fields(stdout)
	if len(refs) != 2 {
		t.Fatalf("contact ids = %q, want two refs", stdout)
	}
	for _, ref := range refs {
		deleteStdout, deleteStderr, code := crmWithStdin(
			t,
			databasePath,
			"",
			"contact",
			"delete",
			ref,
		)
		assertCommandResult(
			t,
			deleteStdout,
			deleteStderr,
			code,
			"",
			"crm: error: refusing to delete without --confirm (non-interactive)\n",
			1,
		)
	}

	stdout = mustCRM(t, databasePath, "contact", "ls", "--format", "json")
	var contacts []json.RawMessage
	if err := json.Unmarshal([]byte(stdout), &contacts); err != nil {
		t.Fatalf("decode contacts after refused deletes: %v", err)
	}
	if len(contacts) != 2 {
		t.Fatalf("contact count after refused deletes = %d, want 2", len(contacts))
	}
}

func TestDeletePromptNamesResolvedRecord(t *testing.T) {
	var messages strings.Builder
	err := readDeleteConfirmation(
		strings.NewReader("yes\n"),
		&messages,
		resolve.EntityContact,
		"Nick Dupont",
		"c17",
	)
	if err != nil {
		t.Fatalf("yes confirmation returned error: %v", err)
	}
	if got, want := messages.String(), `Delete contact "Nick Dupont" (c17)? [y/N] `; got != want {
		t.Fatalf("prompt = %q, want %q", got, want)
	}

	messages.Reset()
	err = readDeleteConfirmation(
		strings.NewReader("\n"),
		&messages,
		resolve.EntityContact,
		"Nick Dupont",
		"c17",
	)
	if !errors.Is(err, model.ErrValidation) || err.Error() != "delete cancelled" {
		t.Fatalf("default-no error = %v, want validation cancellation", err)
	}
}

func TestDeleteRejectsAmbiguousRefWithConfirmation(t *testing.T) {
	databasePath := newDeleteDatabase(t)
	mustCRM(t, databasePath, "contact", "add", "Amb One")
	mustCRM(t, databasePath, "contact", "add", "Amb Two")

	stdout, stderr, code := crm(
		t,
		databasePath,
		"contact",
		"delete",
		"amb",
		"--confirm",
	)
	if stdout != "" || code != 3 || !strings.Contains(stderr, "c1  Amb One") ||
		!strings.Contains(stderr, "c2  Amb Two") {
		t.Fatalf("ambiguous delete stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}

	stdout = mustCRM(t, databasePath, "contact", "ls", "--format", "json")
	var contacts []json.RawMessage
	if err := json.Unmarshal([]byte(stdout), &contacts); err != nil {
		t.Fatalf("decode contacts after ambiguous delete: %v", err)
	}
	if len(contacts) != 2 {
		t.Fatalf("contact count after ambiguous delete = %d, want 2", len(contacts))
	}
}

func TestDeleteEveryEntityEchoesDeletedPreDeleteRecord(t *testing.T) {
	databasePath := newDeleteDatabase(t)
	mustCRM(t, databasePath, "org", "add", "Standalone Org")
	mustCRM(t, databasePath, "contact", "add", "Nick Dupont")
	mustCRM(t, databasePath, "pipeline", "add", "Seed Raise")
	mustCRM(t, databasePath, "stage", "add", "p1", "sourced")
	mustCRM(
		t,
		databasePath,
		"deal",
		"add",
		"Nick ticket",
		"--pipeline",
		"p1",
		"--stage",
		"s1",
		"--contact",
		"c1",
	)
	mustCRM(t, databasePath, "log", "--deal", "d1", "--kind", "note", "--summary", "delete me")

	deletions := []struct {
		ref  string
		args []string
	}{
		{ref: "i1", args: []string{"interaction", "delete", "i1", "--confirm"}},
		{ref: "d1", args: []string{"deal", "delete", "d1", "--confirm"}},
		{ref: "s1", args: []string{"stage", "delete", "p1", "s1", "--confirm"}},
		{ref: "p1", args: []string{"pipeline", "delete", "p1", "--confirm"}},
		{ref: "c1", args: []string{"contact", "delete", "c1", "--confirm"}},
		{ref: "o1", args: []string{"org", "delete", "o1", "--confirm"}},
	}
	for _, deletion := range deletions {
		stdout, stderr, code := crm(t, databasePath, deletion.args...)
		if stderr != "" || code != 0 {
			t.Fatalf("delete %s stdout=%q stderr=%q code=%d", deletion.ref, stdout, stderr, code)
		}
		assertDeletedRecord(t, stdout, deletion.ref)
	}

	stdout, stderr, code := crm(t, databasePath, "interaction", "show", "i1")
	if stdout != "" || code != 2 || !strings.Contains(stderr, `no interaction "i1"`) {
		t.Fatalf("show deleted interaction stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	assertNoSidecars(t, databasePath)
}

func TestDeleteOrgBlockedByContact(t *testing.T) {
	databasePath := newDeleteDatabase(t)
	mustCRM(t, databasePath, "org", "add", "Acme")
	mustCRM(t, databasePath, "contact", "add", "Nick", "--org", "o1")
	assertDeleteBlocked(t, databasePath, []string{"org", "delete", "o1", "--confirm"}, "org appears in 1 contact")
}

func TestDeleteOrgBlockedByDeal(t *testing.T) {
	databasePath := newDeleteDatabase(t)
	mustCRM(t, databasePath, "org", "add", "Acme")
	addDeletePipeline(t, databasePath, "sourced")
	mustCRM(t, databasePath, "deal", "add", "Acme ticket", "--pipeline", "p1", "--org", "o1")
	assertDeleteBlocked(t, databasePath, []string{"org", "delete", "o1", "--confirm"}, "org appears in 1 deal")
}

func TestDeleteOrgBlockedByInteraction(t *testing.T) {
	databasePath := newDeleteDatabase(t)
	mustCRM(t, databasePath, "org", "add", "Acme")
	mustCRM(t, databasePath, "log", "--org", "o1", "--kind", "note", "--summary", "org note")
	assertDeleteBlocked(t, databasePath, []string{"org", "delete", "o1", "--confirm"}, "org appears in 1 interaction")
}

func TestDeleteContactBlockedByInteractionPerson(t *testing.T) {
	databasePath := newDeleteDatabase(t)
	mustCRM(t, databasePath, "contact", "add", "Nick")
	mustCRM(t, databasePath, "log", "--with", "c1", "--kind", "call", "--summary", "call")
	assertDeleteBlocked(t, databasePath, []string{"contact", "delete", "c1", "--confirm"}, "contact appears in 1 interaction")
}

func TestDeleteContactBlockedByDeal(t *testing.T) {
	databasePath := newDeleteDatabase(t)
	mustCRM(t, databasePath, "contact", "add", "Nick")
	addDeletePipeline(t, databasePath, "sourced")
	mustCRM(t, databasePath, "deal", "add", "Nick ticket", "--pipeline", "p1", "--contact", "c1")
	assertDeleteBlocked(t, databasePath, []string{"contact", "delete", "c1", "--confirm"}, "contact appears in 1 deal")
}

func TestDeleteContactBlockedByContactLinkSource(t *testing.T) {
	databasePath := newDeleteDatabase(t)
	mustCRM(t, databasePath, "contact", "add", "Nick")
	mustCRM(t, databasePath, "contact", "add", "Ana")
	mustCRM(t, databasePath, "contact", "relate", "c1", "c2", "--type", "mentor")
	assertDeleteBlocked(t, databasePath, []string{"contact", "delete", "c1", "--confirm"}, "contact appears in 1 contact link")
}

func TestDeleteContactBlockedByContactLinkTarget(t *testing.T) {
	databasePath := newDeleteDatabase(t)
	mustCRM(t, databasePath, "contact", "add", "Nick")
	mustCRM(t, databasePath, "contact", "add", "Ana")
	mustCRM(t, databasePath, "contact", "relate", "c1", "c2", "--type", "mentor")
	assertDeleteBlocked(t, databasePath, []string{"contact", "delete", "c2", "--confirm"}, "contact appears in 1 contact link")
}

func TestDeletePipelineBlockedByStage(t *testing.T) {
	databasePath := newDeleteDatabase(t)
	addDeletePipeline(t, databasePath, "sourced")
	assertDeleteBlocked(t, databasePath, []string{"pipeline", "delete", "p1", "--confirm"}, "pipeline appears in 1 stage")
}

func TestDeletePipelineBlockedByDeal(t *testing.T) {
	databasePath := newDeleteDatabase(t)
	mustCRM(t, databasePath, "contact", "add", "Nick")
	addDeletePipeline(t, databasePath, "sourced")
	mustCRM(t, databasePath, "deal", "add", "Nick ticket", "--pipeline", "p1", "--contact", "c1")
	mustCRM(t, databasePath, "deal", "archive", "d1")
	assertDeleteBlocked(
		t,
		databasePath,
		[]string{"pipeline", "delete", "p1", "--confirm"},
		"1 stage",
		"1 deal",
	)
}

func TestDeleteStageBlockedByDeal(t *testing.T) {
	databasePath := newDeleteDatabase(t)
	mustCRM(t, databasePath, "contact", "add", "Nick")
	addDeletePipeline(t, databasePath, "sourced")
	mustCRM(t, databasePath, "deal", "add", "Nick ticket", "--pipeline", "p1", "--contact", "c1")
	mustCRM(t, databasePath, "deal", "archive", "d1")
	assertDeleteBlocked(
		t,
		databasePath,
		[]string{"stage", "delete", "p1", "s1", "--confirm"},
		"1 deal",
		"1 stage move",
	)
}

func TestDeleteStageBlockedByStageMoveFromEndpoint(t *testing.T) {
	databasePath := stageMoveDeleteFixture(t)
	mustCRM(t, databasePath, "deal", "move", "d1", "s2")
	assertDeleteBlocked(
		t,
		databasePath,
		[]string{"stage", "delete", "p1", "s1", "--confirm"},
		"stage appears in 2 stage moves",
	)
}

func TestDeleteStageBlockedByStageMoveToEndpoint(t *testing.T) {
	databasePath := stageMoveDeleteFixture(t)
	mustCRM(t, databasePath, "deal", "move", "d1", "s2")
	assertDeleteBlocked(
		t,
		databasePath,
		[]string{"stage", "delete", "p1", "s2", "--confirm"},
		"1 deal",
		"1 stage move",
	)
}

func TestDeleteDealBlockedByInteraction(t *testing.T) {
	databasePath := newDeleteDatabase(t)
	mustCRM(t, databasePath, "contact", "add", "Nick")
	addDeletePipeline(t, databasePath, "sourced")
	mustCRM(t, databasePath, "deal", "add", "Nick ticket", "--pipeline", "p1", "--contact", "c1")
	mustCRM(t, databasePath, "log", "--deal", "d1", "--kind", "note", "--summary", "deal note")
	assertDeleteBlocked(t, databasePath, []string{"deal", "delete", "d1", "--confirm"}, "deal appears in 1 interaction")
}

func newDeleteDatabase(t *testing.T) string {
	t.Helper()

	databasePath := filepath.Join(t.TempDir(), "crm.db")
	mustCRM(t, databasePath, "init")

	return databasePath
}

func addDeletePipeline(t *testing.T, databasePath string, stages ...string) {
	t.Helper()

	mustCRM(t, databasePath, "pipeline", "add", "Seed Raise")
	for _, stage := range stages {
		mustCRM(t, databasePath, "stage", "add", "p1", stage)
	}
}

func stageMoveDeleteFixture(t *testing.T) string {
	t.Helper()

	databasePath := newDeleteDatabase(t)
	mustCRM(t, databasePath, "contact", "add", "Nick")
	addDeletePipeline(t, databasePath, "sourced", "pitched")
	mustCRM(
		t,
		databasePath,
		"deal",
		"add",
		"Nick ticket",
		"--pipeline",
		"p1",
		"--stage",
		"s1",
		"--contact",
		"c1",
	)

	return databasePath
}

func assertDeleteBlocked(
	t *testing.T,
	databasePath string,
	arguments []string,
	wantParts ...string,
) {
	t.Helper()

	stdout, stderr, code := crm(t, databasePath, arguments...)
	if stdout != "" || code != 4 || !strings.HasPrefix(stderr, "crm: error:") ||
		!strings.Contains(stderr, "archive instead") {
		t.Fatalf("blocked delete %v stdout=%q stderr=%q code=%d", arguments, stdout, stderr, code)
	}
	for _, want := range wantParts {
		if !strings.Contains(stderr, want) {
			t.Fatalf("blocked delete %v stderr=%q, want %q", arguments, stderr, want)
		}
	}
}

func assertDeletedRecord(t *testing.T, stdout, wantRef string) {
	t.Helper()

	var records []map[string]any
	if err := json.Unmarshal([]byte(stdout), &records); err != nil {
		t.Fatalf("decode deleted record %q: %v", stdout, err)
	}
	if len(records) != 1 {
		t.Fatalf("deleted record count = %d, want 1: %#v", len(records), records)
	}
	if got := records[0]["ref"]; got != wantRef {
		t.Fatalf("deleted record ref = %#v, want %q", got, wantRef)
	}
	if got := records[0]["deleted"]; got != true {
		t.Fatalf("deleted marker = %#v, want true", got)
	}
}
