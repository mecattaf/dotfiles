package cli

import (
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"strconv"
	"testing"
	"time"
)

func TestPostWriteHookTimeoutContract(t *testing.T) {
	if postWriteTimeout != 30*time.Second {
		t.Fatalf("post-write timeout = %s, want 30s", postWriteTimeout)
	}
}

func TestPostWriteHookReceivesMutationPayload(t *testing.T) {
	temporaryDirectory := t.TempDir()
	databasePath := filepath.Join(temporaryDirectory, "crm.db")
	stdout, stderr, code := crm(t, databasePath, "init")
	assertCommandResult(t, stdout, stderr, code, databasePath+"\n", "", 0)

	payloadPath := filepath.Join(temporaryDirectory, "payload.json")
	t.Setenv("CRM_POST_WRITE_HOOK", "cat > "+strconv.Quote(payloadPath))
	stdout, stderr, code = crm(t, databasePath, "org", "add", "Hooked")
	if stderr != "" || code != 0 {
		t.Fatalf("hooked add stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	created := assertCompactOrgJSON(t, stdout, 1)[0]

	payloadBytes, err := os.ReadFile(payloadPath)
	if err != nil {
		t.Fatalf("read hook payload: %v", err)
	}
	var payload struct {
		Event   string           `json:"event"`
		Verb    string           `json:"verb"`
		Entity  string           `json:"entity"`
		Refs    []string         `json:"refs"`
		Records []map[string]any `json:"records"`
		DBPath  string           `json:"db_path"`
	}
	if err := json.Unmarshal(payloadBytes, &payload); err != nil {
		t.Fatalf("decode hook payload %q: %v", payloadBytes, err)
	}
	if payload.Event != "post-write" || payload.Verb != "add" || payload.Entity != "org" {
		t.Fatalf("hook event tuple = (%q, %q, %q)", payload.Event, payload.Verb, payload.Entity)
	}
	if !reflect.DeepEqual(payload.Refs, []string{created.Reference()}) {
		t.Fatalf("hook refs = %v, want [%s]", payload.Refs, created.Reference())
	}
	if len(payload.Records) != 1 || payload.Records[0]["ref"] != created.Reference() ||
		payload.Records[0]["name"] != "Hooked" {
		t.Fatalf("hook records = %#v", payload.Records)
	}
	if payload.DBPath != databasePath {
		t.Fatalf("hook db_path = %q, want %q", payload.DBPath, databasePath)
	}
}

func TestPostWriteHookFailureAndOutputNeverFailVerb(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "crm.db")
	stdout, stderr, code := crm(t, databasePath, "init")
	assertCommandResult(t, stdout, stderr, code, databasePath+"\n", "", 0)

	t.Setenv(
		"CRM_POST_WRITE_HOOK",
		"printf 'hidden hook stdout\\n'; printf 'hook warning\\n' >&2; exit 1",
	)
	stdout, stderr, code = crm(t, databasePath, "org", "add", "Hook fails")
	if code != 0 {
		t.Fatalf("hook failure changed exit code: stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	if stderr != "hook warning\n" {
		t.Fatalf("hook stderr = %q, want passthrough warning", stderr)
	}
	created := assertCompactOrgJSON(t, stdout, 1)
	if created[0].Name != "Hook fails" {
		t.Fatalf("created organization = %#v", created[0])
	}
}

func TestReadVerbNeverFiresPostWriteHook(t *testing.T) {
	temporaryDirectory := t.TempDir()
	databasePath := filepath.Join(temporaryDirectory, "crm.db")
	stdout, stderr, code := crm(t, databasePath, "init")
	assertCommandResult(t, stdout, stderr, code, databasePath+"\n", "", 0)
	stdout, stderr, code = crm(t, databasePath, "org", "add", "Read only")
	if stderr != "" || code != 0 {
		t.Fatalf("fixture add stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}

	readPayloadPath := filepath.Join(temporaryDirectory, "read.json")
	t.Setenv("CRM_POST_WRITE_HOOK", "cat > "+strconv.Quote(readPayloadPath))
	stdout, stderr, code = crm(t, databasePath, "org", "ls")
	if stderr != "" || code != 0 || len(assertCompactOrgJSON(t, stdout, 1)) != 1 {
		t.Fatalf("org ls stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	if _, err := os.Stat(readPayloadPath); !os.IsNotExist(err) {
		t.Fatalf("read hook payload exists or cannot be inspected: %v", err)
	}
}

func TestDoctorHookFiresOnlyForFTSRepair(t *testing.T) {
	temporaryDirectory := t.TempDir()
	databasePath := filepath.Join(temporaryDirectory, "crm.db")
	stdout, stderr, code := crm(t, databasePath, "init")
	assertCommandResult(t, stdout, stderr, code, databasePath+"\n", "", 0)

	payloadPath := filepath.Join(temporaryDirectory, "doctor.json")
	t.Setenv("CRM_POST_WRITE_HOOK", "cat > "+strconv.Quote(payloadPath))
	stdout, stderr, code = crm(t, databasePath, "doctor")
	if stdout == "" || stderr != "" || code != 0 {
		t.Fatalf("read-only doctor stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	if _, err := os.Stat(payloadPath); !os.IsNotExist(err) {
		t.Fatalf("read-only doctor fired hook: %v", err)
	}

	stdout, stderr, code = crm(t, databasePath, "doctor", "--rebuild-fts")
	if stdout == "" || stderr != "" || code != 0 {
		t.Fatalf("repair doctor stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	payloadBytes, err := os.ReadFile(payloadPath)
	if err != nil {
		t.Fatalf("read doctor hook payload: %v", err)
	}
	var payload postWritePayload
	if err := json.Unmarshal(payloadBytes, &payload); err != nil {
		t.Fatalf("decode doctor hook payload %q: %v", payloadBytes, err)
	}
	if payload.Event != "post-write" || payload.Verb != "doctor" || payload.Entity != "fts" {
		t.Fatalf("doctor hook event tuple = (%q, %q, %q)", payload.Event, payload.Verb, payload.Entity)
	}
	if len(payload.Refs) != 0 || len(payload.Records) != 1 || payload.DBPath != databasePath {
		t.Fatalf("doctor hook payload = %#v", payload)
	}
}
