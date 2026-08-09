package cli

import (
	"encoding/json"
	"path/filepath"
	"testing"
)

func TestScenarioAgentSession(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "crm.db")
	stdout, stderr, code := crm(t, databasePath, "init")
	assertCommandResult(t, stdout, stderr, code, databasePath+"\n", "", 0)

	stdout, stderr, code = crm(t, databasePath, "org", "add", "Kima Ventures")
	if stderr != "" || code != 0 {
		t.Fatalf("agent fixture org add stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	stdout, stderr, code = crm(
		t,
		databasePath,
		"contact", "add", "Nick Dupont", "--org", "kima", "--email", "nick@kima.vc",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("agent fixture contact add stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}

	stdout, stderr, code = crm(t, databasePath, "find", "nick", "--format", "json")
	if stderr != "" || code != 0 {
		t.Fatalf("agent find stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	results := decodeFindRows(t, stdout)
	if len(results) == 0 || results[0].Ref != "c1" {
		t.Fatalf("agent find results = %#v, want c1 first", results)
	}

	stdout, stderr, code = crm(
		t,
		databasePath,
		"context", results[0].Ref, "--format", "json",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("agent context stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	briefing := decodeContextObject(t, stdout)
	assertJSONArrayLength(t, briefing, "links", 0)
	assertJSONArrayLength(t, briefing, "deals", 0)
	assertJSONArrayLength(t, briefing, "timeline", 0)

	stdout, stderr, code = crm(
		t,
		databasePath,
		"log", "--kind", "message", "--with", results[0].Ref,
		"--summary", "sent a concise follow-up", "--date", "2026-07-31",
		"--format", "json",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("agent log stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	var logged []map[string]json.RawMessage
	if err := json.Unmarshal([]byte(stdout), &logged); err != nil || len(logged) != 1 {
		t.Fatalf("agent log JSON = %q, err=%v", stdout, err)
	}

	stdout, stderr, code = crm(
		t,
		databasePath,
		"context", results[0].Ref, "--format", "json",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("agent final context stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	briefing = decodeContextObject(t, stdout)
	assertJSONArrayLength(t, briefing, "timeline", 1)
	assertNoSidecars(t, databasePath)
}
