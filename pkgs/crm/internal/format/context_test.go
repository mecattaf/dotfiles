package format

import (
	"bytes"
	"testing"

	"github.com/mecattaf/crm/internal/model"
)

func TestWriteBriefingDocument(t *testing.T) {
	t.Parallel()

	hint := "intro from Jean"
	source := "notes/lead.md"
	detail := "Jean made the introduction"
	email := "nick@kima.vc"
	dossier := "Prefers concise updates."
	category := "vc"
	transcript := "transcripts/2026/nick-call.md"
	note := "Jean introduced Nick"
	briefing := &model.Briefing{
		Contact: &model.Contact{
			ID:                1,
			Name:              "Nick Dupont",
			Email:             &email,
			Context:           &dossier,
			RelationshipHint:  &hint,
			ProvenanceSources: &source,
			ProvenanceDetails: &detail,
		},
		Org: &model.Org{ID: 2, Name: "Kima Ventures", Category: &category},
		Links: []model.ContextLink{{
			Direction: "outgoing",
			Type:      "referred by",
			Note:      &note,
			Contact:   model.Contact{ID: 3, Name: "Jean Martin"},
		}},
		Deals: []model.ContextDeal{{
			Ref: "d4", ID: 4, Title: "Seed ticket", Stage: "pitched", DaysInStage: 6,
		}},
		Timeline: []model.Interaction{{
			ID:             5,
			OccurredOn:     "2026-07-30",
			Kind:           "call",
			Summary:        "partner meeting booked",
			TranscriptPath: &transcript,
		}},
		TimelineTotal: 9,
	}

	var output bytes.Buffer
	if err := WriteBriefing(&output, briefing, FormatTable, false); err != nil {
		t.Fatalf("write briefing document: %v", err)
	}
	want := `# Nick Dupont (c1)
Relationship: intro from Jean
Provenance: notes/lead.md
Provenance detail: Jean made the introduction
Email: nick@kima.vc

Dossier:
Prefers concise updates.

Organization:
  Kima Ventures (o2)
  Category: vc

Links (1):
  c3  Jean Martin  outgoing  referred by — Jean introduced Nick

Deals (1):
  d4  Seed ticket  pitched  6 days in stage

Timeline (9):
  i5  2026-07-30  call  partner meeting booked
    Transcript: transcripts/2026/nick-call.md
`
	if got := output.String(); got != want {
		t.Fatalf("briefing document = %q, want %q", got, want)
	}
}

func TestWriteBriefingJSONIsOneObjectWithEmptyCollections(t *testing.T) {
	t.Parallel()

	briefing := &model.Briefing{
		Org:      &model.Org{Ref: "o1", ID: 1, Name: "Kima Ventures"},
		Links:    make([]model.ContextLink, 0),
		Deals:    make([]model.ContextDeal, 0),
		Timeline: make([]model.Interaction, 0),
	}
	var output bytes.Buffer
	if err := WriteBriefing(&output, briefing, FormatJSON, false); err != nil {
		t.Fatalf("write briefing JSON: %v", err)
	}
	if !bytes.HasPrefix(output.Bytes(), []byte("{")) {
		t.Fatalf("briefing JSON = %q, want one object", output.String())
	}
	for _, fragment := range []string{`"links":[]`, `"deals":[]`, `"timeline":[]`} {
		if !bytes.Contains(output.Bytes(), []byte(fragment)) {
			t.Fatalf("briefing JSON %q omits %s", output.String(), fragment)
		}
	}
}
