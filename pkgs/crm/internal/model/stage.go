package model

import "fmt"

// Stage is the complete persisted pipeline-stage record plus its derived ref.
// RotDays is nil when the stage never rots.
type Stage struct {
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

// Reference returns the pasteable prefixed ref for the stage.
func (stage Stage) Reference() string {
	if stage.Ref != "" {
		return stage.Ref
	}

	return fmt.Sprintf("s%d", stage.ID)
}

// CreateStageInput describes one stage insertion and its placement.
type CreateStageInput struct {
	PipelineID   int64
	Name         string
	RotDays      *int
	First        bool
	AfterStageID *int64
}
