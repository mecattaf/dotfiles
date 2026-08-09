package repo_test

import (
	"context"
	"reflect"
	"testing"
	"time"

	"github.com/mecattaf/crm/internal/db/dbtest"
	"github.com/mecattaf/crm/internal/db/repo"
	"github.com/mecattaf/crm/internal/model"
)

func TestReportStatusCoalescesEmptyAggregates(t *testing.T) {
	t.Parallel()

	database := dbtest.Open(t)
	status, err := repo.NewReportRepo(database).Status(context.Background())
	if err != nil {
		t.Fatalf("load empty status: %v", err)
	}

	want := model.StatusReport{}
	if !reflect.DeepEqual(*status, want) {
		t.Fatalf("empty status = %#v, want %#v", *status, want)
	}
}

func TestReportStaleKeepsNeverContactedAndReversesDeterministically(t *testing.T) {
	t.Parallel()

	ctx := context.Background()
	database := dbtest.Open(t)
	contacts := repo.NewContactRepo(database)
	interactions := repo.NewInteractionRepo(database)

	fresh, err := contacts.Create(ctx, model.CreateContactInput{Name: "Fresh Contact"})
	if err != nil {
		t.Fatalf("create fresh contact: %v", err)
	}
	for _, name := range []string{"Never Alpha", "Never Beta"} {
		if _, err := contacts.Create(ctx, model.CreateContactInput{Name: name}); err != nil {
			t.Fatalf("create %s: %v", name, err)
		}
	}
	old, err := contacts.Create(ctx, model.CreateContactInput{Name: "Old Contact"})
	if err != nil {
		t.Fatalf("create old contact: %v", err)
	}
	if _, err := interactions.Create(ctx, model.CreateInteractionInput{
		Kind:       "note",
		OccurredOn: time.Now().Format("2006-01-02"),
		Summary:    "fresh touch",
		ContactIDs: []int64{fresh.ID},
	}); err != nil {
		t.Fatalf("create fresh interaction: %v", err)
	}
	if _, err := interactions.Create(ctx, model.CreateInteractionInput{
		Kind:       "note",
		OccurredOn: "2000-01-01",
		Summary:    "old touch",
		ContactIDs: []int64{old.ID},
	}); err != nil {
		t.Fatalf("create old interaction: %v", err)
	}

	repository := repo.NewReportRepo(database)
	oldestFirst, err := repository.Stale(ctx, model.StaleFilters{Days: 60})
	if err != nil {
		t.Fatalf("load stale contacts: %v", err)
	}
	assertStaleRefs(t, oldestFirst, "c2", "c3", "c4")
	if oldestFirst[0].Last != nil || oldestFirst[1].Last != nil ||
		oldestFirst[2].Last == nil || *oldestFirst[2].Last != "2000-01-01" {
		t.Fatalf("stale last-touch values = %#v", oldestFirst)
	}

	recentFirst, err := repository.Stale(
		ctx,
		model.StaleFilters{Days: 60, RecentFirst: true},
	)
	if err != nil {
		t.Fatalf("load reverse stale contacts: %v", err)
	}
	assertStaleRefs(t, recentFirst, "c4", "c3", "c2")
}

func TestReportStaleOrgIncludesParticipantOnlyTimeline(t *testing.T) {
	t.Parallel()

	ctx := context.Background()
	database := dbtest.Open(t)
	organizations := repo.NewOrgRepo(database)
	contacts := repo.NewContactRepo(database)
	interactions := repo.NewInteractionRepo(database)

	touched, err := organizations.Create(ctx, model.CreateOrgInput{Name: "Touched Org"})
	if err != nil {
		t.Fatalf("create touched organization: %v", err)
	}
	untouched, err := organizations.Create(ctx, model.CreateOrgInput{Name: "Untouched Org"})
	if err != nil {
		t.Fatalf("create untouched organization: %v", err)
	}
	direct, err := organizations.Create(ctx, model.CreateOrgInput{Name: "Direct Org"})
	if err != nil {
		t.Fatalf("create direct organization: %v", err)
	}
	participant, err := contacts.Create(ctx, model.CreateContactInput{
		Name:  "Participant",
		OrgID: &touched.ID,
	})
	if err != nil {
		t.Fatalf("create participant: %v", err)
	}
	if _, err := interactions.Create(ctx, model.CreateInteractionInput{
		Kind:       "note",
		OccurredOn: time.Now().Format("2006-01-02"),
		Summary:    "participant-only touch",
		ContactIDs: []int64{participant.ID},
	}); err != nil {
		t.Fatalf("create participant-only interaction: %v", err)
	}
	if _, err := interactions.Create(ctx, model.CreateInteractionInput{
		Kind:       "note",
		OccurredOn: time.Now().Format("2006-01-02"),
		Summary:    "direct touch",
		OrgID:      &direct.ID,
	}); err != nil {
		t.Fatalf("create direct organization interaction: %v", err)
	}

	results, err := repo.NewReportRepo(database).Stale(
		ctx,
		model.StaleFilters{Days: 60, Type: "org"},
	)
	if err != nil {
		t.Fatalf("load stale organizations: %v", err)
	}
	assertStaleRefs(t, results, untouched.Reference())
	if results[0].Last != nil {
		t.Fatalf("untouched organization last = %v, want nil", results[0].Last)
	}
}

func assertStaleRefs(t *testing.T, results []model.StaleResult, refs ...string) {
	t.Helper()

	got := make([]string, len(results))
	for index, result := range results {
		got[index] = result.Ref
	}
	if !reflect.DeepEqual(got, refs) {
		t.Fatalf("stale refs = %v, want %v; results=%#v", got, refs, results)
	}
}
