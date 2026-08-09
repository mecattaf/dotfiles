package format

import (
	"bytes"
	"errors"
	"testing"

	"github.com/mecattaf/crm/internal/model"
)

type testRecord struct {
	Ref      string  `json:"ref"`
	Name     string  `json:"name"`
	Category *string `json:"category"`
}

func TestResolve(t *testing.T) {
	t.Parallel()

	accepted := EntityFormats()
	tests := []struct {
		name      string
		requested string
		terminal  bool
		want      Format
	}{
		{name: "pipe default", want: FormatJSON},
		{name: "terminal default", terminal: true, want: FormatTable},
		{name: "explicit table in pipe", requested: "table", want: FormatTable},
		{name: "explicit ids", requested: "ids", want: FormatIDs},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()

			got, err := Resolve(test.requested, test.terminal, accepted)
			if err != nil || got != test.want {
				t.Fatalf("Resolve() = %q, %v, want %q", got, err, test.want)
			}
		})
	}

	_, err := Resolve("csv", false, accepted)
	if !errors.Is(err, model.ErrValidation) {
		t.Fatalf("Resolve(csv) error = %v, want validation", err)
	}
	if got, want := err.Error(), `unsupported format "csv" (accepted: table|json|ids)`; got != want {
		t.Fatalf("Resolve(csv) error = %q, want %q", got, want)
	}
}

func TestWriteJSON(t *testing.T) {
	t.Parallel()

	var output bytes.Buffer
	if err := WriteRecords(&output, nil, Options{Format: FormatJSON}); err != nil {
		t.Fatalf("write empty JSON: %v", err)
	}
	if got, want := output.String(), "[]\n"; got != want {
		t.Fatalf("empty JSON = %q, want %q", got, want)
	}

	rows := []Row{{
		JSON: testRecord{Ref: "o1", Name: "Léger", Category: nil},
		Ref:  "o1",
	}}
	output.Reset()
	if err := WriteRecords(&output, rows, Options{Format: FormatJSON}); err != nil {
		t.Fatalf("write compact JSON: %v", err)
	}
	compact := "[{\"ref\":\"o1\",\"name\":\"Léger\",\"category\":null}]\n"
	if got := output.String(); got != compact {
		t.Fatalf("compact JSON = %q, want %q", got, compact)
	}

	output.Reset()
	if err := WriteRecords(
		&output,
		rows,
		Options{Format: FormatJSON, Terminal: true},
	); err != nil {
		t.Fatalf("write pretty JSON: %v", err)
	}
	pretty := "[\n  {\n    \"ref\": \"o1\",\n    \"name\": \"Léger\",\n    \"category\": null\n  }\n]\n"
	if got := output.String(); got != pretty {
		t.Fatalf("pretty JSON = %q, want %q", got, pretty)
	}
}

func TestWriteIDs(t *testing.T) {
	t.Parallel()

	rows := []Row{{Ref: "o1"}, {Ref: "o7"}}
	var output bytes.Buffer
	if err := WriteRecords(&output, rows, Options{Format: FormatIDs}); err != nil {
		t.Fatalf("write ids: %v", err)
	}
	if got, want := output.String(), "o1\no7\n"; got != want {
		t.Fatalf("ids output = %q, want %q", got, want)
	}
}

func TestWriteTableElidesEmptyColumnsAndCountsRunes(t *testing.T) {
	t.Parallel()

	columns := []ColumnDef{
		{Header: "REF", Field: "ref"},
		{Header: "NAME", Field: "name"},
		{Header: "CATEGORY", Field: "category"},
	}
	rows := []Row{{
		Cells: map[string]string{"ref": "o1", "name": "Léger"},
	}}

	var output bytes.Buffer
	if err := WriteRecords(
		&output,
		rows,
		Options{Format: FormatTable, Columns: columns},
	); err != nil {
		t.Fatalf("write piped table: %v", err)
	}
	if got, want := output.String(), "REF  NAME\no1   Léger\n"; got != want {
		t.Fatalf("piped table = %q, want %q", got, want)
	}

	output.Reset()
	if err := WriteRecords(
		&output,
		rows,
		Options{Format: FormatTable, Terminal: true, Columns: columns},
	); err != nil {
		t.Fatalf("write terminal table: %v", err)
	}
	want := "REF  NAME\n───  ─────\no1   Léger\n"
	if got := output.String(); got != want {
		t.Fatalf("terminal table = %q, want %q", got, want)
	}
}

func TestWriteCSVUsesDeclaredProjection(t *testing.T) {
	t.Parallel()

	rows := []Row{{
		Cells: map[string]string{"ref": "o1", "name": "A, Inc."},
	}}
	columns := []ColumnDef{{Header: "REF", Field: "ref"}, {Header: "NAME", Field: "name"}}
	var output bytes.Buffer
	if err := WriteRecords(
		&output,
		rows,
		Options{Format: FormatCSV, Columns: columns},
	); err != nil {
		t.Fatalf("write CSV: %v", err)
	}
	if got, want := output.String(), "ref,name\no1,\"A, Inc.\"\n"; got != want {
		t.Fatalf("CSV output = %q, want %q", got, want)
	}
}
