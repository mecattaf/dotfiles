package resolve_test

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"testing"

	"github.com/mecattaf/crm/internal/db/dbtest"
	"github.com/mecattaf/crm/internal/model"
	"github.com/mecattaf/crm/internal/resolve"
)

const fixtureTimestamp = "2026-07-31T12:00:00Z"

func TestRefWalksTheSevenRungsInOrder(t *testing.T) {
	t.Parallel()

	database := dbtest.Open(t)
	archivedID := insertOrg(t, database, "Archive Only", "archived-handle", true)
	legerID := insertOrg(t, database, "Léger Capital", "leger-capital", false)
	handleWinnerID := insertOrg(t, database, "Handle Winner", "needle", false)
	_ = insertOrg(t, database, "needle", "", false)
	_ = insertOrg(t, database, "Kima Ventures", "", false)
	_ = insertOrg(t, database, "Kima Partners", "", false)

	contactExactID := insertContact(t, database, "José", "nick@example.com", "jose-profile")
	contactNameID := insertContact(t, database, "jose", "other@example.com", "other-profile")

	pipelineID, stageID := insertPipelineAndStage(t, database, "Seed Raise", "Sourced")
	dealID := insertDeal(t, database, "Kima ticket", pipelineID, stageID, legerID)

	tests := []struct {
		name   string
		entity resolve.Entity
		ref    string
		wantID int64
	}{
		{name: "prefixed id reaches archived", entity: resolve.EntityOrg, ref: fmt.Sprintf("o%d", archivedID), wantID: archivedID},
		{name: "bare id reaches archived", entity: resolve.EntityOrg, ref: fmt.Sprintf("%d", archivedID), wantID: archivedID},
		{name: "exact email is lowercased", entity: resolve.EntityContact, ref: "NICK@EXAMPLE.COM", wantID: contactExactID},
		{name: "linkedin URL is reduced to a handle", entity: resolve.EntityOrg, ref: "https://linkedin.com/company/needle/", wantID: handleWinnerID},
		{name: "linkedin rung beats exact name", entity: resolve.EntityOrg, ref: "needle", wantID: handleWinnerID},
		{name: "exact name beats ambiguous name norm", entity: resolve.EntityContact, ref: "jose", wantID: contactNameID},
		{name: "exact normalized name strips accents", entity: resolve.EntityOrg, ref: "leger capital", wantID: legerID},
		{name: "substring on normalized name", entity: resolve.EntityOrg, ref: "leger", wantID: legerID},
		{name: "deal title uses the name rung", entity: resolve.EntityDeal, ref: "Kima ticket", wantID: dealID},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			match, err := resolve.Ref(context.Background(), database, test.entity, test.ref)
			if err != nil {
				t.Fatalf("resolve %s %q: %v", test.entity, test.ref, err)
			}
			if match.ID != test.wantID {
				t.Fatalf("resolved id = %d, want %d: %#v", match.ID, test.wantID, match)
			}
			if match.Ref == "" || !strings.HasSuffix(match.Ref, fmt.Sprintf("%d", test.wantID)) {
				t.Fatalf("resolved ref = %q, want pasteable id for %d", match.Ref, test.wantID)
			}
		})
	}
}

func TestRefExcludesArchivedRowsFromNonIDRungs(t *testing.T) {
	t.Parallel()

	database := dbtest.Open(t)
	archivedID := insertOrg(t, database, "Archive Only", "archive-linkedin", true)

	for _, ref := range []string{"Archive Only", "archive only", "archive", "archive-linkedin"} {
		_, err := resolve.Ref(context.Background(), database, resolve.EntityOrg, ref)
		if !errors.Is(err, model.ErrNotFound) {
			t.Fatalf("resolve archived org by %q error = %v, want not found", ref, err)
		}
	}

	match, err := resolve.ArchivedRefForConflict(
		context.Background(),
		database,
		resolve.EntityOrg,
		"archive",
	)
	if err != nil || match.ID != archivedID {
		t.Fatalf("archived conflict probe = %#v, %v; want id %d", match, err, archivedID)
	}
}

func TestRefReportsAmbiguityWithTwoPasteableCandidates(t *testing.T) {
	t.Parallel()

	database := dbtest.Open(t)
	firstID := insertOrg(t, database, "Kima Ventures", "", false)
	secondID := insertOrg(t, database, "Kima Partners", "", false)
	_ = insertOrg(t, database, "Kima Labs", "", false)

	_, err := resolve.Ref(context.Background(), database, resolve.EntityOrg, "kima")
	if !errors.Is(err, model.ErrAmbiguous) {
		t.Fatalf("ambiguous error = %v, want ErrAmbiguous", err)
	}
	var ambiguous *resolve.AmbiguousError
	if !errors.As(err, &ambiguous) {
		t.Fatalf("ambiguous error type = %T, want *resolve.AmbiguousError", err)
	}
	if len(ambiguous.Candidates) != 2 {
		t.Fatalf("candidate count = %d, want LIMIT 2: %#v", len(ambiguous.Candidates), ambiguous.Candidates)
	}
	wantRefs := []string{fmt.Sprintf("o%d", firstID), fmt.Sprintf("o%d", secondID)}
	for index, wantRef := range wantRefs {
		candidate := ambiguous.Candidates[index]
		if candidate.Ref != wantRef || !strings.HasPrefix(candidate.Line(), wantRef+"  Kima") {
			t.Fatalf("candidate %d = %#v (%q), want ref %q with pasteable line", index, candidate, candidate.Line(), wantRef)
		}
		if !strings.Contains(err.Error(), candidate.Line()) {
			t.Fatalf("ambiguity message %q omits candidate %q", err, candidate.Line())
		}
	}
}

func TestRefRejectsWrongEntityPrefix(t *testing.T) {
	t.Parallel()

	database := dbtest.Open(t)
	_, err := resolve.Ref(context.Background(), database, resolve.EntityOrg, "c12")
	if !errors.Is(err, model.ErrNotFound) {
		t.Fatalf("wrong-prefix error = %v, want ErrNotFound", err)
	}
	if got, want := err.Error(), `ref "c12" names a contact, not an org`; got != want {
		t.Fatalf("wrong-prefix message = %q, want %q", got, want)
	}

	_, err = resolve.Ref(context.Background(), database, resolve.EntityContact, "o12")
	if got, want := err.Error(), `ref "o12" names an org, not a contact`; got != want {
		t.Fatalf("reverse wrong-prefix message = %q, want %q", got, want)
	}
}

func TestContactOrOrgRefResolvesBothAndRejectsCrossEntityAmbiguity(t *testing.T) {
	t.Parallel()

	database := dbtest.Open(t)
	orgID := insertOrg(t, database, "Atlas", "atlas-org", false)
	contactID := insertContact(t, database, "Atlas", "atlas@example.com", "atlas-contact")

	for _, test := range []struct {
		name       string
		ref        string
		wantEntity resolve.Entity
		wantID     int64
	}{
		{name: "prefixed contact", ref: fmt.Sprintf("c%d", contactID), wantEntity: resolve.EntityContact, wantID: contactID},
		{name: "prefixed org", ref: fmt.Sprintf("o%d", orgID), wantEntity: resolve.EntityOrg, wantID: orgID},
		{name: "contact email", ref: "ATLAS@EXAMPLE.COM", wantEntity: resolve.EntityContact, wantID: contactID},
		{name: "org linkedin", ref: "atlas-org", wantEntity: resolve.EntityOrg, wantID: orgID},
	} {
		t.Run(test.name, func(t *testing.T) {
			match, err := resolve.ContactOrOrgRef(context.Background(), database, test.ref)
			if err != nil {
				t.Fatalf("resolve context ref %q: %v", test.ref, err)
			}
			if match.Entity != test.wantEntity || match.ID != test.wantID {
				t.Fatalf("context match = %#v, want %s %d", match, test.wantEntity, test.wantID)
			}
		})
	}

	_, err := resolve.ContactOrOrgRef(context.Background(), database, "Atlas")
	if !errors.Is(err, model.ErrAmbiguous) {
		t.Fatalf("cross-entity collision error = %v, want ambiguous", err)
	}
	var ambiguous *resolve.AmbiguousError
	if !errors.As(err, &ambiguous) || len(ambiguous.Candidates) != 2 {
		t.Fatalf("cross-entity candidates = %#v, want two", ambiguous)
	}
	if got, want := ambiguous.Candidates[0].Ref, fmt.Sprintf("c%d", contactID); got != want {
		t.Fatalf("first cross-entity candidate = %q, want %q", got, want)
	}
	if got, want := ambiguous.Candidates[1].Ref, fmt.Sprintf("o%d", orgID); got != want {
		t.Fatalf("second cross-entity candidate = %q, want %q", got, want)
	}

	_, err = resolve.ContactOrOrgRef(context.Background(), database, "i12")
	if !errors.Is(err, model.ErrNotFound) {
		t.Fatalf("context wrong-prefix error = %v, want not found", err)
	}
	if got, want := err.Error(), `ref "i12" names an interaction, not a contact or org`; got != want {
		t.Fatalf("context wrong-prefix message = %q, want %q", got, want)
	}

	_, err = resolve.ContactOrOrgRef(context.Background(), database, "missing")
	if got, want := err.Error(), `no contact or org "missing" — try: crm find missing`; got != want {
		t.Fatalf("context missing message = %q, want %q", got, want)
	}
}

func TestStageRefIsScopedToOnePipeline(t *testing.T) {
	t.Parallel()

	database := dbtest.Open(t)
	firstPipelineID, firstStageID := insertPipelineAndStage(t, database, "Seed", "First Contact")
	secondStageID := insertStage(t, database, firstPipelineID, "Final Contact", false)
	archivedStageID := insertStage(t, database, firstPipelineID, "Archived", true)
	otherPipelineID, _ := insertPipelineAndStage(t, database, "Growth", "First Contact")

	match, err := resolve.StageRef(context.Background(), database, firstPipelineID, "first contact")
	if err != nil || match.ID != firstStageID {
		t.Fatalf("resolve exact scoped stage = %#v, %v; want id %d", match, err, firstStageID)
	}

	_, err = resolve.StageRef(context.Background(), database, firstPipelineID, "contact")
	if !errors.Is(err, model.ErrAmbiguous) {
		t.Fatalf("ambiguous scoped stage error = %v, want ErrAmbiguous", err)
	}

	match, err = resolve.StageRef(
		context.Background(),
		database,
		firstPipelineID,
		fmt.Sprintf("s%d", archivedStageID),
	)
	if err != nil || match.ID != archivedStageID {
		t.Fatalf("resolve archived scoped stage id = %#v, %v", match, err)
	}

	_, err = resolve.StageRef(context.Background(), database, firstPipelineID, "Archived")
	if !errors.Is(err, model.ErrNotFound) {
		t.Fatalf("resolve archived scoped stage name error = %v, want not found", err)
	}
	match, err = resolve.ArchivedStageRefForConflict(
		context.Background(),
		database,
		firstPipelineID,
		"Archived",
	)
	if err != nil || match.ID != archivedStageID {
		t.Fatalf("archived stage conflict probe = %#v, %v; want id %d", match, err, archivedStageID)
	}

	_, err = resolve.StageRef(context.Background(), database, otherPipelineID, fmt.Sprintf("s%d", secondStageID))
	if !errors.Is(err, model.ErrNotFound) {
		t.Fatalf("cross-pipeline stage error = %v, want ErrNotFound", err)
	}
}

func TestReferenceFailureRemedies(t *testing.T) {
	t.Parallel()

	database := dbtest.Open(t)
	_, err := resolve.Ref(context.Background(), database, resolve.EntityOrg, "no such org")
	if got, want := err.Error(), `no org "no such org" — try: crm find "no such org"`; got != want {
		t.Fatalf("ordinary not-found message = %q, want %q", got, want)
	}
	if !errors.Is(err, model.ErrNotFound) {
		t.Fatalf("ordinary not-found classification = %v, want ErrNotFound", err)
	}

	for _, test := range []struct {
		entity resolve.Entity
		ref    string
		want   string
	}{
		{entity: resolve.EntityOrg, ref: "kima", want: `no org "kima" — try: crm org add "kima"`},
		{entity: resolve.EntityContact, ref: "Nick Dupont", want: `no contact "Nick Dupont" — try: crm contact add "Nick Dupont"`},
		{entity: resolve.EntityDeal, ref: "Seed ticket", want: `no deal "Seed ticket" — try: crm deal add "Seed ticket"`},
		{entity: resolve.EntityPipeline, ref: "Seed", want: `no pipeline "Seed" — try: crm pipeline add "Seed"`},
	} {
		t.Run(string(test.entity), func(t *testing.T) {
			linkErr := resolve.LinkNotFound(test.entity, test.ref)
			if got := linkErr.Error(); got != test.want {
				t.Fatalf("link remedy = %q, want %q", got, test.want)
			}
			if !errors.Is(linkErr, model.ErrNotFound) {
				t.Fatalf("link remedy classification = %v, want ErrNotFound", linkErr)
			}
		})
	}
}

func TestLinkRefAddsRemedyWithoutMaskingWrongPrefix(t *testing.T) {
	t.Parallel()

	database := dbtest.Open(t)
	_, err := resolve.LinkRef(context.Background(), database, resolve.EntityOrg, "nosuchorg")
	if got, want := err.Error(), `no org "nosuchorg" — try: crm org add "nosuchorg"`; got != want {
		t.Fatalf("link miss = %q, want %q", got, want)
	}
	if !errors.Is(err, model.ErrNotFound) {
		t.Fatalf("link miss classification = %v, want not found", err)
	}

	_, err = resolve.LinkRef(context.Background(), database, resolve.EntityOrg, "c12")
	if got, want := err.Error(), `ref "c12" names a contact, not an org`; got != want {
		t.Fatalf("wrong-prefix link miss = %q, want %q", got, want)
	}
}

func TestPrefixedEntityAcceptsOnlyPositivePasteableRefs(t *testing.T) {
	t.Parallel()

	for _, test := range []struct {
		ref        string
		wantEntity resolve.Entity
		wantOK     bool
	}{
		{ref: "c12", wantEntity: resolve.EntityContact, wantOK: true},
		{ref: " o4 ", wantEntity: resolve.EntityOrg, wantOK: true},
		{ref: "nick", wantOK: false},
		{ref: "c0", wantOK: false},
		{ref: "x1", wantOK: false},
	} {
		entity, ok := resolve.PrefixedEntity(test.ref)
		if entity != test.wantEntity || ok != test.wantOK {
			t.Fatalf("PrefixedEntity(%q) = (%q, %t), want (%q, %t)", test.ref, entity, ok, test.wantEntity, test.wantOK)
		}
	}
}

func insertOrg(t *testing.T, database *sql.DB, name, linkedIn string, archived bool) int64 {
	t.Helper()

	nameNorm, _ := model.NormalizeName(name)
	var linkedInValue any
	if linkedIn != "" {
		linkedInValue = linkedIn
	}
	var archivedAt any
	if archived {
		archivedAt = fixtureTimestamp
	}
	result, err := database.Exec(
		`INSERT INTO orgs (name, name_norm, linkedin, created_at, updated_at, archived_at)
		 VALUES (?, ?, ?, ?, ?, ?)`,
		name,
		nameNorm,
		linkedInValue,
		fixtureTimestamp,
		fixtureTimestamp,
		archivedAt,
	)
	if err != nil {
		t.Fatalf("insert org %q: %v", name, err)
	}
	id, err := result.LastInsertId()
	if err != nil {
		t.Fatalf("read org %q id: %v", name, err)
	}

	return id
}

func insertContact(t *testing.T, database *sql.DB, name, email, linkedIn string) int64 {
	t.Helper()

	nameNorm, _ := model.NormalizeName(name)
	result, err := database.Exec(
		`INSERT INTO contacts (name, name_norm, email, linkedin, created_at, updated_at)
		 VALUES (?, ?, ?, ?, ?, ?)`,
		name,
		nameNorm,
		email,
		linkedIn,
		fixtureTimestamp,
		fixtureTimestamp,
	)
	if err != nil {
		t.Fatalf("insert contact %q: %v", name, err)
	}
	id, err := result.LastInsertId()
	if err != nil {
		t.Fatalf("read contact %q id: %v", name, err)
	}

	return id
}

func insertPipelineAndStage(t *testing.T, database *sql.DB, pipelineName, stageName string) (int64, int64) {
	t.Helper()

	pipelineNorm, _ := model.NormalizeName(pipelineName)
	result, err := database.Exec(
		`INSERT INTO pipelines (name, name_norm, position, created_at, updated_at)
		 VALUES (?, ?, 1, ?, ?)`,
		pipelineName,
		pipelineNorm,
		fixtureTimestamp,
		fixtureTimestamp,
	)
	if err != nil {
		t.Fatalf("insert pipeline %q: %v", pipelineName, err)
	}
	pipelineID, err := result.LastInsertId()
	if err != nil {
		t.Fatalf("read pipeline %q id: %v", pipelineName, err)
	}

	return pipelineID, insertStage(t, database, pipelineID, stageName, false)
}

func insertStage(t *testing.T, database *sql.DB, pipelineID int64, name string, archived bool) int64 {
	t.Helper()

	nameNorm, _ := model.NormalizeName(name)
	var archivedAt any
	if archived {
		archivedAt = fixtureTimestamp
	}
	result, err := database.Exec(
		`INSERT INTO stages (pipeline_id, name, name_norm, position, created_at, updated_at, archived_at)
		 VALUES (?, ?, ?, (SELECT COUNT(*) + 1 FROM stages WHERE pipeline_id = ?), ?, ?, ?)`,
		pipelineID,
		name,
		nameNorm,
		pipelineID,
		fixtureTimestamp,
		fixtureTimestamp,
		archivedAt,
	)
	if err != nil {
		t.Fatalf("insert stage %q: %v", name, err)
	}
	id, err := result.LastInsertId()
	if err != nil {
		t.Fatalf("read stage %q id: %v", name, err)
	}

	return id
}

func insertDeal(t *testing.T, database *sql.DB, title string, pipelineID, stageID, orgID int64) int64 {
	t.Helper()

	titleNorm, _ := model.NormalizeName(title)
	result, err := database.Exec(
		`INSERT INTO deals (
			title, title_norm, org_id, pipeline_id, stage_id, stage_changed_at,
			created_at, updated_at
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
		title,
		titleNorm,
		orgID,
		pipelineID,
		stageID,
		fixtureTimestamp,
		fixtureTimestamp,
		fixtureTimestamp,
	)
	if err != nil {
		t.Fatalf("insert deal %q: %v", title, err)
	}
	id, err := result.LastInsertId()
	if err != nil {
		t.Fatalf("read deal %q id: %v", title, err)
	}

	return id
}
