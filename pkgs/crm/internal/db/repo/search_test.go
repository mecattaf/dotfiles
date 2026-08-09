package repo_test

import (
	"context"
	"math"
	"strings"
	"testing"

	"github.com/mecattaf/crm/internal/db/dbtest"
	"github.com/mecattaf/crm/internal/db/repo"
	"github.com/mecattaf/crm/internal/model"
)

func TestSearchRepoNormalizesAndGloballyMergesRanks(t *testing.T) {
	t.Parallel()

	database := dbtest.Open(t)
	ctx := context.Background()
	contact, err := repo.NewContactRepo(database).Create(
		ctx,
		model.CreateContactInput{Name: "Needle"},
	)
	if err != nil {
		t.Fatalf("create exact-name contact: %v", err)
	}
	interactions := repo.NewInteractionRepo(database)
	if _, err := interactions.Create(
		ctx,
		model.CreateInteractionInput{
			Kind: "note", OccurredOn: "2026-07-01", Summary: "Needle",
			ContactIDs: []int64{contact.ID},
		},
	); err != nil {
		t.Fatalf("create strong interaction: %v", err)
	}
	weakBody := strings.Repeat("unrelated filler words ", 80) + "needle"
	if _, err := interactions.Create(
		ctx,
		model.CreateInteractionInput{
			Kind: "meeting", OccurredOn: "2026-07-02", Summary: "Quarterly update",
			Body: &weakBody, ContactIDs: []int64{contact.ID},
		},
	); err != nil {
		t.Fatalf("create weak interaction: %v", err)
	}

	results, err := repo.NewSearchRepo(database).Find(
		ctx,
		"needle",
		model.FindFilters{Limit: 20},
	)
	if err != nil {
		t.Fatalf("find needle: %v", err)
	}
	if len(results) != 3 {
		t.Fatalf("find results = %#v, want three rows", results)
	}

	maxByType := map[string]float64{}
	contactIndex := -1
	weakInteractionIndex := -1
	for index, result := range results {
		if result.Rank > maxByType[result.Type] {
			maxByType[result.Type] = result.Rank
		}
		if result.Ref == contact.Reference() {
			contactIndex = index
		}
		if result.Type == "interaction" && result.Name == "Quarterly update" {
			weakInteractionIndex = index
			if result.Rank >= 1 {
				t.Fatalf("weak interaction rank = %v, want below 1", result.Rank)
			}
		}
	}
	for _, entityType := range []string{"contact", "interaction"} {
		if math.Abs(maxByType[entityType]-1) > 1e-12 {
			t.Fatalf("best %s rank = %v, want 1", entityType, maxByType[entityType])
		}
	}
	if contactIndex < 0 || weakInteractionIndex < 0 || contactIndex >= weakInteractionIndex {
		t.Fatalf(
			"exact contact index = %d, weak interaction index = %d; results=%#v",
			contactIndex,
			weakInteractionIndex,
			results,
		)
	}
}

func TestSearchRepoEscapesPunctuationAndUsesFTSUpdateTrigger(t *testing.T) {
	t.Parallel()

	database := dbtest.Open(t)
	ctx := context.Background()
	contact, err := repo.NewContactRepo(database).Create(
		ctx,
		model.CreateContactInput{Name: "Nick Dupont", Email: "nick@kima.vc"},
	)
	if err != nil {
		t.Fatalf("create contact: %v", err)
	}
	interactions := repo.NewInteractionRepo(database)
	interaction, err := interactions.Create(
		ctx,
		model.CreateInteractionInput{
			Kind: "call", OccurredOn: "2026-07-29", Summary: "legacyterm briefing",
			ContactIDs: []int64{contact.ID},
		},
	)
	if err != nil {
		t.Fatalf("create interaction: %v", err)
	}

	search := repo.NewSearchRepo(database)
	for _, query := range []string{
		"nick@kima.vc",
		"nick.kima",
		"nick-kima",
		"nick:kima",
		`nick"dupont`,
	} {
		results, findErr := search.Find(
			ctx,
			query,
			model.FindFilters{Type: "contact", Limit: 20},
		)
		if findErr != nil {
			t.Fatalf("find punctuation-bearing query %q: %v", query, findErr)
		}
		if len(results) != 1 || results[0].Ref != contact.Reference() {
			t.Fatalf("query %q results = %#v, want %s", query, results, contact.Reference())
		}
	}
	for _, query := range []string{"@", ".", "-", ":"} {
		if _, findErr := search.Find(
			ctx,
			query,
			model.FindFilters{Type: "contact", Limit: 20},
		); findErr != nil {
			t.Fatalf("find punctuation-only query %q: %v", query, findErr)
		}
	}

	newSummary := "replacementterm briefing"
	if _, err := interactions.Update(
		ctx,
		interaction.ID,
		model.UpdateInteractionInput{Summary: &newSummary},
	); err != nil {
		t.Fatalf("update interaction summary: %v", err)
	}
	oldResults, err := search.Find(
		ctx,
		"legacyterm",
		model.FindFilters{Type: "interaction", Limit: 20},
	)
	if err != nil {
		t.Fatalf("find old interaction term: %v", err)
	}
	if len(oldResults) != 0 {
		t.Fatalf("old-term results = %#v, want none", oldResults)
	}
	newResults, err := search.Find(
		ctx,
		"replacementterm",
		model.FindFilters{Type: "interaction", Limit: 20},
	)
	if err != nil {
		t.Fatalf("find replacement interaction term: %v", err)
	}
	if len(newResults) != 1 || newResults[0].Ref != interaction.Reference() {
		t.Fatalf("replacement-term results = %#v, want %s", newResults, interaction.Reference())
	}
}

func TestSearchRepoUnionsOrgContactsAndExcludesArchivedRows(t *testing.T) {
	t.Parallel()

	database := dbtest.Open(t)
	ctx := context.Background()
	organization, err := repo.NewOrgRepo(database).Create(
		ctx,
		model.CreateOrgInput{Name: "Kima Ventures", Category: "vc", Location: "Paris"},
	)
	if err != nil {
		t.Fatalf("create organization: %v", err)
	}
	contact, err := repo.NewContactRepo(database).Create(
		ctx,
		model.CreateContactInput{
			Name: "Alice Martin", OrgID: &organization.ID, Email: "alice@example.com",
		},
	)
	if err != nil {
		t.Fatalf("create linked contact: %v", err)
	}

	search := repo.NewSearchRepo(database)
	results, err := search.Find(
		ctx,
		"kima",
		model.FindFilters{Type: "contact", Limit: 20},
	)
	if err != nil {
		t.Fatalf("find linked contact through organization: %v", err)
	}
	if len(results) != 1 || results[0].Ref != contact.Reference() {
		t.Fatalf("linked contact results = %#v, want %s", results, contact.Reference())
	}
	if results[0].Detail != "alice@example.com · Kima Ventures" {
		t.Fatalf("linked contact detail = %q", results[0].Detail)
	}
	organizationResults, err := search.Find(
		ctx,
		"kima",
		model.FindFilters{Type: "org", Limit: 20},
	)
	if err != nil {
		t.Fatalf("find organization: %v", err)
	}
	if len(organizationResults) != 1 || organizationResults[0].Ref != organization.Reference() {
		t.Fatalf("organization results = %#v, want %s", organizationResults, organization.Reference())
	}
	if organizationResults[0].Detail != "vc · Paris" {
		t.Fatalf("organization detail = %q", organizationResults[0].Detail)
	}

	if _, err := database.Exec(
		"UPDATE contacts SET archived_at = ? WHERE id = ?",
		"2026-07-31T12:00:00Z",
		contact.ID,
	); err != nil {
		t.Fatalf("archive linked contact: %v", err)
	}
	results, err = search.Find(
		ctx,
		"kima",
		model.FindFilters{Type: "contact", Limit: 20},
	)
	if err != nil {
		t.Fatalf("find after archive: %v", err)
	}
	if len(results) != 0 {
		t.Fatalf("archived contact results = %#v, want none", results)
	}
}

func TestSearchRepoDefaultLimitIsTwenty(t *testing.T) {
	t.Parallel()

	database := dbtest.Open(t)
	ctx := context.Background()
	contacts := repo.NewContactRepo(database)
	for index := 1; index <= 21; index++ {
		if _, err := contacts.Create(
			ctx,
			model.CreateContactInput{Name: "Capmatch person " + strings.Repeat("x", index)},
		); err != nil {
			t.Fatalf("create contact %d: %v", index, err)
		}
	}

	results, err := repo.NewSearchRepo(database).Find(
		ctx,
		"capmatch",
		model.FindFilters{Type: "contact"},
	)
	if err != nil {
		t.Fatalf("find with default limit: %v", err)
	}
	if len(results) != 20 {
		t.Fatalf("default-limited results = %d, want 20", len(results))
	}
}

func TestSearchRepoMatchesDiacriticsAndRendersDealDetail(t *testing.T) {
	t.Parallel()

	database := dbtest.Open(t)
	ctx := context.Background()
	contact, err := repo.NewContactRepo(database).Create(
		ctx,
		model.CreateContactInput{Name: "François Léger"},
	)
	if err != nil {
		t.Fatalf("create accented contact: %v", err)
	}
	search := repo.NewSearchRepo(database)
	for _, query := range []string{"Léger", "Leger"} {
		results, findErr := search.Find(
			ctx,
			query,
			model.FindFilters{Type: "contact", Limit: 20},
		)
		if findErr != nil {
			t.Fatalf("find %q: %v", query, findErr)
		}
		if len(results) != 1 || results[0].Ref != contact.Reference() {
			t.Fatalf("find %q results = %#v, want %s", query, results, contact.Reference())
		}
	}

	const timestamp = "2026-07-31T12:00:00Z"
	pipelineResult, err := database.Exec(
		`INSERT INTO pipelines (name, name_norm, position, created_at, updated_at)
		 VALUES (?, ?, ?, ?, ?)`,
		"Seed Raise", "seed raise", 1, timestamp, timestamp,
	)
	if err != nil {
		t.Fatalf("insert pipeline: %v", err)
	}
	pipelineID, err := pipelineResult.LastInsertId()
	if err != nil {
		t.Fatalf("read pipeline id: %v", err)
	}
	stageResult, err := database.Exec(
		`INSERT INTO stages (
			pipeline_id, name, name_norm, position, created_at, updated_at
		 ) VALUES (?, ?, ?, ?, ?, ?)`,
		pipelineID, "Pitched", "pitched", 1, timestamp, timestamp,
	)
	if err != nil {
		t.Fatalf("insert stage: %v", err)
	}
	stageID, err := stageResult.LastInsertId()
	if err != nil {
		t.Fatalf("read stage id: %v", err)
	}
	if _, err := database.Exec(
		`INSERT INTO deals (
			title, title_norm, contact_id, pipeline_id, stage_id,
			stage_changed_at, created_at, updated_at
		 ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
		"Léger dataroom", "leger dataroom", contact.ID, pipelineID, stageID,
		timestamp, timestamp, timestamp,
	); err != nil {
		t.Fatalf("insert deal: %v", err)
	}

	results, err := search.Find(
		ctx,
		"dataroom",
		model.FindFilters{Type: "deal", Limit: 20},
	)
	if err != nil {
		t.Fatalf("find deal: %v", err)
	}
	if len(results) != 1 || results[0].Type != "deal" || results[0].Ref != "d1" {
		t.Fatalf("deal results = %#v", results)
	}
	if results[0].Detail != "Seed Raise · Pitched" {
		t.Fatalf("deal detail = %q", results[0].Detail)
	}
}
