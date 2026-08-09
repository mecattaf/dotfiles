package cli

import (
	"encoding/json"
	"fmt"
	"path/filepath"
	"reflect"
	"slices"
	"testing"

	"github.com/mecattaf/crm/internal/db"
)

type dupeJSONRecord struct {
	Ref  string `json:"ref"`
	Name string `json:"name"`
}

type dupeJSONRow struct {
	Left    dupeJSONRecord `json:"left"`
	Right   dupeJSONRecord `json:"right"`
	Score   float64        `json:"score"`
	Reasons []string       `json:"reasons"`
}

func TestDupesScoresAuditableReasonsAndIsStrictlyReadOnly(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "crm.db")
	stdout, stderr, code := crm(t, databasePath, "init")
	assertCommandResult(t, stdout, stderr, code, databasePath+"\n", "", 0)

	contacts := [][]string{
		{"Alice Smith", "--email", "alice@gmail.com"},
		{"Bob Jones", "--email", "bob@gmail.com"},
		{"Renée Martin", "--email", "renee@kima.vc"},
		{"Renee Marten", "--email", "r.marten@kima.vc"},
	}
	for _, fixture := range contacts {
		arguments := append([]string{"contact", "add"}, fixture...)
		stdout, stderr, code = crm(t, databasePath, arguments...)
		if stderr != "" || code != 0 {
			t.Fatalf("contact fixture %q stdout=%q stderr=%q code=%d", fixture[0], stdout, stderr, code)
		}
	}
	for _, fixture := range [][]string{
		{"North Holdings", "--website", "https://sales.example.co.uk/team"},
		{"South Labs", "--website", "support.example.co.uk"},
	} {
		arguments := append([]string{"org", "add"}, fixture...)
		stdout, stderr, code = crm(t, databasePath, arguments...)
		if stderr != "" || code != 0 {
			t.Fatalf("org fixture %q stdout=%q stderr=%q code=%d", fixture[0], stdout, stderr, code)
		}
	}

	before := snapshotCRMRowCounts(t, databasePath)
	stdout, stderr, code = crm(
		t,
		databasePath,
		"dupes", "--type", "contact", "--threshold", "0", "--format", "json",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("contact dupes stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	var contactRows []dupeJSONRow
	if err := json.Unmarshal([]byte(stdout), &contactRows); err != nil {
		t.Fatalf("decode contact dupes %q: %v", stdout, err)
	}
	if len(contactRows) != 6 {
		t.Fatalf("contact dupe pair count = %d, want 6: %#v", len(contactRows), contactRows)
	}
	for _, row := range contactRows {
		if row.Reasons == nil {
			t.Fatalf("dupe row carries null reasons instead of []: %#v", row)
		}
	}

	freeMail := findDupePair(t, contactRows, "c1", "c2")
	if slices.Contains(freeMail.Reasons, "shared email domain") {
		t.Fatalf("free-mail-only pair reasons = %v", freeMail.Reasons)
	}
	strong := findDupePair(t, contactRows, "c3", "c4")
	if got, want := strong.Score, 0.55; got != want {
		t.Fatalf("strong contact pair score = %v, want %v", got, want)
	}
	for _, reason := range []string{"similar name", "shared email domain"} {
		if !slices.Contains(strong.Reasons, reason) {
			t.Fatalf("strong contact pair reasons = %v, missing %q", strong.Reasons, reason)
		}
	}

	stdout, stderr, code = crm(
		t,
		databasePath,
		"dupes", "--type", "org", "--threshold", "0.2", "--format", "json",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("org dupes stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	var orgRows []dupeJSONRow
	if err := json.Unmarshal([]byte(stdout), &orgRows); err != nil {
		t.Fatalf("decode org dupes %q: %v", stdout, err)
	}
	orgPair := findDupePair(t, orgRows, "o1", "o2")
	if orgPair.Score != 0.2 ||
		!slices.Equal(orgPair.Reasons, []string{"same registrable website domain"}) {
		t.Fatalf("organization domain pair = %#v", orgPair)
	}

	stdout, stderr, code = crm(t, databasePath, "dupes")
	if stderr != "" || code != 0 {
		t.Fatalf("default dupes stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	var defaultRows []dupeJSONRow
	if err := json.Unmarshal([]byte(stdout), &defaultRows); err != nil {
		t.Fatalf("decode default dupes %q: %v", stdout, err)
	}
	if len(defaultRows) == 0 {
		t.Fatal("default dupes omitted the strong contact pair")
	}
	after := snapshotCRMRowCounts(t, databasePath)
	if !reflect.DeepEqual(after, before) {
		t.Fatalf("dupes changed database row counts: before=%v after=%v", before, after)
	}

	assertNoSidecars(t, databasePath)
}

func TestDupesValidatesTypeThresholdLimitAndFormat(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "crm.db")
	stdout, stderr, code := crm(t, databasePath, "init")
	assertCommandResult(t, stdout, stderr, code, databasePath+"\n", "", 0)

	for _, test := range []struct {
		arguments []string
		message   string
	}{
		{
			arguments: []string{"dupes", "--type", "deal"},
			message:   "invalid dupes type \"deal\" (accepted: contact,org)",
		},
		{arguments: []string{"dupes", "--threshold", "1.1"}, message: "threshold must be between 0 and 1"},
		{arguments: []string{"dupes", "--limit", "-1"}, message: "limit must not be negative"},
		{arguments: []string{"dupes", "--format", "ids"}, message: "unsupported format \"ids\" (accepted: table|json)"},
	} {
		stdout, stderr, code = crm(t, databasePath, test.arguments...)
		if stdout != "" || code != 1 || stderr != "crm: error: "+test.message+"\n" {
			t.Fatalf("crm %v stdout=%q stderr=%q code=%d", test.arguments, stdout, stderr, code)
		}
	}
}

func findDupePair(t *testing.T, rows []dupeJSONRow, leftRef, rightRef string) dupeJSONRow {
	t.Helper()
	for _, row := range rows {
		if row.Left.Ref == leftRef && row.Right.Ref == rightRef ||
			row.Left.Ref == rightRef && row.Right.Ref == leftRef {
			return row
		}
	}

	t.Fatalf("dupe pair %s/%s not found in %#v", leftRef, rightRef, rows)
	return dupeJSONRow{}
}

func snapshotCRMRowCounts(t *testing.T, databasePath string) map[string]int {
	t.Helper()
	database, err := db.Open(databasePath)
	if err != nil {
		t.Fatalf("open database for row counts: %v", err)
	}
	defer func() {
		if err := database.Close(); err != nil {
			t.Errorf("close database after row counts: %v", err)
		}
	}()

	tables := []string{
		"orgs", "contacts", "contact_links", "pipelines", "stages",
		"deals", "stage_moves", "interactions", "interaction_people",
	}
	counts := make(map[string]int, len(tables))
	for _, table := range tables {
		var count int
		if err := database.QueryRow(fmt.Sprintf("SELECT COUNT(*) FROM %s", table)).Scan(&count); err != nil {
			t.Fatalf("count %s: %v", table, err)
		}
		counts[table] = count
	}

	return counts
}
