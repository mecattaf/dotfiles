package cli

import (
	"encoding/csv"
	"encoding/json"
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"reflect"
	"strconv"
	"strings"
	"testing"

	"github.com/mecattaf/crm/internal/model"
)

func TestFlatExportEmptyAndAllShape(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "crm.db")
	mustCRM(t, databasePath, "init")

	stdout, stderr, code := crm(t, databasePath, "export", "contacts", "--format", "json")
	assertCommandResult(t, stdout, stderr, code, "[]\n", "", 0)
	stdout, stderr, code = crm(t, databasePath, "export", "contacts")
	assertCommandResult(t, stdout, stderr, code, "[]\n", "", 0)

	wantHeader := "ref,id,name,name_norm,org_id,job_title,email,phone,linkedin," +
		"location,context,relationship_hint,provenance_sources,provenance_details," +
		"created_at,updated_at,archived_at,links\n"
	stdout, stderr, code = crm(t, databasePath, "export", "contacts", "--format", "csv")
	assertCommandResult(t, stdout, stderr, code, wantHeader, "", 0)

	stdout, stderr, code = crm(t, databasePath, "export", "all", "--format", "json")
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		`{"contacts":[],"deals":[],"interactions":[],"orgs":[]}`+"\n",
		"",
		0,
	)
	var exported map[string]json.RawMessage
	if err := json.Unmarshal([]byte(stdout), &exported); err != nil {
		t.Fatalf("decode export all: %v", err)
	}
	keys := make([]string, 0, len(exported))
	for _, key := range []string{"contacts", "deals", "interactions", "orgs"} {
		if _, found := exported[key]; found {
			keys = append(keys, key)
		}
	}
	if want := []string{"contacts", "deals", "interactions", "orgs"}; !reflect.DeepEqual(keys, want) || len(exported) != len(want) {
		t.Fatalf("export all keys = %v (object=%v), want %v", keys, exported, want)
	}

	stdout, stderr, code = crm(t, databasePath, "export", "all", "--format", "csv")
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"",
		"crm: error: unsupported format \"csv\" (accepted: json)\n",
		1,
	)
	assertNoSidecars(t, databasePath)
}

func TestFlatExportCSVPreservesFixtureValues(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "crm.db")
	mustCRM(t, databasePath, "init")
	mustCRM(
		t,
		databasePath,
		"org", "add", `Léger, "Labs"`,
		"--category", "vc || advisor",
		"--context", "First line\nSecond, \"quoted\"",
		"--source", "notes/α.md",
		"--source", "notes/β.md",
		"--detail", "Renée said hello",
	)
	mustCRM(t, databasePath, "org", "add", "Null Fields")
	mustCRM(t, databasePath, "org", "archive", "o2")

	stdout, stderr, code := crm(t, databasePath, "export", "orgs", "--format", "csv")
	if stderr != "" || code != 0 {
		t.Fatalf("CSV export stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	reader := csv.NewReader(strings.NewReader(stdout))
	records, err := reader.ReadAll()
	if err != nil {
		t.Fatalf("parse exported CSV %q: %v", stdout, err)
	}
	if len(records) != 3 {
		t.Fatalf("CSV records = %d, want header plus two rows: %#v", len(records), records)
	}
	header := records[0]
	indexes := make(map[string]int, len(header))
	for index, field := range header {
		indexes[field] = index
	}
	for _, field := range []string{
		"ref", "id", "name", "name_norm", "context", "provenance_sources",
		"provenance_details", "website", "archived_at",
	} {
		if _, found := indexes[field]; !found {
			t.Fatalf("CSV header %v omits %q", header, field)
		}
	}
	first := records[1]
	if got := first[indexes["name"]]; got != `Léger, "Labs"` {
		t.Fatalf("CSV name = %q", got)
	}
	if got := first[indexes["context"]]; got != "First line\nSecond, \"quoted\"" {
		t.Fatalf("CSV embedded-newline context = %q", got)
	}
	if got := first[indexes["provenance_sources"]]; got != "notes/α.md || notes/β.md" {
		t.Fatalf("CSV provenance separator/unicode = %q", got)
	}
	if got := first[indexes["provenance_details"]]; got != "Renée said hello" {
		t.Fatalf("CSV unicode detail = %q", got)
	}
	second := records[2]
	if got := second[indexes["website"]]; got != "" {
		t.Fatalf("CSV NULL website = %q, want empty cell", got)
	}
	if got := second[indexes["archived_at"]]; got == "" {
		t.Fatal("flat CSV omitted the archived row's lifecycle timestamp")
	}
	if !strings.Contains(stdout, `"Léger, ""Labs"""`) ||
		!strings.Contains(stdout, `"First line`+"\n"+`Second, ""quoted"""`) {
		t.Fatalf("CSV writer did not quote commas, quotes, and newlines correctly: %q", stdout)
	}

	stdout, stderr, code = crm(t, databasePath, "export", "orgs", "--format", "json")
	if stderr != "" || code != 0 {
		t.Fatalf("JSON export stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	var organizations []model.Org
	if err := json.Unmarshal([]byte(stdout), &organizations); err != nil {
		t.Fatalf("decode org JSON export: %v", err)
	}
	if len(organizations) != 2 || organizations[1].Website != nil || organizations[1].ArchivedAt == nil {
		t.Fatalf("JSON export lost NULL/archive state: %#v", organizations)
	}
	assertNoSidecars(t, databasePath)
}

func TestFlatExportEveryEntityHasCompleteJSONAndCSV(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "crm.db")
	runReportFixture(
		t,
		databasePath,
		[]string{"init"},
		[]string{"org", "add", "Acme", "--category", "customer"},
		[]string{"contact", "add", "Ana", "--org", "o1", "--email", "ana@example.com"},
		[]string{"pipeline", "add", "Sales"},
		[]string{"stage", "add", "p1", "contacted", "--rot", "14"},
		[]string{"deal", "add", "Acme renewal", "--pipeline", "p1", "--org", "o1", "--contact", "c1"},
		[]string{"log", "--kind", "note", "--with", "c1", "--org", "o1", "--deal", "d1", "--summary", "Renewal note"},
	)

	tests := []struct {
		entity string
		ref    string
		keys   []string
	}{
		{
			entity: "orgs", ref: "o1",
			keys: []string{"ref", "id", "name", "name_norm", "category", "website", "linkedin", "location", "focus", "context", "relationship_hint", "provenance_sources", "provenance_details", "created_at", "updated_at", "archived_at"},
		},
		{
			entity: "contacts", ref: "c1",
			keys: []string{"ref", "id", "name", "name_norm", "org_id", "job_title", "email", "phone", "linkedin", "location", "context", "relationship_hint", "provenance_sources", "provenance_details", "created_at", "updated_at", "archived_at", "links"},
		},
		{
			entity: "deals", ref: "d1",
			keys: []string{"ref", "id", "title", "title_norm", "org_id", "contact_id", "pipeline_id", "pipeline", "stage_id", "stage", "status", "outcome_reason", "closed_at", "stage_changed_at", "days_in_stage", "rot_days", "created_at", "updated_at", "archived_at"},
		},
		{
			entity: "interactions", ref: "i1",
			keys: []string{"ref", "id", "kind", "occurred_on", "summary", "body", "transcript_path", "org_id", "deal_id", "contact_ids", "created_at", "updated_at", "archived_at"},
		},
	}
	for _, test := range tests {
		t.Run(test.entity, func(t *testing.T) {
			stdout, stderr, code := crm(
				t,
				databasePath,
				"export", test.entity, "--format", "json",
			)
			if stderr != "" || code != 0 {
				t.Fatalf("JSON export stdout=%q stderr=%q code=%d", stdout, stderr, code)
			}
			var rows []map[string]json.RawMessage
			if err := json.Unmarshal([]byte(stdout), &rows); err != nil {
				t.Fatalf("decode JSON export: %v", err)
			}
			if len(rows) != 1 || string(rows[0]["ref"]) != strconv.Quote(test.ref) {
				t.Fatalf("JSON export rows = %#v, want %s", rows, test.ref)
			}
			assertExactFieldSet(t, rows[0], test.keys)

			stdout, stderr, code = crm(
				t,
				databasePath,
				"export", test.entity, "--format", "csv",
			)
			if stderr != "" || code != 0 {
				t.Fatalf("CSV export stdout=%q stderr=%q code=%d", stdout, stderr, code)
			}
			records, err := csv.NewReader(strings.NewReader(stdout)).ReadAll()
			if err != nil {
				t.Fatalf("parse CSV export: %v", err)
			}
			if len(records) != 2 || !reflect.DeepEqual(records[0], test.keys) || records[1][0] != test.ref {
				t.Fatalf("CSV export records = %#v, want header %v and ref %s", records, test.keys, test.ref)
			}
		})
	}
	assertNoSidecars(t, databasePath)
}

func assertExactFieldSet(t *testing.T, row map[string]json.RawMessage, fields []string) {
	t.Helper()
	if len(row) != len(fields) {
		t.Fatalf("JSON fields = %v, want exactly %v", row, fields)
	}
	for _, field := range fields {
		if _, found := row[field]; !found {
			t.Fatalf("JSON fields = %v, missing %q", row, field)
		}
	}
}

func TestExportTreeAcceptanceAndWholesaleRegeneration(t *testing.T) {
	base := t.TempDir()
	databasePath := filepath.Join(base, "crm.db")
	mustCRM(t, databasePath, "init")
	transcriptRelative := filepath.Join("transcripts", "2026", "call notes.md")
	transcriptAbsolute := filepath.Join(base, transcriptRelative)
	if err := os.MkdirAll(filepath.Dir(transcriptAbsolute), 0o700); err != nil {
		t.Fatalf("create transcript fixture directory: %v", err)
	}
	if err := os.WriteFile(transcriptAbsolute, []byte("# Evidence\n"), 0o600); err != nil {
		t.Fatalf("write transcript fixture: %v", err)
	}

	runReportFixture(
		t,
		databasePath,
		[]string{"org", "add", "Acme & Co", "--source", "notes/source.md"},
		[]string{
			"contact", "add", "Anaïs O'Neil", "--org", "o1", "--email", "anais@example.com",
			"--source", "notes/source.md", "--detail", "Met in Paris",
		},
		[]string{"pipeline", "add", "Customer"},
		[]string{"stage", "add", "p1", "contacted"},
		[]string{"deal", "add", "Acme renewal", "--pipeline", "p1", "--org", "o1", "--contact", "c1"},
		[]string{
			"log", "--kind", "call", "--with", "c1", "--org", "o1", "--deal", "d1",
			"--date", "2026-07-29", "--summary", "Discussed the renewal", "--transcript", transcriptRelative,
		},
	)

	destination := filepath.Join(base, "review-tree")
	stdout, stderr, code := crm(t, databasePath, "export", "tree", destination)
	assertCommandResult(t, stdout, stderr, code, destination+"\n", "", 0)

	wantFiles := []string{
		"README.md",
		"index.md",
		filepath.Join("orgs", "acme-co.md"),
		filepath.Join("contacts", "anais-o-neil.md"),
		filepath.Join("deals", "acme-renewal.md"),
		filepath.Join("interactions", "2026-07-29-call-i1.md"),
	}
	for _, relative := range wantFiles {
		info, err := os.Stat(filepath.Join(destination, relative))
		if err != nil || !info.Mode().IsRegular() {
			t.Fatalf("generated file %s missing: info=%v err=%v", relative, info, err)
		}
	}
	contactPath := filepath.Join(destination, "contacts", "anais-o-neil.md")
	contactBytes, err := os.ReadFile(contactPath)
	if err != nil {
		t.Fatalf("read generated contact: %v", err)
	}
	contactMarkdown := string(contactBytes)
	for _, fragment := range []string{
		"---\nid: c1\norg: o1\nemail: \"anais@example.com\"\nprovenance:\n",
		"# Anaïs O'Neil (c1)",
		"## Timeline",
		"Discussed the renewal",
		"[transcript](../../transcripts/2026/call%20notes.md)",
	} {
		if !strings.Contains(contactMarkdown, fragment) {
			t.Fatalf("contact Markdown omits %q:\n%s", fragment, contactMarkdown)
		}
	}
	indexBytes, err := os.ReadFile(filepath.Join(destination, "index.md"))
	if err != nil || !strings.Contains(string(indexBytes), "Contacts (1)") ||
		!strings.Contains(string(indexBytes), "contacts/anais-o-neil.md") {
		t.Fatalf("generated index is incomplete: %q err=%v", indexBytes, err)
	}
	if err := filepath.WalkDir(destination, func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if entry.IsDir() && strings.HasPrefix(entry.Name(), "_by-") {
			t.Fatalf("tree contains copied index directory %s", path)
		}

		return nil
	}); err != nil {
		t.Fatalf("walk generated tree: %v", err)
	}

	stalePaths := []string{
		filepath.Join(destination, "stale.md"),
		filepath.Join(destination, "contacts", "obsolete.md"),
	}
	for _, path := range stalePaths {
		if err := os.WriteFile(path, []byte("stale\n"), 0o600); err != nil {
			t.Fatalf("write stale generated fixture: %v", err)
		}
	}
	mustCRM(t, databasePath, "contact", "archive", "c1")
	stdout, stderr, code = crm(t, databasePath, "export", "tree", destination)
	assertCommandResult(t, stdout, stderr, code, destination+"\n", "", 0)
	for _, path := range append(stalePaths, contactPath) {
		if _, err := os.Stat(path); !errors.Is(err, os.ErrNotExist) {
			t.Fatalf("wholesale regeneration retained %s: %v", path, err)
		}
	}

	flatJSON := mustCRM(t, databasePath, "export", "contacts", "--format", "json")
	var contacts []model.Contact
	if err := json.Unmarshal([]byte(flatJSON), &contacts); err != nil {
		t.Fatalf("decode archived flat contact export: %v", err)
	}
	if len(contacts) != 1 || contacts[0].ArchivedAt == nil {
		t.Fatalf("flat export did not retain archived contact: %#v", contacts)
	}

	mustCRM(t, databasePath, "contact", "unarchive", "c1")
	defaultDestination := filepath.Join(base, "tree")
	stdout, stderr, code = crm(t, databasePath, "export", "tree")
	assertCommandResult(t, stdout, stderr, code, defaultDestination+"\n", "", 0)
	if _, err := os.Stat(filepath.Join(defaultDestination, "contacts", "anais-o-neil.md")); err != nil {
		t.Fatalf("default tree destination missing contact: %v", err)
	}
	assertNoSidecars(t, databasePath)
}

func TestExportTreeRefusesUnownedNonemptyDirectory(t *testing.T) {
	base := t.TempDir()
	databasePath := filepath.Join(base, "crm.db")
	mustCRM(t, databasePath, "init")
	destination := filepath.Join(base, "unrelated")
	if err := os.Mkdir(destination, 0o700); err != nil {
		t.Fatalf("create unrelated directory: %v", err)
	}
	keptPath := filepath.Join(destination, "keep.txt")
	if err := os.WriteFile(keptPath, []byte("keep\n"), 0o600); err != nil {
		t.Fatalf("write unrelated file: %v", err)
	}

	stdout, stderr, code := crm(t, databasePath, "export", "tree", destination)
	if stdout != "" || code != 1 || !strings.Contains(stderr, "is not a generated CRM tree") {
		t.Fatalf("unowned destination stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	content, err := os.ReadFile(keptPath)
	if err != nil || string(content) != "keep\n" {
		t.Fatalf("unowned destination was changed: content=%q err=%v", content, err)
	}
}

func TestExportFormatsValidateBeforeDatabaseAccess(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "missing.db")
	stdout, stderr, code := crm(t, databasePath, "export", "contacts", "--format", "table")
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"",
		"crm: error: unsupported format \"table\" (accepted: json|csv)\n",
		1,
	)
	stdout, stderr, code = crm(t, databasePath, "export", "all", "--format", "csv")
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"",
		"crm: error: unsupported format \"csv\" (accepted: json)\n",
		1,
	)
}
