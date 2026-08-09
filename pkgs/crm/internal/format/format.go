// Package format owns all writes of command data to stdout.
package format

import (
	"encoding/csv"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"strings"
	"unicode/utf8"

	"github.com/mattn/go-isatty"
	"github.com/mecattaf/crm/internal/model"
)

// Format names one supported command-data serialization.
type Format string

const (
	// FormatTable selects the human-oriented column renderer.
	FormatTable Format = "table"
	// FormatJSON selects stable JSON records.
	FormatJSON Format = "json"
	// FormatCSV selects a flat comma-separated projection.
	FormatCSV Format = "csv"
	// FormatIDs selects one pasteable prefixed ref per line.
	FormatIDs Format = "ids"
)

// ColumnDef declares one projected table or CSV column.
type ColumnDef struct {
	Header string
	Field  string
}

// Row adapts one typed JSON value to the shared table, CSV, and ids
// renderers. JSON must contain the complete stable record; Cells is the
// deliberately curated human projection.
type Row struct {
	JSON  any
	Ref   string
	Cells map[string]string
}

// Options controls one formatter invocation.
type Options struct {
	Format   Format
	Terminal bool
	Columns  []ColumnDef
}

// EntityFormats returns the accepted output set for rows carrying refs.
func EntityFormats() []Format {
	return []Format{FormatTable, FormatJSON, FormatIDs}
}

// ExportFormats returns the two serializations supported by flat entity
// exports. Export deliberately has no table or ids projection: its output is
// intended for lossless inspection and later import.
func ExportFormats() []Format {
	return []Format{FormatJSON, FormatCSV}
}

// ExportAllFormats returns the sole serialization supported by export all.
// CSV cannot represent the four keyed entity collections in one flat stream.
func ExportAllFormats() []Format {
	return []Format{FormatJSON}
}

// AcceptedList returns the display form of a verb's accepted format set.
func AcceptedList(accepted []Format) string {
	values := make([]string, len(accepted))
	for index, candidate := range accepted {
		values[index] = string(candidate)
	}

	return strings.Join(values, "|")
}

// Resolve validates an explicit format or selects table for a terminal and
// JSON for a pipe. Unsupported values are hard validation errors.
func Resolve(requested string, terminal bool, accepted []Format) (Format, error) {
	selected := Format(requested)
	if requested == "" {
		selected = FormatJSON
		if terminal {
			selected = FormatTable
		}
	}

	for _, candidate := range accepted {
		if selected == candidate {
			return selected, nil
		}
	}

	return "", model.NewExitError(
		model.ErrValidation,
		"unsupported format %q (accepted: %s)",
		selected,
		AcceptedList(accepted),
	)
}

// IsTerminal reports whether output is an interactive terminal. Non-file
// writers are pipes for deterministic tests and embedding.
func IsTerminal(output io.Writer) bool {
	file, ok := output.(*os.File)
	if !ok {
		return false
	}

	descriptor := file.Fd()
	return isatty.IsTerminal(descriptor) || isatty.IsCygwinTerminal(descriptor)
}

// WriteRecords is the sole record-output switch used by commands.
func WriteRecords(output io.Writer, rows []Row, options Options) error {
	switch options.Format {
	case FormatTable:
		return writeTable(output, rows, options.Columns, options.Terminal)
	case FormatJSON:
		return writeJSON(output, rows, options.Terminal)
	case FormatCSV:
		return writeCSV(output, rows, options.Columns)
	case FormatIDs:
		return writeIDs(output, rows)
	default:
		return fmt.Errorf("write output: unsupported resolved format %q", options.Format)
	}
}

func writeJSON(output io.Writer, rows []Row, pretty bool) error {
	values := make([]any, 0, len(rows))
	for _, row := range rows {
		values = append(values, row.JSON)
	}

	encoder := json.NewEncoder(output)
	if pretty {
		encoder.SetIndent("", "  ")
	}
	if err := encoder.Encode(values); err != nil {
		return fmt.Errorf("write JSON output: %w", err)
	}

	return nil
}

// WriteJSONValue writes a non-row JSON document while preserving the shared
// compact-through-a-pipe and pretty-on-a-terminal behavior. Commands use this
// for shaped reports such as export all so the formatter remains the only
// package that writes command data to stdout.
func WriteJSONValue(output io.Writer, value any, pretty bool) error {
	encoder := json.NewEncoder(output)
	if pretty {
		encoder.SetIndent("", "  ")
	}
	if err := encoder.Encode(value); err != nil {
		return fmt.Errorf("write JSON output: %w", err)
	}

	return nil
}

func writeIDs(output io.Writer, rows []Row) error {
	for _, row := range rows {
		if row.Ref == "" {
			return fmt.Errorf("write ids output: row has no ref")
		}
		if _, err := fmt.Fprintln(output, row.Ref); err != nil {
			return fmt.Errorf("write ids output: %w", err)
		}
	}

	return nil
}

func writeCSV(output io.Writer, rows []Row, columns []ColumnDef) error {
	writer := csv.NewWriter(output)
	header := make([]string, len(columns))
	for index, column := range columns {
		header[index] = column.Field
	}
	if err := writer.Write(header); err != nil {
		return fmt.Errorf("write CSV header: %w", err)
	}

	for _, row := range rows {
		record := make([]string, len(columns))
		for index, column := range columns {
			record[index] = row.Cells[column.Field]
		}
		if err := writer.Write(record); err != nil {
			return fmt.Errorf("write CSV row: %w", err)
		}
	}

	writer.Flush()
	if err := writer.Error(); err != nil {
		return fmt.Errorf("write CSV output: %w", err)
	}

	return nil
}

func writeTable(output io.Writer, rows []Row, columns []ColumnDef, rule bool) error {
	if len(rows) == 0 {
		return nil
	}

	visible := make([]ColumnDef, 0, len(columns))
	for _, column := range columns {
		for _, row := range rows {
			if row.Cells[column.Field] != "" {
				visible = append(visible, column)
				break
			}
		}
	}
	if len(visible) == 0 {
		return nil
	}

	widths := make([]int, len(visible))
	for index, column := range visible {
		widths[index] = utf8.RuneCountInString(column.Header)
		for _, row := range rows {
			widths[index] = max(widths[index], utf8.RuneCountInString(row.Cells[column.Field]))
		}
	}

	header := make([]string, len(visible))
	for index, column := range visible {
		header[index] = column.Header
	}
	if err := writeTableLine(output, header, widths); err != nil {
		return err
	}
	if rule {
		separators := make([]string, len(widths))
		for index, width := range widths {
			separators[index] = strings.Repeat("─", width)
		}
		if err := writeTableLine(output, separators, widths); err != nil {
			return err
		}
	}

	for _, row := range rows {
		values := make([]string, len(visible))
		for index, column := range visible {
			values[index] = row.Cells[column.Field]
		}
		if err := writeTableLine(output, values, widths); err != nil {
			return err
		}
	}

	return nil
}

func writeTableLine(output io.Writer, values []string, widths []int) error {
	for index, value := range values {
		if index > 0 {
			if _, err := io.WriteString(output, "  "); err != nil {
				return fmt.Errorf("write table output: %w", err)
			}
		}
		if _, err := io.WriteString(output, value); err != nil {
			return fmt.Errorf("write table output: %w", err)
		}
		if index < len(values)-1 {
			padding := widths[index] - utf8.RuneCountInString(value)
			if _, err := io.WriteString(output, strings.Repeat(" ", padding)); err != nil {
				return fmt.Errorf("write table output: %w", err)
			}
		}
	}
	if _, err := io.WriteString(output, "\n"); err != nil {
		return fmt.Errorf("write table output: %w", err)
	}

	return nil
}

// WritePath writes one resolved filesystem path as command data.
func WritePath(output io.Writer, path string) error {
	if _, err := fmt.Fprintln(output, path); err != nil {
		return fmt.Errorf("write output: %w", err)
	}

	return nil
}
