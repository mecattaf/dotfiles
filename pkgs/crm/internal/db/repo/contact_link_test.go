package repo_test

import (
	"context"
	"errors"
	"testing"

	"github.com/mecattaf/crm/internal/db/dbtest"
	"github.com/mecattaf/crm/internal/db/repo"
	"github.com/mecattaf/crm/internal/model"
)

func TestContactLinkRepoReadsBothEndsAndTranslatesDuplicates(t *testing.T) {
	t.Parallel()

	database := dbtest.Open(t)
	contacts := repo.NewContactRepo(database)
	nick, err := contacts.Create(context.Background(), model.CreateContactInput{Name: "Nick"})
	if err != nil {
		t.Fatalf("create Nick: %v", err)
	}
	jean, err := contacts.Create(context.Background(), model.CreateContactInput{Name: "Jean"})
	if err != nil {
		t.Fatalf("create Jean: %v", err)
	}

	links := repo.NewContactLinkRepo(database)
	related, err := links.Relate(
		context.Background(),
		nick.ID,
		jean.ID,
		" referred by ",
		" Jean made the intro ",
	)
	if err != nil {
		t.Fatalf("relate contacts: %v", err)
	}
	if len(related.Links) != 1 || related.Links[0].Direction != "outgoing" ||
		related.Links[0].Contact.ID != jean.ID {
		t.Fatalf("origin links = %#v", related.Links)
	}
	if related.Links[0].Type != "referred by" || related.Links[0].Note == nil ||
		*related.Links[0].Note != "Jean made the intro" {
		t.Fatalf("normalized origin link = %#v", related.Links[0])
	}

	farEnd, err := links.FindForContact(context.Background(), jean.ID)
	if err != nil {
		t.Fatalf("find far-end links: %v", err)
	}
	if len(farEnd) != 1 || farEnd[0].Direction != "incoming" ||
		farEnd[0].Contact.ID != nick.ID {
		t.Fatalf("far-end links = %#v", farEnd)
	}

	_, err = links.Relate(
		context.Background(),
		nick.ID,
		jean.ID,
		"referred by",
		"",
	)
	if !errors.Is(err, model.ErrConflict) {
		t.Fatalf("duplicate relate error = %v, want conflict", err)
	}
	if got, want := err.Error(), `duplicate contact link c1 -> c2 with type "referred by"`; got != want {
		t.Fatalf("duplicate relate error = %q, want %q", got, want)
	}

	_, err = links.Relate(context.Background(), nick.ID, nick.ID, "peer", "")
	if !errors.Is(err, model.ErrValidation) ||
		err.Error() != "cannot relate a contact to itself" {
		t.Fatalf("self-link error = %v, want validation", err)
	}
}

func TestContactLinkRepoUnrelateDirectionAndAllDirections(t *testing.T) {
	t.Parallel()

	database := dbtest.Open(t)
	contacts := repo.NewContactRepo(database)
	nick, err := contacts.Create(context.Background(), model.CreateContactInput{Name: "Nick"})
	if err != nil {
		t.Fatalf("create Nick: %v", err)
	}
	jean, err := contacts.Create(context.Background(), model.CreateContactInput{Name: "Jean"})
	if err != nil {
		t.Fatalf("create Jean: %v", err)
	}

	links := repo.NewContactLinkRepo(database)
	for _, fixture := range []struct {
		from     int64
		to       int64
		linkType string
	}{
		{from: nick.ID, to: jean.ID, linkType: "colleague"},
		{from: jean.ID, to: nick.ID, linkType: "colleague"},
		{from: nick.ID, to: jean.ID, linkType: "mentor"},
	} {
		if _, err := links.Relate(
			context.Background(), fixture.from, fixture.to, fixture.linkType, "",
		); err != nil {
			t.Fatalf("relate %d -> %d as %q: %v", fixture.from, fixture.to, fixture.linkType, err)
		}
	}

	colleague := " colleague "
	updated, err := links.Unrelate(context.Background(), nick.ID, jean.ID, &colleague)
	if err != nil {
		t.Fatalf("unrelate one directed type: %v", err)
	}
	if len(updated.Links) != 2 {
		t.Fatalf("links after directed unrelate = %#v, want reverse colleague and mentor", updated.Links)
	}
	for _, link := range updated.Links {
		if link.Direction == "outgoing" && link.Type == "colleague" {
			t.Fatalf("directed colleague link survived: %#v", updated.Links)
		}
	}

	updated, err = links.Unrelate(context.Background(), nick.ID, jean.ID, nil)
	if err != nil {
		t.Fatalf("unrelate all directions: %v", err)
	}
	if len(updated.Links) != 0 {
		t.Fatalf("links after all-direction unrelate = %#v, want none", updated.Links)
	}
	farEnd, err := links.FindForContact(context.Background(), jean.ID)
	if err != nil {
		t.Fatalf("find far end after unrelate: %v", err)
	}
	if len(farEnd) != 0 {
		t.Fatalf("far-end links after unrelate = %#v, want none", farEnd)
	}
}
