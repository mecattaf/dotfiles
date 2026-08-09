package repo_test

import (
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/mecattaf/crm/internal/db/dbtest"
	"github.com/mecattaf/crm/internal/db/repo"
	"github.com/mecattaf/crm/internal/model"
)

func TestContactRepoCreateAndListByOrg(t *testing.T) {
	t.Parallel()

	database := dbtest.Open(t)
	organization, err := repo.NewOrgRepo(database).Create(
		context.Background(),
		model.CreateOrgInput{Name: "Société Générale"},
	)
	if err != nil {
		t.Fatalf("create organization: %v", err)
	}

	contact, err := repo.NewContactRepo(database).Create(
		context.Background(),
		model.CreateContactInput{
			Name:              " Élodie Martin ",
			OrgID:             &organization.ID,
			JobTitle:          " Partner ",
			Email:             "Elodie@Example.COM",
			Phone:             "+33 6 12 34 56 78",
			LinkedIn:          "https://linkedin.com/in/elodie-martin/",
			Location:          " Paris,   France ",
			Context:           "rolling dossier",
			RelationshipHint:  "intro from Jean",
			ProvenanceSources: []string{" one.md ", "two.md"},
			ProvenanceDetails: []string{" line 1 ", "line 2"},
		},
	)
	if err != nil {
		t.Fatalf("create contact: %v", err)
	}
	if contact.Ref != "c1" || contact.Name != "Élodie Martin" ||
		contact.NameNorm != "elodie martin" {
		t.Fatalf("contact identity = %#v", contact)
	}
	assertStringPointer(t, "email", contact.Email, "elodie@example.com")
	assertStringPointer(t, "phone", contact.Phone, "+33612345678")
	assertStringPointer(t, "linkedin", contact.LinkedIn, "elodie-martin")
	assertStringPointer(t, "location", contact.Location, "Paris, France")
	if contact.OrgID == nil || *contact.OrgID != organization.ID {
		t.Fatalf("org_id = %v, want %d", contact.OrgID, organization.ID)
	}
	if contact.CreatedAt != contact.UpdatedAt {
		t.Fatalf("created_at %q != updated_at %q", contact.CreatedAt, contact.UpdatedAt)
	}

	listed, err := repo.NewContactRepo(database).List(
		context.Background(),
		model.ContactFilters{OrgID: &organization.ID},
	)
	if err != nil {
		t.Fatalf("list contacts by org: %v", err)
	}
	if len(listed) != 1 || listed[0].ID != contact.ID {
		t.Fatalf("listed contacts = %#v", listed)
	}
}

func TestContactRepoTranslatesDuplicateEmailAndPreservesNoop(t *testing.T) {
	t.Parallel()

	database := dbtest.Open(t)
	repository := repo.NewContactRepo(database)
	owner, err := repository.Create(
		context.Background(),
		model.CreateContactInput{Name: "Nick Dupont", Email: "Nick@Kima.VC"},
	)
	if err != nil {
		t.Fatalf("create owner: %v", err)
	}

	_, err = repository.Create(
		context.Background(),
		model.CreateContactInput{Name: "Other Guy", Email: "NICK@KIMA.VC"},
	)
	if !errors.Is(err, model.ErrConflict) {
		t.Fatalf("duplicate create error = %v, want conflict", err)
	}
	if got, want := err.Error(), `duplicate email "nick@kima.vc" — already on contact 1 (Nick Dupont)`; got != want {
		t.Fatalf("duplicate create error = %q, want %q", got, want)
	}

	const oldTimestamp = "2020-01-02T03:04:05Z"
	if _, err := database.Exec(
		"UPDATE contacts SET updated_at = ? WHERE id = ?",
		oldTimestamp,
		owner.ID,
	); err != nil {
		t.Fatalf("backdate owner: %v", err)
	}
	sameEmail := "NICK@KIMA.VC"
	unchanged, err := repository.Update(
		context.Background(),
		owner.ID,
		model.UpdateContactInput{Email: &sameEmail},
	)
	if err != nil {
		t.Fatalf("idempotent email update: %v", err)
	}
	if unchanged.UpdatedAt != oldTimestamp {
		t.Fatalf("no-op updated_at = %q, want %q", unchanged.UpdatedAt, oldTimestamp)
	}

	other, err := repository.Create(
		context.Background(),
		model.CreateContactInput{Name: "Ana", Email: "ana@example.com"},
	)
	if err != nil {
		t.Fatalf("create second contact: %v", err)
	}
	duplicate := "nick@kima.vc"
	_, err = repository.Update(
		context.Background(),
		other.ID,
		model.UpdateContactInput{Email: &duplicate},
	)
	if !errors.Is(err, model.ErrConflict) || !strings.Contains(err.Error(), "contact 1 (Nick Dupont)") {
		t.Fatalf("duplicate update error = %v, want owner-naming conflict", err)
	}

	var count int
	if err := database.QueryRow("SELECT COUNT(*) FROM contacts").Scan(&count); err != nil {
		t.Fatalf("count contacts: %v", err)
	}
	if count != 2 {
		t.Fatalf("contact count = %d, want 2", count)
	}
}

func TestContactRepoUpdateIsTruePatchIncludingOrgClear(t *testing.T) {
	t.Parallel()

	database := dbtest.Open(t)
	organization, err := repo.NewOrgRepo(database).Create(
		context.Background(),
		model.CreateOrgInput{Name: "Kima Ventures"},
	)
	if err != nil {
		t.Fatalf("create organization: %v", err)
	}
	repository := repo.NewContactRepo(database)
	contact, err := repository.Create(
		context.Background(),
		model.CreateContactInput{
			Name:              "Nick Dupont",
			OrgID:             &organization.ID,
			JobTitle:          "Partner",
			Email:             "nick@kima.vc",
			Phone:             "+33612345678",
			LinkedIn:          "nick-dupont",
			Location:          "Paris",
			Context:           "original dossier",
			RelationshipHint:  "intro",
			ProvenanceSources: []string{"one.md"},
			ProvenanceDetails: []string{"line 1"},
		},
	)
	if err != nil {
		t.Fatalf("create contact: %v", err)
	}

	empty := ""
	clearOrg := (*int64)(nil)
	updated, err := repository.Update(
		context.Background(),
		contact.ID,
		model.UpdateContactInput{
			OrgID:             &clearOrg,
			JobTitle:          &empty,
			Email:             &empty,
			Phone:             &empty,
			LinkedIn:          &empty,
			Location:          &empty,
			ContextAppend:     stringPointer("new intelligence"),
			RelationshipHint:  &empty,
			ProvenanceSources: []string{"two.md"},
			ProvenanceDetails: []string{"line 2"},
		},
	)
	if err != nil {
		t.Fatalf("update contact: %v", err)
	}
	if updated.OrgID != nil || updated.JobTitle != nil || updated.Email != nil ||
		updated.Phone != nil || updated.LinkedIn != nil || updated.Location != nil ||
		updated.RelationshipHint != nil {
		t.Fatalf("cleared contact fields = %#v", updated)
	}
	assertStringPointer(t, "context", updated.Context, "original dossier\n\nnew intelligence")
	assertStringPointer(t, "sources", updated.ProvenanceSources, "one.md || two.md")
	assertStringPointer(t, "details", updated.ProvenanceDetails, "line 1 || line 2")
}
