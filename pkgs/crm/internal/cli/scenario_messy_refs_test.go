package cli

import (
	"path/filepath"
	"testing"
)

func TestScenarioMessyRefs(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "crm.db")
	stdout, stderr, code := crm(t, databasePath, "init")
	assertCommandResult(t, stdout, stderr, code, databasePath+"\n", "", 0)

	stdout, stderr, code = crm(t, databasePath, "org", "add", "Société Générale")
	if stderr != "" || code != 0 {
		t.Fatalf("org add stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}

	stdout, stderr, code = crm(
		t,
		databasePath,
		"contact", "add", "Élodie Martin",
		"--org", "societe",
		"--email", "Elodie@Example.COM",
		"--linkedin", "https://linkedin.com/in/elodie-martin/",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("accented contact add stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	elodie := assertCompactContactJSON(t, stdout, 1)[0]
	if elodie.Ref != "c1" || elodie.NameNorm != "elodie martin" {
		t.Fatalf("accented contact = %#v", elodie)
	}

	stdoutWithoutAccent, stderr, code := crm(t, databasePath, "contact", "show", "elodie")
	if stderr != "" || code != 0 {
		t.Fatalf("unaccented show stdout=%q stderr=%q code=%d", stdoutWithoutAccent, stderr, code)
	}
	stdoutWithAccent, stderr, code := crm(t, databasePath, "contact", "show", "élodie")
	assertCommandResult(t, stdoutWithAccent, stderr, code, stdoutWithoutAccent, "", 0)

	for _, fixture := range []struct {
		name  string
		email string
	}{
		{name: "Anaïs Dupont", email: "anais.dupont@example.com"},
		{name: "Anaïs Durand", email: "anais.durand@example.com"},
	} {
		stdout, stderr, code = crm(
			t,
			databasePath,
			"contact", "add", fixture.name,
			"--org", "societe generale",
			"--email", fixture.email,
		)
		if stderr != "" || code != 0 {
			t.Fatalf("contact add %q stdout=%q stderr=%q code=%d", fixture.name, stdout, stderr, code)
		}
	}

	stdout, stderr, code = crm(t, databasePath, "contact", "show", "anais")
	if stdout != "" || code != 3 {
		t.Fatalf("ambiguous show stdout=%q stderr=%q code=%d, want empty/3", stdout, stderr, code)
	}
	assertContainsLines(
		t,
		stderr,
		"crm: error: ambiguous contact \"anais\":\n",
		"c2  Anaïs Dupont  anais.dupont@example.com  @Société Générale",
		"c3  Anaïs Durand  anais.durand@example.com  @Société Générale",
	)

	stdout, stderr, code = crm(
		t,
		databasePath,
		"contact", "add", "Élodie Duplicate",
		"--email", "ELODIE@EXAMPLE.COM",
	)
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"",
		"crm: error: duplicate email \"elodie@example.com\" — already on contact 1 (Élodie Martin)\n",
		4,
	)

	stdout, stderr, code = crm(t, databasePath, "contact", "ls", "--format", "json")
	if stderr != "" || code != 0 {
		t.Fatalf("final contact list stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	contacts := assertCompactContactJSON(t, stdout, 3)
	wantNames := []string{"Anaïs Dupont", "Anaïs Durand", "Élodie Martin"}
	wantNorms := []string{"anais dupont", "anais durand", "elodie martin"}
	wantEmails := []string{
		"anais.dupont@example.com",
		"anais.durand@example.com",
		"elodie@example.com",
	}
	for index, contact := range contacts {
		if contact.Name != wantNames[index] || contact.NameNorm != wantNorms[index] {
			t.Fatalf("final contact %d identity = %#v", index, contact)
		}
		assertInt64Pointer(t, "org_id", contact.OrgID, 1)
		assertStringPointer(t, "email", contact.Email, wantEmails[index])
		if contact.JobTitle != nil || contact.Phone != nil || contact.Location != nil ||
			contact.Context != nil || contact.RelationshipHint != nil ||
			contact.ProvenanceSources != nil || contact.ProvenanceDetails != nil ||
			contact.ArchivedAt != nil {
			t.Fatalf("final contact %s has unexpected optional state: %#v", contact.Ref, contact)
		}
	}
	if contacts[0].LinkedIn != nil || contacts[1].LinkedIn != nil {
		t.Fatalf("Anaïs fixtures unexpectedly gained LinkedIn handles: %#v", contacts[:2])
	}
	assertStringPointer(t, "Elodie linkedin", contacts[2].LinkedIn, "elodie-martin")

	stdout, stderr, code = crm(t, databasePath, "org", "ls", "--format", "ids")
	assertCommandResult(t, stdout, stderr, code, "o1\n", "", 0)

	stdout, stderr, code = crm(t, databasePath, "contact", "archive", "elodie")
	if stderr != "" || code != 0 {
		t.Fatalf("archive accented contact stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	archivedElodie := assertCompactContactJSON(t, stdout, 1)[0]
	if archivedElodie.Ref != "c1" || archivedElodie.ArchivedAt == nil {
		t.Fatalf("archived accented contact = %#v", archivedElodie)
	}

	stdout, stderr, code = crm(t, databasePath, "contact", "ls", "--format", "json")
	if stderr != "" || code != 0 {
		t.Fatalf("live contact list after archive stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	liveContacts := assertCompactContactJSON(t, stdout, 2)
	for _, contact := range liveContacts {
		if contact.Ref == "c1" || contact.ArchivedAt != nil {
			t.Fatalf("live listing contains archived contact: %#v", liveContacts)
		}
	}

	stdout, stderr, code = crm(
		t,
		databasePath,
		"contact", "ls", "--all", "--format", "json",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("all contact list after archive stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	allContacts := assertCompactContactJSON(t, stdout, 3)
	if allContacts[2].Ref != "c1" || allContacts[2].ArchivedAt == nil {
		t.Fatalf("--all listing does not visibly retain archived Élodie: %#v", allContacts)
	}
	assertNoSidecars(t, databasePath)
}
