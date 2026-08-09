package format

import (
	"bytes"
	"strings"
	"testing"

	"github.com/mecattaf/crm/internal/model"
)

func TestWriteDealDetailIncludesHistoryAndTimeline(t *testing.T) {
	t.Parallel()

	note := "deck sent"
	fromID := int64(1)
	fromName := "sourced"
	detail := &model.DealDetail{
		Deal: model.Deal{Ref: "d1", ID: 1, Title: "Seed ticket"},
		StageMoves: []model.StageMove{
			{ID: 1, DealID: 1, ToStageID: 1, ToStageName: "sourced", MovedAt: "2026-07-29T10:00:00Z"},
			{
				ID: 2, DealID: 1, FromStageID: &fromID, FromStageName: &fromName,
				ToStageID: 2, ToStageName: "pitched", MovedAt: "2026-07-30T10:00:00Z", Note: &note,
			},
		},
	}
	detail.Timeline = []model.DealTimelineEntry{
		{Type: "stage_move", OccurredAt: detail.StageMoves[1].MovedAt, StageMove: &detail.StageMoves[1]},
		{
			Type: "interaction", OccurredAt: "2026-07-30",
			Interaction: &model.Interaction{
				ID: 3, OccurredOn: "2026-07-30", Kind: "email", Summary: "sent the deck",
			},
		},
	}
	row := Row{JSON: *detail, Ref: "d1", Cells: map[string]string{"ref": "d1", "title": "Seed ticket"}}
	columns := []ColumnDef{{Header: "REF", Field: "ref"}, {Header: "TITLE", Field: "title"}}

	var output bytes.Buffer
	if err := WriteDealDetail(&output, row, columns, detail, FormatTable, false); err != nil {
		t.Fatalf("write deal detail: %v", err)
	}
	for _, fragment := range []string{
		"Stage history (2):",
		"opened → sourced",
		"sourced → pitched — deck sent",
		"Timeline (2):",
		"i3  2026-07-30  email  sent the deck",
	} {
		if !strings.Contains(output.String(), fragment) {
			t.Fatalf("deal detail %q omits %q", output.String(), fragment)
		}
	}

	output.Reset()
	if err := WriteDealDetail(&output, row, columns, detail, FormatJSON, false); err != nil {
		t.Fatalf("write deal detail JSON: %v", err)
	}
	for _, fragment := range []string{`"stage_moves":[`, `"timeline":[`, `"interaction":`} {
		if !strings.Contains(output.String(), fragment) {
			t.Fatalf("deal detail JSON %q omits %q", output.String(), fragment)
		}
	}
}
