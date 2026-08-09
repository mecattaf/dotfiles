package cli

import (
	"encoding/json"
	"fmt"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestOrgArchiveAcceptance(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "crm.db")
	stdout, stderr, code := crm(t, databasePath, "init")
	assertCommandResult(t, stdout, stderr, code, databasePath+"\n", "", 0)
	stdout, stderr, code = crm(t, databasePath, "org", "add", "Kima Ventures")
	if stderr != "" || code != 0 {
		t.Fatalf("org add stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}

	stdout, stderr, code = crm(t, databasePath, "org", "archive", "kima")
	if stderr != "" || code != 0 {
		t.Fatalf("org archive stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	archived := assertCompactOrgJSON(t, stdout, 1)[0]
	assertArchivedTimestamp(t, archived.ArchivedAt, archived.UpdatedAt)

	// A repeated name ref remains an idempotent conflict even though ordinary
	// name rungs deliberately exclude archived rows.
	stdout, stderr, code = crm(t, databasePath, "org", "archive", "kima")
	if stdout != "" || code != 4 || !strings.Contains(stderr, "already archived") {
		t.Fatalf("repeat archive stdout=%q stderr=%q code=%d, want empty/conflict", stdout, stderr, code)
	}

	stdout, stderr, code = crm(t, databasePath, "org", "archive", "nosuchorg")
	if stdout != "" || code != 2 || !strings.Contains(stderr, `no org "nosuchorg"`) {
		t.Fatalf("missing archive stdout=%q stderr=%q code=%d, want empty/not-found", stdout, stderr, code)
	}

	stdout, stderr, code = crm(t, databasePath, "org", "ls", "--format", "json")
	assertCommandResult(t, stdout, stderr, code, "[]\n", "", 0)
	stdout, stderr, code = crm(t, databasePath, "org", "ls", "--all", "--format", "json")
	if stderr != "" || code != 0 {
		t.Fatalf("org ls --all stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	listed := assertCompactOrgJSON(t, stdout, 1)[0]
	assertArchivedTimestamp(t, listed.ArchivedAt, listed.UpdatedAt)

	stdout, stderr, code = crm(t, databasePath, "org", "ls", "--all", "--format", "table")
	if stderr != "" || code != 0 || !strings.Contains(stdout, "ARCHIVED") ||
		!strings.Contains(stdout, *listed.ArchivedAt) {
		t.Fatalf("archived table row is not visibly marked: stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}

	stdout, stderr, code = crm(t, databasePath, "org", "show", "o1")
	if stderr != "" || code != 0 || assertCompactOrgJSON(t, stdout, 1)[0].ArchivedAt == nil {
		t.Fatalf("show archived id stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	stdout, stderr, code = crm(t, databasePath, "org", "show", "kima")
	if stdout != "" || code != 2 {
		t.Fatalf("show archived name stdout=%q stderr=%q code=%d, want empty/not-found", stdout, stderr, code)
	}

	stdout, stderr, code = crm(t, databasePath, "org", "add", "Kima Ventures")
	if stderr != "" || code != 0 {
		t.Fatalf("re-add archived org name stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	if got := assertCompactOrgJSON(t, stdout, 1)[0].Ref; got != "o2" {
		t.Fatalf("re-added org ref = %q, want o2", got)
	}

	assertNoSidecars(t, databasePath)
}

func TestArchiveAndUnarchiveEveryEntity(t *testing.T) {
	databasePath := lifecycleFixture(t)

	tests := []struct {
		name        string
		archiveArgs []string
		ref         string
		listArgs    []string
	}{
		{name: "org", archiveArgs: []string{"org", "archive", "o1"}, ref: "o1", listArgs: []string{"org", "ls"}},
		{name: "contact", archiveArgs: []string{"contact", "archive", "c1"}, ref: "c1", listArgs: []string{"contact", "ls"}},
		{name: "interaction", archiveArgs: []string{"interaction", "archive", "i1"}, ref: "i1", listArgs: []string{"interaction", "ls"}},
		{name: "pipeline", archiveArgs: []string{"pipeline", "archive", "p1"}, ref: "p1", listArgs: []string{"pipeline", "ls"}},
		{name: "stage", archiveArgs: []string{"stage", "archive", "p1", "s2"}, ref: "s2"},
		{name: "deal", archiveArgs: []string{"deal", "archive", "d1"}, ref: "d1", listArgs: []string{"deal", "ls"}},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			stdout, stderr, code := crm(t, databasePath, test.archiveArgs...)
			if stderr != "" || code != 0 {
				t.Fatalf("archive stdout=%q stderr=%q code=%d", stdout, stderr, code)
			}
			archived := decodeLifecycleRecord(t, stdout)
			if archived.Ref != test.ref || archived.ArchivedAt == nil {
				t.Fatalf("archived record = %#v, want %s marked", archived, test.ref)
			}
			assertArchivedTimestamp(t, archived.ArchivedAt, archived.UpdatedAt)

			stdout, stderr, code = crm(t, databasePath, test.archiveArgs...)
			if stdout != "" || code != 4 || !strings.Contains(stderr, "already archived") {
				t.Fatalf("repeat archive stdout=%q stderr=%q code=%d", stdout, stderr, code)
			}

			if len(test.listArgs) > 0 {
				args := append(append([]string(nil), test.listArgs...), "--format", "json")
				stdout, stderr, code = crm(t, databasePath, args...)
				if stderr != "" || code != 0 || lifecycleListHasRef(t, stdout, test.ref) {
					t.Fatalf("default list stdout=%q stderr=%q code=%d still contains %s", stdout, stderr, code, test.ref)
				}
				args = append(append([]string(nil), test.listArgs...), "--all", "--format", "json")
				stdout, stderr, code = crm(t, databasePath, args...)
				if stderr != "" || code != 0 || !lifecycleListHasArchivedRef(t, stdout, test.ref) {
					t.Fatalf("--all list stdout=%q stderr=%q code=%d omits marked %s", stdout, stderr, code, test.ref)
				}
			}

			unarchiveArgs := append([]string{test.archiveArgs[0], "unarchive"}, test.archiveArgs[2:]...)
			stdout, stderr, code = crm(t, databasePath, unarchiveArgs...)
			if stderr != "" || code != 0 {
				t.Fatalf("unarchive stdout=%q stderr=%q code=%d", stdout, stderr, code)
			}
			restored := decodeLifecycleRecord(t, stdout)
			if restored.Ref != test.ref || restored.ArchivedAt != nil {
				t.Fatalf("unarchived record = %#v, want %s live", restored, test.ref)
			}

			stdout, stderr, code = crm(t, databasePath, unarchiveArgs...)
			if stdout != "" || code != 4 || !strings.Contains(stderr, "already unarchived") {
				t.Fatalf("repeat unarchive stdout=%q stderr=%q code=%d", stdout, stderr, code)
			}
		})
	}

	assertNoSidecars(t, databasePath)
}

func TestLifecycleMissingRefsAreNotFoundForEveryEntity(t *testing.T) {
	databasePath := lifecycleFixture(t)
	tests := [][]string{
		{"org", "archive", "o999"},
		{"contact", "archive", "c999"},
		{"interaction", "archive", "i999"},
		{"pipeline", "archive", "p999"},
		{"stage", "archive", "p1", "s999"},
		{"deal", "archive", "d999"},
		{"org", "unarchive", "o999"},
		{"contact", "unarchive", "c999"},
		{"interaction", "unarchive", "i999"},
		{"pipeline", "unarchive", "p999"},
		{"stage", "unarchive", "p1", "s999"},
		{"deal", "unarchive", "d999"},
	}

	for _, arguments := range tests {
		t.Run(strings.Join(arguments[:2], "_"), func(t *testing.T) {
			stdout, stderr, code := crm(t, databasePath, arguments...)
			if stdout != "" || code != 2 || !strings.HasPrefix(stderr, "crm: error:") {
				t.Fatalf("%v stdout=%q stderr=%q code=%d, want empty/not-found", arguments, stdout, stderr, code)
			}
		})
	}
}

func TestArchivingFreesLiveUniqueValues(t *testing.T) {
	t.Run("contact email", func(t *testing.T) {
		databasePath := filepath.Join(t.TempDir(), "crm.db")
		mustCRM(t, databasePath, "init")
		mustCRM(t, databasePath, "contact", "add", "Original", "--email", "same@example.com")
		mustCRM(t, databasePath, "contact", "archive", "c1")
		stdout := mustCRM(t, databasePath, "contact", "add", "Replacement", "--email", "SAME@example.com")
		if got := decodeLifecycleRecord(t, stdout).Ref; got != "c2" {
			t.Fatalf("replacement contact ref = %q, want c2", got)
		}
	})

	t.Run("pipeline name", func(t *testing.T) {
		databasePath := filepath.Join(t.TempDir(), "crm.db")
		mustCRM(t, databasePath, "init")
		mustCRM(t, databasePath, "pipeline", "add", "Seed Raise")
		mustCRM(t, databasePath, "pipeline", "archive", "p1")
		stdout := mustCRM(t, databasePath, "pipeline", "add", "Seed Raise")
		if got := decodeLifecycleRecord(t, stdout).Ref; got != "p2" {
			t.Fatalf("replacement pipeline ref = %q, want p2", got)
		}
	})

	t.Run("stage name", func(t *testing.T) {
		databasePath := filepath.Join(t.TempDir(), "crm.db")
		mustCRM(t, databasePath, "init")
		mustCRM(t, databasePath, "pipeline", "add", "Seed Raise")
		mustCRM(t, databasePath, "stage", "add", "p1", "pitched")
		mustCRM(t, databasePath, "stage", "archive", "p1", "s1")
		stdout := mustCRM(t, databasePath, "stage", "add", "p1", "pitched")
		if got := decodeLifecycleRecord(t, stdout).Ref; got != "s2" {
			t.Fatalf("replacement stage ref = %q, want s2", got)
		}
	})
}

func TestUnarchiveRefusesRestoringAClaimedUniqueValue(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "crm.db")
	mustCRM(t, databasePath, "init")
	mustCRM(t, databasePath, "org", "add", "Kima Ventures")
	mustCRM(t, databasePath, "org", "archive", "o1")
	mustCRM(t, databasePath, "org", "add", "Kima Ventures")

	stdout, stderr, code := crm(t, databasePath, "org", "unarchive", "o1")
	if stdout != "" || code != 4 || !strings.Contains(stderr, "o2 (Kima Ventures)") {
		t.Fatalf("colliding unarchive stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}

	stdout, stderr, code = crm(t, databasePath, "org", "show", "o1")
	if stderr != "" || code != 0 || assertCompactOrgJSON(t, stdout, 1)[0].ArchivedAt == nil {
		t.Fatalf("failed unarchive changed archived row: stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
}

func TestDealMoveRejectsArchivedStage(t *testing.T) {
	databasePath := lifecycleFixture(t)
	mustCRM(t, databasePath, "stage", "archive", "p1", "pitched")

	for _, stageRef := range []string{"pitched", "s2"} {
		stdout, stderr, code := crm(t, databasePath, "deal", "move", "d1", stageRef)
		if stdout != "" || code != 4 || !strings.Contains(stderr, "not a live stage") {
			t.Fatalf("move to archived %q stdout=%q stderr=%q code=%d", stageRef, stdout, stderr, code)
		}
	}
}

type lifecycleRecord struct {
	Ref        string  `json:"ref"`
	UpdatedAt  string  `json:"updated_at"`
	ArchivedAt *string `json:"archived_at"`
}

func lifecycleFixture(t *testing.T) string {
	t.Helper()

	databasePath := filepath.Join(t.TempDir(), "crm.db")
	mustCRM(t, databasePath, "init")
	mustCRM(t, databasePath, "org", "add", "Acme")
	mustCRM(t, databasePath, "contact", "add", "Nick", "--org", "o1")
	mustCRM(t, databasePath, "pipeline", "add", "Seed Raise")
	mustCRM(t, databasePath, "stage", "add", "p1", "sourced")
	mustCRM(t, databasePath, "stage", "add", "p1", "pitched")
	mustCRM(t, databasePath, "deal", "add", "Acme ticket", "--pipeline", "p1", "--stage", "s1", "--org", "o1")
	mustCRM(t, databasePath, "log", "--deal", "d1", "--kind", "note", "--summary", "fixture")

	return databasePath
}

func mustCRM(t *testing.T, databasePath string, arguments ...string) string {
	t.Helper()

	stdout, stderr, code := crm(t, databasePath, arguments...)
	if stderr != "" || code != 0 {
		t.Fatalf("crm %s stdout=%q stderr=%q code=%d", strings.Join(arguments, " "), stdout, stderr, code)
	}

	return stdout
}

func decodeLifecycleRecord(t *testing.T, stdout string) lifecycleRecord {
	t.Helper()

	var records []lifecycleRecord
	if err := json.Unmarshal([]byte(stdout), &records); err != nil {
		t.Fatalf("decode lifecycle output %q: %v", stdout, err)
	}
	if len(records) != 1 {
		t.Fatalf("lifecycle output length = %d, want 1: %#v", len(records), records)
	}
	encoded, err := json.Marshal(records)
	if err != nil {
		t.Fatalf("re-encode lifecycle output: %v", err)
	}
	if !strings.Contains(stdout, fmt.Sprintf(`"ref":%q`, records[0].Ref)) ||
		!strings.HasSuffix(stdout, "\n") || len(encoded) == 0 {
		t.Fatalf("lifecycle output is not compact JSON: %q", stdout)
	}

	return records[0]
}

func assertArchivedTimestamp(t *testing.T, archivedAt *string, updatedAt string) {
	t.Helper()

	if archivedAt == nil {
		t.Fatal("archived_at is null, want RFC3339 timestamp")
	}
	if _, err := time.Parse(time.RFC3339, *archivedAt); err != nil {
		t.Fatalf("archived_at = %q, want RFC3339: %v", *archivedAt, err)
	}
	if *archivedAt != updatedAt {
		t.Fatalf("archived_at = %q, updated_at = %q; want same mutation instant", *archivedAt, updatedAt)
	}
}

func lifecycleListHasRef(t *testing.T, stdout, wanted string) bool {
	t.Helper()

	var records []lifecycleRecord
	if err := json.Unmarshal([]byte(stdout), &records); err != nil {
		t.Fatalf("decode lifecycle list %q: %v", stdout, err)
	}
	for _, record := range records {
		if record.Ref == wanted {
			return true
		}
	}

	return false
}

func lifecycleListHasArchivedRef(t *testing.T, stdout, wanted string) bool {
	t.Helper()

	var records []lifecycleRecord
	if err := json.Unmarshal([]byte(stdout), &records); err != nil {
		t.Fatalf("decode lifecycle list %q: %v", stdout, err)
	}
	for _, record := range records {
		if record.Ref == wanted {
			return record.ArchivedAt != nil
		}
	}

	return false
}
