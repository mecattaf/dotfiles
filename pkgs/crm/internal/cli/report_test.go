package cli

import (
	"encoding/json"
	"fmt"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

type statusJSONOutput struct {
	Orgs              int     `json:"orgs"`
	Contacts          int     `json:"contacts"`
	Interactions      int     `json:"interactions"`
	OpenDeals         int     `json:"open_deals"`
	LastLogged        *string `json:"last_logged"`
	LastLoggedDaysAgo int     `json:"last_logged_days_ago"`
	NeverContacted    int     `json:"never_contacted"`
	Stale90Days       int     `json:"stale_90d"`
	RottingDeals      int     `json:"rotting_deals"`
	DBPath            string  `json:"db_path"`
}

func TestStatusEmptyHasStableKeysAndResolvedPath(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "empty.db")
	stdout, stderr, code := crm(t, databasePath, "init")
	assertCommandResult(t, stdout, stderr, code, databasePath+"\n", "", 0)

	stdout, stderr, code = crm(t, databasePath, "status")
	want := fmt.Sprintf(
		"[{\"orgs\":0,\"contacts\":0,\"interactions\":0,"+
			"\"open_deals\":0,\"last_logged\":null,\"last_logged_days_ago\":0,"+
			"\"never_contacted\":0,\"stale_90d\":0,\"rotting_deals\":0,"+
			"\"db_path\":%q}]\n",
		databasePath,
	)
	assertCommandResult(t, stdout, stderr, code, want, "", 0)
	assertNoSidecars(t, databasePath)
}

func TestStatusCountsLiveRowsAndRottingDeals(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "crm.db")
	today := time.Now().Format("2006-01-02")
	runReportFixture(t, databasePath,
		[]string{"init"},
		[]string{"org", "add", "Kima Ventures"},
		[]string{"org", "add", "Quiet Org"},
		[]string{"contact", "add", "Never Contact"},
		[]string{"contact", "add", "Old Contact"},
		[]string{"contact", "add", "Fresh Contact", "--org", "kima"},
		[]string{"log", "--with", "c2", "--kind", "note", "--date", "2000-01-01", "--summary", "old touch"},
		[]string{"log", "--with", "c3", "--kind", "note", "--date", today, "--summary", "fresh touch"},
		[]string{"pipeline", "add", "Outreach"},
		[]string{"stage", "add", "p1", "contacted", "--rot", "1"},
		[]string{"deal", "add", "Old open", "--pipeline", "p1", "--org", "kima"},
		[]string{"deal", "add", "Fresh open", "--pipeline", "p1", "--org", "kima"},
		[]string{"deal", "add", "Closed", "--pipeline", "p1", "--org", "kima"},
	)
	backdateDealStage(t, databasePath, "d1", 5*24*time.Hour)
	backdateDealStage(t, databasePath, "d3", 5*24*time.Hour)
	stdout, stderr, code := crm(t, databasePath, "deal", "lose", "d3", "--reason", "passed")
	if stderr != "" || code != 0 {
		t.Fatalf("close deal stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}

	stdout, stderr, code = crm(t, databasePath, "status", "--format", "json")
	if stderr != "" || code != 0 {
		t.Fatalf("status stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	var statuses []statusJSONOutput
	if err := json.Unmarshal([]byte(stdout), &statuses); err != nil {
		t.Fatalf("decode status %q: %v", stdout, err)
	}
	if len(statuses) != 1 {
		t.Fatalf("status rows = %#v, want one", statuses)
	}
	status := statuses[0]
	if status.Orgs != 2 || status.Contacts != 3 || status.Interactions != 2 ||
		status.OpenDeals != 2 || status.LastLogged == nil || *status.LastLogged != today ||
		status.LastLoggedDaysAgo != 0 || status.NeverContacted != 1 ||
		status.Stale90Days != 2 || status.RottingDeals != 1 || status.DBPath != databasePath {
		t.Fatalf("populated status = %#v", status)
	}
	assertNoSidecars(t, databasePath)
}

func TestStaleOrderingOrgTimelineAndIDsComposition(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "crm.db")
	today := time.Now().Format("2006-01-02")
	runReportFixture(t, databasePath,
		[]string{"init"},
		[]string{"org", "add", "Kima Ventures"},
		[]string{"org", "add", "Quiet Org"},
		[]string{"contact", "add", "Never Alpha"},
		[]string{"contact", "add", "Never Beta"},
		[]string{"contact", "add", "Ancient Contact"},
		[]string{"contact", "add", "Older Contact"},
		[]string{"contact", "add", "Fresh Contact", "--org", "kima"},
		[]string{"log", "--with", "c3", "--kind", "note", "--date", "2000-01-01", "--summary", "ancient touch"},
		[]string{"log", "--with", "c4", "--kind", "note", "--date", "2001-01-01", "--summary", "older touch"},
		[]string{"log", "--with", "c5", "--kind", "note", "--date", today, "--summary", "participant-only fresh touch"},
	)

	stdout, stderr, code := crm(t, databasePath, "stale", "--days", "60", "--format", "json")
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"[{\"type\":\"contact\",\"ref\":\"c1\",\"id\":1,\"name\":\"Never Alpha\",\"last\":null},"+
			"{\"type\":\"contact\",\"ref\":\"c2\",\"id\":2,\"name\":\"Never Beta\",\"last\":null},"+
			"{\"type\":\"contact\",\"ref\":\"c3\",\"id\":3,\"name\":\"Ancient Contact\",\"last\":\"2000-01-01\"},"+
			"{\"type\":\"contact\",\"ref\":\"c4\",\"id\":4,\"name\":\"Older Contact\",\"last\":\"2001-01-01\"}]\n",
		"",
		0,
	)

	stdout, stderr, code = crm(
		t,
		databasePath,
		"stale", "--days", "60", "--recent-first", "--format", "ids",
	)
	assertCommandResult(t, stdout, stderr, code, "c4\nc3\nc2\nc1\n", "", 0)
	for _, reference := range strings.Fields(stdout) {
		contextOut, contextErr, contextCode := crm(
			t,
			databasePath,
			"context", reference, "--format", "json",
		)
		if contextErr != "" || contextCode != 0 || contextOut == "" {
			t.Fatalf(
				"stale ids composition %s stdout=%q stderr=%q code=%d",
				reference,
				contextOut,
				contextErr,
				contextCode,
			)
		}
	}

	// Kima's interaction has no interactions.org_id. It is reachable only
	// through its participant, so this assertion distinguishes the full org
	// timeline union from an org_id-only implementation.
	stdout, stderr, code = crm(t, databasePath, "stale", "--type", "org", "--format", "json")
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"[{\"type\":\"org\",\"ref\":\"o2\",\"id\":2,\"name\":\"Quiet Org\",\"last\":null}]\n",
		"",
		0,
	)
	stdout, stderr, code = crm(t, databasePath, "stale", "--type", "org", "--format", "table")
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"TYPE  REF  NAME       LAST\norg   o2   Quiet Org  never\n",
		"",
		0,
	)
	assertNoSidecars(t, databasePath)
}

func TestStaleValidatesFlagsBeforeDatabaseAccess(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "missing.db")
	stdout, stderr, code := crm(t, databasePath, "stale", "--days", "0")
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"",
		"crm: error: stale days must be positive\n",
		1,
	)

	stdout, stderr, code = crm(t, databasePath, "stale", "--type", "deal")
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"",
		"crm: error: invalid stale type \"deal\" (accepted: contact,org)\n",
		1,
	)

	stdout, stderr, code = crm(t, databasePath, "stale", "--format", "csv")
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"",
		"crm: error: unsupported format \"csv\" (accepted: table|json|ids)\n",
		1,
	)
}

func runReportFixture(t *testing.T, databasePath string, commands ...[]string) {
	t.Helper()

	for _, arguments := range commands {
		stdout, stderr, code := crm(t, databasePath, arguments...)
		if stderr != "" || code != 0 {
			t.Fatalf(
				"report fixture command %v stdout=%q stderr=%q code=%d",
				arguments,
				stdout,
				stderr,
				code,
			)
		}
	}
}
