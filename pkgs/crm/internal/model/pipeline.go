package model

import "fmt"

// Pipeline is the complete persisted pipeline record plus its derived ref
// and ordered live stages. Stages is always a non-nil slice in JSON.
type Pipeline struct {
	Ref        string  `json:"ref"`
	ID         int64   `json:"id"`
	Name       string  `json:"name"`
	NameNorm   string  `json:"name_norm"`
	Position   int     `json:"position"`
	Stages     []Stage `json:"stages"`
	CreatedAt  string  `json:"created_at"`
	UpdatedAt  string  `json:"updated_at"`
	ArchivedAt *string `json:"archived_at"`
}

// Reference returns the pasteable prefixed ref for the pipeline.
func (pipeline Pipeline) Reference() string {
	if pipeline.Ref != "" {
		return pipeline.Ref
	}

	return fmt.Sprintf("p%d", pipeline.ID)
}
