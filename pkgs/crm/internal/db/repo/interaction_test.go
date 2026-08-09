package repo_test

import (
	"context"
	"errors"
	"reflect"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/mecattaf/crm/internal/db/dbtest"
	"github.com/mecattaf/crm/internal/db/repo"
	"github.com/mecattaf/crm/internal/model"
)

func TestInteractionRepoCreateIsAtomicAndDeduplicatesParticipants(t *testing.T) {
	t.Parallel()

	database := dbtest.Open(t)
	contacts := repo.NewContactRepo(database)
	first, err := contacts.Create(
		context.Background(),
		model.CreateContactInput{Name: "Nick Dupont"},
	)
	if err != nil {
		t.Fatalf("create first contact: %v", err)
	}
	second, err := contacts.Create(
		context.Background(),
		model.CreateContactInput{Name: "Jean Martin"},
	)
	if err != nil {
		t.Fatalf("create second contact: %v", err)
	}

	interaction, err := repo.NewInteractionRepo(database).Create(
		context.Background(),
		model.CreateInteractionInput{
			Kind:       "call",
			OccurredOn: "2026-07-29",
			Summary:    "intro call",
			ContactIDs: []int64{first.ID, first.ID, second.ID},
		},
	)
	if err != nil {
		t.Fatalf("create interaction: %v", err)
	}
	if interaction.Ref != "i1" || interaction.Reference() != "i1" {
		t.Fatalf("interaction identity = %#v", interaction)
	}
	if got, want := interaction.ContactIDs, []int64{first.ID, second.ID}; !reflect.DeepEqual(got, want) {
		t.Fatalf("contact ids = %v, want %v", got, want)
	}

	var participantCount int
	if err := database.QueryRow(
		"SELECT COUNT(*) FROM interaction_people WHERE interaction_id = ?",
		interaction.ID,
	).Scan(&participantCount); err != nil {
		t.Fatalf("count interaction participants: %v", err)
	}
	if participantCount != 2 {
		t.Fatalf("participant count = %d, want 2", participantCount)
	}

	_, err = repo.NewInteractionRepo(database).Create(
		context.Background(),
		model.CreateInteractionInput{
			Kind:       "call",
			OccurredOn: "2026-07-29",
			Summary:    "bad foreign key",
			ContactIDs: []int64{first.ID, 9999},
		},
	)
	if err == nil {
		t.Fatal("create with bad participant succeeded")
	}
	var interactionCount int
	if err := database.QueryRow("SELECT COUNT(*) FROM interactions").Scan(&interactionCount); err != nil {
		t.Fatalf("count interactions: %v", err)
	}
	if interactionCount != 1 {
		t.Fatalf("interaction count after failed atomic write = %d, want 1", interactionCount)
	}
}

func TestInteractionRepoListLoadsParticipantsAfterRowsClose(t *testing.T) {
	t.Parallel()

	database := dbtest.Open(t)
	contact, err := repo.NewContactRepo(database).Create(
		context.Background(),
		model.CreateContactInput{Name: "Nick Dupont"},
	)
	if err != nil {
		t.Fatalf("create contact: %v", err)
	}
	repository := repo.NewInteractionRepo(database)
	for _, input := range []model.CreateInteractionInput{
		{Kind: "email", OccurredOn: "2026-07-28", Summary: "older", ContactIDs: []int64{contact.ID}},
		{Kind: "call", OccurredOn: "2026-07-29", Summary: "same date first", ContactIDs: []int64{contact.ID}},
		{Kind: "call", OccurredOn: "2026-07-29", Summary: "same date second", ContactIDs: []int64{contact.ID}},
	} {
		if _, err := repository.Create(context.Background(), input); err != nil {
			t.Fatalf("create interaction %q: %v", input.Summary, err)
		}
	}

	result := make(chan struct {
		rows []model.Interaction
		err  error
	}, 1)
	go func() {
		rows, listErr := repository.List(
			context.Background(),
			model.InteractionFilters{ContactID: &contact.ID},
		)
		result <- struct {
			rows []model.Interaction
			err  error
		}{rows: rows, err: listErr}
	}()

	select {
	case got := <-result:
		if got.err != nil {
			t.Fatalf("list interactions: %v", got.err)
		}
		wantSummaries := []string{"same date second", "same date first", "older"}
		if len(got.rows) != len(wantSummaries) {
			t.Fatalf("listed interactions = %#v", got.rows)
		}
		for index, want := range wantSummaries {
			if got.rows[index].Summary != want {
				t.Fatalf("interaction %d summary = %q, want %q", index, got.rows[index].Summary, want)
			}
			if !reflect.DeepEqual(got.rows[index].ContactIDs, []int64{contact.ID}) {
				t.Fatalf("interaction %d contact ids = %v", index, got.rows[index].ContactIDs)
			}
		}
	case <-time.After(2 * time.Second):
		t.Fatal("interaction listing hung while batch-loading participants")
	}
}

func TestInteractionRepoUpdateIsTruePatchWithIdempotentSetMembership(t *testing.T) {
	t.Parallel()

	database := dbtest.Open(t)
	contacts := repo.NewContactRepo(database)
	first, err := contacts.Create(context.Background(), model.CreateContactInput{Name: "Nick"})
	if err != nil {
		t.Fatalf("create first contact: %v", err)
	}
	second, err := contacts.Create(context.Background(), model.CreateContactInput{Name: "Jean"})
	if err != nil {
		t.Fatalf("create second contact: %v", err)
	}
	repository := repo.NewInteractionRepo(database)
	interaction, err := repository.Create(
		context.Background(),
		model.CreateInteractionInput{
			Kind: "call", OccurredOn: "2026-07-29", Summary: "intro", ContactIDs: []int64{first.ID},
		},
	)
	if err != nil {
		t.Fatalf("create interaction: %v", err)
	}

	const oldTimestamp = "2020-01-02T03:04:05Z"
	if _, err := database.Exec(
		"UPDATE interactions SET updated_at = ? WHERE id = ?",
		oldTimestamp,
		interaction.ID,
	); err != nil {
		t.Fatalf("backdate interaction: %v", err)
	}

	updated, err := repository.Update(
		context.Background(),
		interaction.ID,
		model.UpdateInteractionInput{
			AddContactIDs:    []int64{second.ID, second.ID},
			RemoveContactIDs: []int64{first.ID},
		},
	)
	if err != nil {
		t.Fatalf("replace participant set: %v", err)
	}
	if !reflect.DeepEqual(updated.ContactIDs, []int64{second.ID}) {
		t.Fatalf("updated contact ids = %v, want [%d]", updated.ContactIDs, second.ID)
	}
	if updated.UpdatedAt == oldTimestamp {
		t.Fatalf("changed membership kept updated_at %q", oldTimestamp)
	}

	unchangedAt := updated.UpdatedAt
	updated, err = repository.Update(
		context.Background(),
		interaction.ID,
		model.UpdateInteractionInput{
			AddContactIDs:    []int64{second.ID},
			RemoveContactIDs: []int64{first.ID},
		},
	)
	if err != nil {
		t.Fatalf("repeat membership patch: %v", err)
	}
	if updated.UpdatedAt != unchangedAt {
		t.Fatalf("idempotent membership edit updated_at = %q, want %q", updated.UpdatedAt, unchangedAt)
	}

	_, err = repository.Update(
		context.Background(),
		interaction.ID,
		model.UpdateInteractionInput{RemoveContactIDs: []int64{second.ID}},
	)
	if !errors.Is(err, model.ErrConflict) {
		t.Fatalf("orphaning patch error = %v, want conflict", err)
	}
	for _, fragment := range []string{"participants=0", "org=none", "deal=none"} {
		if !strings.Contains(err.Error(), fragment) {
			t.Fatalf("orphaning patch error %q omits %q", err, fragment)
		}
	}
	shown, err := repository.FindByID(context.Background(), interaction.ID)
	if err != nil {
		t.Fatalf("show after rejected patch: %v", err)
	}
	if !reflect.DeepEqual(shown.ContactIDs, []int64{second.ID}) {
		t.Fatalf("rejected patch changed contact ids to %v", shown.ContactIDs)
	}
}

func TestInteractionKindsMatchSQLiteCheckConstraint(t *testing.T) {
	t.Parallel()

	database := dbtest.Open(t)
	var tableSQL string
	if err := database.QueryRow(
		"SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'interactions'",
	).Scan(&tableSQL); err != nil {
		t.Fatalf("read interactions DDL: %v", err)
	}

	checkPattern := regexp.MustCompile(`(?i)kind\s+IN\s*\(([^)]*)\)`)
	match := checkPattern.FindStringSubmatch(tableSQL)
	if len(match) != 2 {
		t.Fatalf("interactions DDL has no parsable kind CHECK: %s", tableSQL)
	}
	quotedValue := regexp.MustCompile(`'([^']*)'`)
	valueMatches := quotedValue.FindAllStringSubmatch(match[1], -1)
	databaseKinds := make([]string, 0, len(valueMatches))
	for _, valueMatch := range valueMatches {
		databaseKinds = append(databaseKinds, valueMatch[1])
	}
	if !reflect.DeepEqual(databaseKinds, model.InteractionKinds) {
		t.Fatalf("database kinds = %v, Go kinds = %v", databaseKinds, model.InteractionKinds)
	}
}
