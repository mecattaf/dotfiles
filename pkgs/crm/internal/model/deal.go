package model

import "fmt"

// DealStatuses is the single source of truth for accepted deal states. CLI
// validation, error text, completion, and a CHECK-drift test all consume it.
var DealStatuses = []string{"open", "won", "lost"}

// ValidDealStatus reports whether status is accepted by the shared enum.
func ValidDealStatus(status string) bool {
	for _, candidate := range DealStatuses {
		if status == candidate {
			return true
		}
	}

	return false
}

// Deal is the complete persisted opportunity plus derived pipeline, stage,
// and rot fields used by every list and mutation renderer.
type Deal struct {
	Ref            string  `json:"ref"`
	ID             int64   `json:"id"`
	Title          string  `json:"title"`
	TitleNorm      string  `json:"title_norm"`
	OrgID          *int64  `json:"org_id"`
	ContactID      *int64  `json:"contact_id"`
	PipelineID     int64   `json:"pipeline_id"`
	Pipeline       string  `json:"pipeline"`
	StageID        int64   `json:"stage_id"`
	Stage          string  `json:"stage"`
	Status         string  `json:"status"`
	OutcomeReason  *string `json:"outcome_reason"`
	ClosedAt       *string `json:"closed_at"`
	StageChangedAt string  `json:"stage_changed_at"`
	DaysInStage    int     `json:"days_in_stage"`
	RotDays        *int    `json:"rot_days"`
	CreatedAt      string  `json:"created_at"`
	UpdatedAt      string  `json:"updated_at"`
	ArchivedAt     *string `json:"archived_at"`
}

// Reference returns the pasteable prefixed ref for the deal.
func (deal Deal) Reference() string {
	if deal.Ref != "" {
		return deal.Ref
	}

	return fmt.Sprintf("d%d", deal.ID)
}

// StageMove is one real-columned transition in a deal's stage history. Stage
// names are derived at read time so history remains readable after renames.
type StageMove struct {
	ID            int64   `json:"id"`
	DealID        int64   `json:"deal_id"`
	FromStageID   *int64  `json:"from_stage_id"`
	FromStageName *string `json:"from_stage"`
	ToStageID     int64   `json:"to_stage_id"`
	ToStageName   string  `json:"to_stage"`
	MovedAt       string  `json:"moved_at"`
	Note          *string `json:"note"`
}

// DealTimelineEntry is one stage move or deal-linked interaction in the
// merged newest-first timeline. Exactly one payload is non-nil.
type DealTimelineEntry struct {
	Type        string       `json:"type"`
	OccurredAt  string       `json:"occurred_at"`
	StageMove   *StageMove   `json:"stage_move"`
	Interaction *Interaction `json:"interaction"`
}

// DealDetail is the show projection. Anonymous embedding keeps the base deal
// JSON flat while adding the two show-only collections.
type DealDetail struct {
	Deal
	StageMoves []StageMove         `json:"stage_moves"`
	Timeline   []DealTimelineEntry `json:"timeline"`
}

// CreateDealInput contains refs resolved before the opening transaction.
type CreateDealInput struct {
	Title      string
	OrgID      *int64
	ContactID  *int64
	PipelineID int64
	StageID    int64
}

// UpdateDealInput is a true PATCH. Nullable anchors use double pointers so a
// nil outer pointer means absent and a nil inner pointer means clear.
type UpdateDealInput struct {
	Title     *string
	OrgID     **int64
	ContactID **int64
}

// DealFilters controls deterministic deal listings. IDs are already resolved
// by the command before repository work begins.
type DealFilters struct {
	PipelineID *int64
	StageID    *int64
	Status     *string
	Rotting    bool
	All        bool
	Limit      int
}
