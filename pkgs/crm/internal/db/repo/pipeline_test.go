package repo_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/mecattaf/crm/internal/db/dbtest"
	"github.com/mecattaf/crm/internal/db/repo"
	"github.com/mecattaf/crm/internal/model"
)

func TestPipelineRepoListBatchLoadsOrderedStagesAfterRowsClose(t *testing.T) {
	t.Parallel()

	database := dbtest.Open(t)
	pipelines := repo.NewPipelineRepo(database)
	seed, err := pipelines.Create(context.Background(), "Seed")
	if err != nil {
		t.Fatalf("create seed pipeline: %v", err)
	}
	if _, err := pipelines.Create(context.Background(), "Sales"); err != nil {
		t.Fatalf("create sales pipeline: %v", err)
	}

	stages := repo.NewStageRepo(database)
	sourced, err := stages.Create(
		context.Background(),
		model.CreateStageInput{PipelineID: seed.ID, Name: "sourced"},
	)
	if err != nil {
		t.Fatalf("create sourced stage: %v", err)
	}
	if _, err := stages.Create(
		context.Background(),
		model.CreateStageInput{PipelineID: seed.ID, Name: "pitched"},
	); err != nil {
		t.Fatalf("create pitched stage: %v", err)
	}
	rotDays := 14
	if _, err := stages.Create(
		context.Background(),
		model.CreateStageInput{
			PipelineID:   seed.ID,
			Name:         "contacted",
			RotDays:      &rotDays,
			AfterStageID: &sourced.ID,
		},
	); err != nil {
		t.Fatalf("create contacted stage: %v", err)
	}

	result := make(chan struct {
		rows []model.Pipeline
		err  error
	}, 1)
	go func() {
		rows, listErr := pipelines.List(context.Background(), false)
		result <- struct {
			rows []model.Pipeline
			err  error
		}{rows: rows, err: listErr}
	}()

	select {
	case got := <-result:
		if got.err != nil {
			t.Fatalf("list pipelines: %v", got.err)
		}
		if len(got.rows) != 2 {
			t.Fatalf("listed pipelines = %#v", got.rows)
		}
		if got.rows[0].Name != "Seed" || got.rows[1].Name != "Sales" {
			t.Fatalf("pipeline order = %#v", got.rows)
		}
		wantStages := []string{"sourced", "contacted", "pitched"}
		if len(got.rows[0].Stages) != len(wantStages) {
			t.Fatalf("seed stages = %#v", got.rows[0].Stages)
		}
		for index, want := range wantStages {
			if got.rows[0].Stages[index].Name != want ||
				got.rows[0].Stages[index].Position != index+1 {
				t.Fatalf("seed stage %d = %#v, want %q", index, got.rows[0].Stages[index], want)
			}
		}
		if got.rows[0].Stages[1].RotDays == nil || *got.rows[0].Stages[1].RotDays != 14 {
			t.Fatalf("contacted rot = %v, want 14", got.rows[0].Stages[1].RotDays)
		}
		if got.rows[1].Stages == nil || len(got.rows[1].Stages) != 0 {
			t.Fatalf("sales stages = %#v, want []", got.rows[1].Stages)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("pipeline listing hung while batch-loading stages")
	}
}

func TestStageCreateDuplicateRollsBackPositionShift(t *testing.T) {
	t.Parallel()

	database := dbtest.Open(t)
	pipeline, err := repo.NewPipelineRepo(database).Create(context.Background(), "Seed")
	if err != nil {
		t.Fatalf("create pipeline: %v", err)
	}
	stages := repo.NewStageRepo(database)
	for _, name := range []string{"sourced", "pitched"} {
		if _, err := stages.Create(
			context.Background(),
			model.CreateStageInput{PipelineID: pipeline.ID, Name: name},
		); err != nil {
			t.Fatalf("create stage %q: %v", name, err)
		}
	}

	_, err = stages.Create(
		context.Background(),
		model.CreateStageInput{PipelineID: pipeline.ID, Name: "SOURCED", First: true},
	)
	if !errors.Is(err, model.ErrConflict) {
		t.Fatalf("duplicate stage error = %v, want ErrConflict", err)
	}

	listed, err := stages.ListByPipeline(context.Background(), pipeline.ID, false)
	if err != nil {
		t.Fatalf("list stages after rejected duplicate: %v", err)
	}
	if len(listed) != 2 || listed[0].Name != "sourced" || listed[0].Position != 1 ||
		listed[1].Name != "pitched" || listed[1].Position != 2 {
		t.Fatalf("positions changed after rolled-back duplicate: %#v", listed)
	}
}
