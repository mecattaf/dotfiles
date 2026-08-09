package format

import (
	"encoding/json"
	"fmt"
	"io"
	"strings"

	"github.com/mecattaf/crm/internal/model"
)

var doctorColumns = []ColumnDef{
	{Header: "CHECK", Field: "check"},
	{Header: "STATUS", Field: "status"},
	{Header: "DETAIL", Field: "detail"},
}

// DoctorFormats returns the human-table and JSON report serializations.
func DoctorFormats() []Format {
	return []Format{FormatTable, FormatJSON}
}

// WriteDoctorReport renders all eight checks as a table or as one keyed JSON
// object. No renderer performs database or filesystem work.
func WriteDoctorReport(
	output io.Writer,
	report model.DoctorReport,
	selected Format,
	pretty bool,
) error {
	switch selected {
	case FormatTable:
		return WriteRecords(
			output,
			doctorRows(report),
			Options{Format: FormatTable, Terminal: pretty, Columns: doctorColumns},
		)
	case FormatJSON:
		encoder := json.NewEncoder(output)
		if pretty {
			encoder.SetIndent("", "  ")
		}
		if err := encoder.Encode(report); err != nil {
			return fmt.Errorf("write doctor JSON output: %w", err)
		}

		return nil
	default:
		return fmt.Errorf("write doctor report: unsupported resolved format %q", selected)
	}
}

func doctorRows(report model.DoctorReport) []Row {
	return []Row{
		doctorRow("integrity_check", report.IntegrityCheck),
		doctorRow("foreign_key_check", report.ForeignKeyCheck),
		{
			Cells: map[string]string{
				"check":  "fts",
				"status": doctorStatus(report.FTS.OK),
				"detail": doctorFTSDetail(report.FTS),
			},
		},
		doctorRow("journal_mode", report.JournalMode),
		doctorRow("transcript_paths", report.TranscriptPaths),
		doctorRow("deal_stages", report.DealStages),
		doctorRow("interaction_links", report.InteractionLinks),
		doctorRow("user_version", report.UserVersion),
	}
}

func doctorRow(name string, check model.DoctorCheck) Row {
	return Row{Cells: map[string]string{
		"check":  name,
		"status": doctorStatus(check.OK),
		"detail": check.Detail,
	}}
}

func doctorStatus(ok bool) string {
	if ok {
		return "ok"
	}

	return "fail"
}

func doctorFTSDetail(check model.DoctorFTSCheck) string {
	details := make([]string, 0, len(check.Tables))
	for _, table := range check.Tables {
		detail := fmt.Sprintf(
			"%s content=%d index=%d",
			table.Table,
			table.ContentRows,
			table.IndexRows,
		)
		if !table.OK {
			detail += " (" + table.Detail + ")"
		}
		details = append(details, detail)
	}

	return strings.Join(details, "; ")
}
