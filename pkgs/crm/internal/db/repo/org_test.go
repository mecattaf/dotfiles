package repo_test

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/mecattaf/crm/internal/db/dbtest"
	"github.com/mecattaf/crm/internal/db/repo"
	"github.com/mecattaf/crm/internal/model"
)

func TestOrgRepoCreateNormalizesAndReturnsCompleteRecord(t *testing.T) {
	t.Parallel()

	database := dbtest.Open(t)
	repository := repo.NewOrgRepo(database)
	organization, err := repository.Create(context.Background(), model.CreateOrgInput{
		Name:              " Léger Capital ",
		Category:          " vc ",
		Website:           "https://www.LEGER.VC/?source=test",
		LinkedIn:          "https://linkedin.com/company/leger-capital/",
		Location:          " Paris,   France ",
		Focus:             "pre-seed",
		Context:           "met the team",
		RelationshipHint:  "intro from Jean",
		ProvenanceSources: []string{" first.md ", "second.md"},
		ProvenanceDetails: []string{"line 4", " line 9 "},
	})
	if err != nil {
		t.Fatalf("create organization: %v", err)
	}

	if organization.ID != 1 || organization.Ref != "o1" || organization.Reference() != "o1" {
		t.Fatalf("identity = id %d ref %q", organization.ID, organization.Ref)
	}
	if organization.Name != "Léger Capital" || organization.NameNorm != "leger capital" {
		t.Fatalf("name = %q, normalized = %q", organization.Name, organization.NameNorm)
	}
	assertStringPointer(t, "category", organization.Category, "vc")
	assertStringPointer(t, "website", organization.Website, "leger.vc")
	assertStringPointer(t, "linkedin", organization.LinkedIn, "leger-capital")
	assertStringPointer(t, "location", organization.Location, "Paris, France")
	assertStringPointer(t, "focus", organization.Focus, "pre-seed")
	assertStringPointer(t, "context", organization.Context, "met the team")
	assertStringPointer(t, "hint", organization.RelationshipHint, "intro from Jean")
	assertStringPointer(t, "sources", organization.ProvenanceSources, "first.md || second.md")
	assertStringPointer(t, "details", organization.ProvenanceDetails, "line 4 || line 9")
	if organization.ArchivedAt != nil {
		t.Fatalf("archived_at = %q, want nil", *organization.ArchivedAt)
	}
	for field, value := range map[string]string{
		"created_at": organization.CreatedAt,
		"updated_at": organization.UpdatedAt,
	} {
		parsed, parseErr := time.Parse(time.RFC3339, value)
		if parseErr != nil || parsed.Location() != time.UTC {
			t.Fatalf("%s = %q, want RFC3339 UTC: %v", field, value, parseErr)
		}
	}
	if organization.CreatedAt != organization.UpdatedAt {
		t.Fatalf("created_at %q != updated_at %q", organization.CreatedAt, organization.UpdatedAt)
	}

	listed, err := repository.List(context.Background(), model.OrgFilters{})
	if err != nil {
		t.Fatalf("list organizations: %v", err)
	}
	if len(listed) != 1 || listed[0].NameNorm != "leger capital" {
		t.Fatalf("listed organizations = %#v", listed)
	}
}

func TestOrgRepoTranslatesUniqueNameViolation(t *testing.T) {
	t.Parallel()

	database := dbtest.Open(t)
	repository := repo.NewOrgRepo(database)
	if _, err := repository.Create(
		context.Background(),
		model.CreateOrgInput{Name: "Léger Capital"},
	); err != nil {
		t.Fatalf("create owner: %v", err)
	}

	_, err := repository.Create(
		context.Background(),
		model.CreateOrgInput{Name: "Leger Capital"},
	)
	if !errors.Is(err, model.ErrConflict) {
		t.Fatalf("duplicate error = %v, want conflict", err)
	}
	if !strings.Contains(err.Error(), "o1 (Léger Capital)") {
		t.Fatalf("duplicate error does not name owner: %q", err)
	}

	var count int
	if queryErr := database.QueryRow("SELECT COUNT(*) FROM orgs").Scan(&count); queryErr != nil {
		t.Fatalf("count organizations: %v", queryErr)
	}
	if count != 1 {
		t.Fatalf("organization count = %d, want 1", count)
	}
}

func TestOrgRepoListFiltersArchivedCategoryAndLimit(t *testing.T) {
	t.Parallel()

	database := dbtest.Open(t)
	repository := repo.NewOrgRepo(database)
	for _, input := range []model.CreateOrgInput{
		{Name: "Zulu", Category: "vc"},
		{Name: "Alpha", Category: "customer"},
		{Name: "Bravo", Category: "vc"},
	} {
		if _, err := repository.Create(context.Background(), input); err != nil {
			t.Fatalf("create %s: %v", input.Name, err)
		}
	}
	if _, err := database.Exec(
		"UPDATE orgs SET archived_at = ? WHERE name = ?",
		"2026-07-31T12:00:00Z",
		"Bravo",
	); err != nil {
		t.Fatalf("archive fixture: %v", err)
	}

	category := "vc"
	listed, err := repository.List(context.Background(), model.OrgFilters{
		Category: &category,
		Limit:    1,
	})
	if err != nil {
		t.Fatalf("list live vc organizations: %v", err)
	}
	if len(listed) != 1 || listed[0].Name != "Zulu" {
		t.Fatalf("live vc organizations = %#v", listed)
	}

	listed, err = repository.List(context.Background(), model.OrgFilters{
		Category: &category,
		All:      true,
	})
	if err != nil {
		t.Fatalf("list all vc organizations: %v", err)
	}
	if len(listed) != 2 || listed[0].Name != "Bravo" || listed[1].Name != "Zulu" {
		t.Fatalf("all vc organizations = %#v", listed)
	}
}

func TestOrgRepoUpdateIsTruePatch(t *testing.T) {
	t.Parallel()

	database := dbtest.Open(t)
	repository := repo.NewOrgRepo(database)
	organization, err := repository.Create(context.Background(), model.CreateOrgInput{
		Name:              "Kima Ventures",
		Website:           "kima.vc",
		Context:           "original dossier",
		ProvenanceSources: []string{"n.md"},
		ProvenanceDetails: []string{"line 1"},
	})
	if err != nil {
		t.Fatalf("create organization: %v", err)
	}

	const oldTimestamp = "2020-01-02T03:04:05Z"
	if _, err := database.Exec(
		"UPDATE orgs SET updated_at = ? WHERE id = ?",
		oldTimestamp,
		organization.ID,
	); err != nil {
		t.Fatalf("backdate organization: %v", err)
	}

	updated, err := repository.Update(context.Background(), organization.ID, model.UpdateOrgInput{
		Category:          stringPointer(" investor "),
		Website:           stringPointer("https://www.EXAMPLE.COM/labs?source=test"),
		LinkedIn:          stringPointer("https://linkedin.com/company/kima-ventures/"),
		Location:          stringPointer(" Paris,   France "),
		Focus:             stringPointer("pre-seed"),
		RelationshipHint:  stringPointer("intro from Jean"),
		ContextAppend:     stringPointer("new intelligence"),
		ProvenanceSources: []string{" b.md ", "c.md"},
		ProvenanceDetails: []string{" line 2 "},
	})
	if err != nil {
		t.Fatalf("update organization: %v", err)
	}
	if updated.UpdatedAt == oldTimestamp {
		t.Fatalf("changed update preserved old updated_at %q", oldTimestamp)
	}
	assertStringPointer(t, "category", updated.Category, "investor")
	assertStringPointer(t, "website", updated.Website, "example.com/labs")
	assertStringPointer(t, "linkedin", updated.LinkedIn, "kima-ventures")
	assertStringPointer(t, "location", updated.Location, "Paris, France")
	assertStringPointer(t, "focus", updated.Focus, "pre-seed")
	assertStringPointer(t, "hint", updated.RelationshipHint, "intro from Jean")
	assertStringPointer(t, "context", updated.Context, "original dossier\n\nnew intelligence")
	assertStringPointer(t, "sources", updated.ProvenanceSources, "n.md || b.md || c.md")
	assertStringPointer(t, "details", updated.ProvenanceDetails, "line 1 || line 2")

	unchangedAt := updated.UpdatedAt
	updated, err = repository.Update(context.Background(), organization.ID, model.UpdateOrgInput{
		Focus: stringPointer("pre-seed"),
	})
	if err != nil {
		t.Fatalf("repeat idempotent update: %v", err)
	}
	if updated.UpdatedAt != unchangedAt {
		t.Fatalf("no-op updated_at = %q, want unchanged %q", updated.UpdatedAt, unchangedAt)
	}

	updated, err = repository.Update(context.Background(), organization.ID, model.UpdateOrgInput{})
	if err != nil {
		t.Fatalf("empty patch: %v", err)
	}
	if updated.UpdatedAt != unchangedAt {
		t.Fatalf("empty patch updated_at = %q, want unchanged %q", updated.UpdatedAt, unchangedAt)
	}
}

func TestOrgRepoUpdateClearsNullableFieldsToSQLNull(t *testing.T) {
	t.Parallel()

	database := dbtest.Open(t)
	repository := repo.NewOrgRepo(database)
	organization, err := repository.Create(context.Background(), model.CreateOrgInput{
		Name:             "Clearable",
		Category:         "vc",
		Website:          "clearable.example",
		LinkedIn:         "clearable",
		Location:         "Paris",
		Focus:            "seed",
		Context:          "dossier",
		RelationshipHint: "friend",
	})
	if err != nil {
		t.Fatalf("create organization: %v", err)
	}

	empty := ""
	updated, err := repository.Update(context.Background(), organization.ID, model.UpdateOrgInput{
		Category:         &empty,
		Website:          &empty,
		LinkedIn:         &empty,
		Location:         &empty,
		Focus:            &empty,
		Context:          &empty,
		RelationshipHint: &empty,
	})
	if err != nil {
		t.Fatalf("clear organization: %v", err)
	}
	if updated.Category != nil || updated.Website != nil || updated.LinkedIn != nil ||
		updated.Location != nil || updated.Focus != nil || updated.Context != nil ||
		updated.RelationshipHint != nil {
		t.Fatalf("cleared nullable fields = %#v, want nil pointers", updated)
	}

	var nonNullCount int
	if err := database.QueryRow(
		`SELECT
			(category IS NOT NULL) + (website IS NOT NULL) + (linkedin IS NOT NULL) +
			(location IS NOT NULL) + (focus IS NOT NULL) + (context IS NOT NULL) +
			(relationship_hint IS NOT NULL)
		 FROM orgs WHERE id = ?`,
		organization.ID,
	).Scan(&nonNullCount); err != nil {
		t.Fatalf("inspect cleared SQL values: %v", err)
	}
	if nonNullCount != 0 {
		t.Fatalf("non-NULL cleared field count = %d, want 0", nonNullCount)
	}
}

func stringPointer(value string) *string {
	return &value
}

func assertStringPointer(t *testing.T, field string, got *string, want string) {
	t.Helper()

	if got == nil || *got != want {
		t.Fatalf("%s = %v, want %q", field, got, want)
	}
}
