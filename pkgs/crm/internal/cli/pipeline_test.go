package cli

import (
	"encoding/json"
	"fmt"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

type pipelineOutput struct {
	Ref        string        `json:"ref"`
	ID         int64         `json:"id"`
	Name       string        `json:"name"`
	NameNorm   string        `json:"name_norm"`
	Position   int           `json:"position"`
	Stages     []stageOutput `json:"stages"`
	CreatedAt  string        `json:"created_at"`
	UpdatedAt  string        `json:"updated_at"`
	ArchivedAt *string       `json:"archived_at"`
}

type stageOutput struct {
	Ref        string  `json:"ref"`
	ID         int64   `json:"id"`
	PipelineID int64   `json:"pipeline_id"`
	Name       string  `json:"name"`
	NameNorm   string  `json:"name_norm"`
	Position   int     `json:"position"`
	RotDays    *int    `json:"rot_days"`
	CreatedAt  string  `json:"created_at"`
	UpdatedAt  string  `json:"updated_at"`
	ArchivedAt *string `json:"archived_at"`
}

func TestPipelineAndStageAcceptance(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "crm.db")
	stdout, stderr, code := crm(t, databasePath, "init")
	assertCommandResult(t, stdout, stderr, code, databasePath+"\n", "", 0)
	stdout, stderr, code = crm(t, databasePath, "pipeline", "ls", "--format", "json")
	assertCommandResult(t, stdout, stderr, code, "[]\n", "", 0)

	stdout, stderr, code = crm(t, databasePath, "pipeline", "add", "Seed raise")
	if stderr != "" || code != 0 {
		t.Fatalf("pipeline add stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	created := assertCompactPipelineJSON(t, stdout, 1)[0]
	if created.Ref != "p1" || created.Name != "Seed raise" ||
		created.NameNorm != "seed raise" || created.Position != 1 {
		t.Fatalf("created pipeline = %#v", created)
	}
	if created.Stages == nil || len(created.Stages) != 0 {
		t.Fatalf("created pipeline stages = %#v, want []", created.Stages)
	}

	stdout, stderr, code = crm(t, databasePath, "pipeline", "add", "Seed raise")
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"",
		"crm: error: duplicate pipeline name \"Seed raise\" — already on pipeline p1 (Seed raise)\n",
		4,
	)

	stdout, stderr, code = crm(t, databasePath, "pipelines", "list")
	if stderr != "" || code != 0 {
		t.Fatalf("pipelines list stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	listed := assertCompactPipelineJSON(t, stdout, 1)
	if listed[0].Ref != "p1" {
		t.Fatalf("pipeline listing = %#v", listed)
	}

	for index, name := range []string{"sourced", "pitched"} {
		stdout, stderr, code = crm(t, databasePath, "stage", "add", "p1", name)
		if stderr != "" || code != 0 {
			t.Fatalf("stage add %q stdout=%q stderr=%q code=%d", name, stdout, stderr, code)
		}
		stage := assertCompactStageJSON(t, stdout, 1)[0]
		if stage.Ref != fmt.Sprintf("s%d", index+1) || stage.Name != name ||
			stage.PipelineID != 1 || stage.Position != index+1 || stage.RotDays != nil {
			t.Fatalf("added stage %q = %#v", name, stage)
		}
	}

	stdout, stderr, code = crm(
		t,
		databasePath,
		"stage", "add", "p1", "contacted", "--rot", "14", "--after", "sourced",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("placed stage add stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	contacted := assertCompactStageJSON(t, stdout, 1)[0]
	if contacted.Ref != "s3" || contacted.Position != 2 ||
		contacted.RotDays == nil || *contacted.RotDays != 14 {
		t.Fatalf("placed contacted stage = %#v", contacted)
	}

	stdout, stderr, code = crm(t, databasePath, "p", "show", "p1")
	if stderr != "" || code != 0 {
		t.Fatalf("pipeline alias show stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	shown := assertCompactPipelineJSON(t, stdout, 1)[0]
	assertStageOrder(t, shown.Stages, "sourced", "contacted", "pitched")
	if shown.Stages[1].RotDays == nil || *shown.Stages[1].RotDays != 14 {
		t.Fatalf("shown contacted rot = %v, want 14", shown.Stages[1].RotDays)
	}

	stdout, stderr, code = crm(
		t,
		databasePath,
		"stage", "reorder", "p1", "pitched", "sourced",
	)
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"",
		"crm: error: stage reorder for pipeline p1 must list every live stage exactly once — missing: contacted\n",
		1,
	)

	stdout, stderr, code = crm(
		t,
		databasePath,
		"stage", "reorder", "p1", "pitched", "contacted", "sourced",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("complete stage reorder stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	reordered := assertCompactStageJSON(t, stdout, 3)
	assertStageOrder(t, reordered, "pitched", "contacted", "sourced")

	stdout, stderr, code = crm(t, databasePath, "stage", "set-rot", "p1", "pitched", "7")
	if stderr != "" || code != 0 {
		t.Fatalf("stage set-rot stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	withRot := assertCompactStageJSON(t, stdout, 1)[0]
	if withRot.RotDays == nil || *withRot.RotDays != 7 {
		t.Fatalf("stage rot_days = %v, want 7", withRot.RotDays)
	}

	stdout, stderr, code = crm(t, databasePath, "stage", "set-rot", "p1", "pitched", "none")
	if stderr != "" || code != 0 {
		t.Fatalf("stage clear rot stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	clearedRot := assertCompactStageJSON(t, stdout, 1)[0]
	if clearedRot.RotDays != nil {
		t.Fatalf("cleared rot_days = %v, want JSON null", clearedRot.RotDays)
	}

	stdout, stderr, code = crm(
		t,
		databasePath,
		"stage", "rename", "p1", "contacted", "first contact",
	)
	if stderr != "" || code != 0 {
		t.Fatalf("stage rename stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	renamedStage := assertCompactStageJSON(t, stdout, 1)[0]
	if renamedStage.Ref != "s3" || renamedStage.Name != "first contact" ||
		renamedStage.NameNorm != "first contact" {
		t.Fatalf("renamed stage = %#v", renamedStage)
	}

	stdout, stderr, code = crm(t, databasePath, "pipeline", "rename", "p1", "Seed round")
	if stderr != "" || code != 0 {
		t.Fatalf("pipeline rename stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	renamedPipeline := assertCompactPipelineJSON(t, stdout, 1)[0]
	if renamedPipeline.Ref != "p1" || renamedPipeline.Name != "Seed round" ||
		renamedPipeline.NameNorm != "seed round" {
		t.Fatalf("renamed pipeline = %#v", renamedPipeline)
	}
	assertStageOrder(t, renamedPipeline.Stages, "pitched", "first contact", "sourced")

	stdout, stderr, code = crm(t, databasePath, "stage", "add", "p1", "SOURCED")
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"",
		"crm: error: duplicate stage name \"SOURCED\" — already on stage s1 (sourced) in pipeline p1\n",
		4,
	)

	assertNoSidecars(t, databasePath)
}

func TestStagePlacementAndPipelineScopedResolution(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "crm.db")
	stdout, stderr, code := crm(t, databasePath, "init")
	assertCommandResult(t, stdout, stderr, code, databasePath+"\n", "", 0)

	for _, pipeline := range []string{"Seed", "Sales"} {
		stdout, stderr, code = crm(t, databasePath, "pipeline", "add", pipeline)
		if stderr != "" || code != 0 {
			t.Fatalf("pipeline add %q stdout=%q stderr=%q code=%d", pipeline, stdout, stderr, code)
		}
		assertCompactPipelineJSON(t, stdout, 1)
	}
	stdout, stderr, code = crm(t, databasePath, "pipeline", "rename", "p2", "SÉED")
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"",
		"crm: error: duplicate pipeline name \"SÉED\" — already on pipeline p1 (Seed)\n",
		4,
	)

	stdout, stderr, code = crm(t, databasePath, "stage", "add", "p1", "later")
	if stderr != "" || code != 0 {
		t.Fatalf("append later stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	assertCompactStageJSON(t, stdout, 1)
	stdout, stderr, code = crm(t, databasePath, "stage", "add", "p1", "first", "--first")
	if stderr != "" || code != 0 {
		t.Fatalf("add first stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	assertCompactStageJSON(t, stdout, 1)
	stdout, stderr, code = crm(t, databasePath, "stage", "add", "p1", "middle", "--after", "first")
	if stderr != "" || code != 0 {
		t.Fatalf("add middle stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	assertCompactStageJSON(t, stdout, 1)

	stdout, stderr, code = crm(t, databasePath, "pipeline", "show", "Seed")
	if stderr != "" || code != 0 {
		t.Fatalf("show placements stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	assertStageOrder(t, assertCompactPipelineJSON(t, stdout, 1)[0].Stages, "first", "middle", "later")

	stdout, stderr, code = crm(t, databasePath, "stage", "add", "p2", "first")
	if stderr != "" || code != 0 {
		t.Fatalf("same stage name in another pipeline stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	otherStage := assertCompactStageJSON(t, stdout, 1)[0]
	if otherStage.Ref != "s4" || otherStage.PipelineID != 2 {
		t.Fatalf("other pipeline stage = %#v", otherStage)
	}
	stdout, stderr, code = crm(t, databasePath, "stage", "rename", "p1", "middle", "FIRST")
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"",
		"crm: error: duplicate stage name \"FIRST\" — already on stage s2 (first) in pipeline p1\n",
		4,
	)

	stdout, stderr, code = crm(t, databasePath, "stage", "rename", "p2", "s1", "wrong")
	if stdout != "" || code != 2 || !strings.Contains(stderr, "no stage \"s1\"") {
		t.Fatalf("cross-pipeline stage ref stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}

	stdout, stderr, code = crm(t, databasePath, "stage", "set-rot", "p1", "middle", "0")
	assertCommandResult(
		t,
		stdout,
		stderr,
		code,
		"",
		"crm: error: rot days must be a positive integer or none\n",
		1,
	)

	stdout, stderr, code = crm(
		t,
		databasePath,
		"stage", "add", "p1", "invalid", "--first", "--after", "middle",
	)
	if stdout != "" || code != 1 || !strings.Contains(stderr, "if any flags in the group") {
		t.Fatalf("mutually exclusive placement stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
}

func assertCompactPipelineJSON(t *testing.T, stdout string, wantLength int) []pipelineOutput {
	t.Helper()

	var records []pipelineOutput
	if err := json.Unmarshal([]byte(stdout), &records); err != nil {
		t.Fatalf("decode pipeline output %q: %v", stdout, err)
	}
	if len(records) != wantLength {
		t.Fatalf("pipeline output length = %d, want %d: %#v", len(records), wantLength, records)
	}
	assertCompactJSON(t, stdout, records)
	for _, record := range records {
		assertRFC3339(t, "pipeline.created_at", record.CreatedAt)
		assertRFC3339(t, "pipeline.updated_at", record.UpdatedAt)
		if record.Stages == nil {
			t.Fatalf("pipeline stages decoded as nil: %#v", record)
		}
		for _, stage := range record.Stages {
			assertStageTimestamps(t, stage)
		}
	}

	return records
}

func assertCompactStageJSON(t *testing.T, stdout string, wantLength int) []stageOutput {
	t.Helper()

	var records []stageOutput
	if err := json.Unmarshal([]byte(stdout), &records); err != nil {
		t.Fatalf("decode stage output %q: %v", stdout, err)
	}
	if len(records) != wantLength {
		t.Fatalf("stage output length = %d, want %d: %#v", len(records), wantLength, records)
	}
	assertCompactJSON(t, stdout, records)
	for _, record := range records {
		assertStageTimestamps(t, record)
	}

	return records
}

func assertCompactJSON[T any](t *testing.T, stdout string, records []T) {
	t.Helper()

	encoded, err := json.Marshal(records)
	if err != nil {
		t.Fatalf("re-encode output: %v", err)
	}
	if got, want := stdout, string(encoded)+"\n"; got != want {
		t.Fatalf("output is not compact stable JSON: got %q want %q", got, want)
	}
}

func assertStageTimestamps(t *testing.T, stage stageOutput) {
	t.Helper()

	assertRFC3339(t, "stage.created_at", stage.CreatedAt)
	assertRFC3339(t, "stage.updated_at", stage.UpdatedAt)
}

func assertRFC3339(t *testing.T, field, value string) {
	t.Helper()

	if _, err := time.Parse(time.RFC3339, value); err != nil {
		t.Fatalf("%s = %q, want RFC3339: %v", field, value, err)
	}
}

func assertStageOrder(t *testing.T, stages []stageOutput, wantNames ...string) {
	t.Helper()

	if len(stages) != len(wantNames) {
		t.Fatalf("stage count = %d, want %d: %#v", len(stages), len(wantNames), stages)
	}
	for index, wantName := range wantNames {
		if stages[index].Name != wantName || stages[index].Position != index+1 {
			t.Fatalf("stage %d = %#v, want name %q position %d", index, stages[index], wantName, index+1)
		}
	}
}
