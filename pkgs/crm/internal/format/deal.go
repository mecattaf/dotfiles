package format

import (
	"fmt"
	"io"

	"github.com/mecattaf/crm/internal/model"
)

// WriteDealDetail renders a normal entity row for JSON/ids and augments the
// human table with the deal's chronological history and merged timeline.
func WriteDealDetail(
	output io.Writer,
	row Row,
	columns []ColumnDef,
	detail *model.DealDetail,
	selected Format,
	terminal bool,
) error {
	if detail == nil {
		return fmt.Errorf("write deal detail: nil detail")
	}
	if err := WriteRecords(
		output,
		[]Row{row},
		Options{Format: selected, Terminal: terminal, Columns: columns},
	); err != nil {
		return err
	}
	if selected != FormatTable {
		return nil
	}

	if _, err := fmt.Fprintf(output, "\nStage history (%d):\n", len(detail.StageMoves)); err != nil {
		return fmt.Errorf("write deal stage-history heading: %w", err)
	}
	for _, move := range detail.StageMoves {
		from := "opened"
		if move.FromStageName != nil {
			from = *move.FromStageName
		}
		if _, err := fmt.Fprintf(
			output,
			"  %s  %s → %s",
			move.MovedAt,
			from,
			move.ToStageName,
		); err != nil {
			return fmt.Errorf("write deal stage history: %w", err)
		}
		if move.Note != nil {
			if _, err := fmt.Fprintf(output, " — %s", *move.Note); err != nil {
				return fmt.Errorf("write deal stage note: %w", err)
			}
		}
		if _, err := fmt.Fprintln(output); err != nil {
			return fmt.Errorf("write deal stage-history newline: %w", err)
		}
	}

	if _, err := fmt.Fprintf(output, "\nTimeline (%d):\n", len(detail.Timeline)); err != nil {
		return fmt.Errorf("write deal timeline heading: %w", err)
	}
	for _, entry := range detail.Timeline {
		switch {
		case entry.StageMove != nil:
			from := "opened"
			if entry.StageMove.FromStageName != nil {
				from = *entry.StageMove.FromStageName
			}
			if _, err := fmt.Fprintf(
				output,
				"  %s  stage  %s → %s\n",
				entry.StageMove.MovedAt,
				from,
				entry.StageMove.ToStageName,
			); err != nil {
				return fmt.Errorf("write deal timeline stage move: %w", err)
			}
		case entry.Interaction != nil:
			if _, err := fmt.Fprintf(
				output,
				"  %s  %s  %s  %s\n",
				entry.Interaction.Reference(),
				entry.Interaction.OccurredOn,
				entry.Interaction.Kind,
				entry.Interaction.Summary,
			); err != nil {
				return fmt.Errorf("write deal timeline interaction: %w", err)
			}
		}
	}

	return nil
}
