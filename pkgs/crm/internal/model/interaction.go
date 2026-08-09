package model

import "fmt"

// InteractionKinds is the single source of truth for accepted interaction
// kinds. CLI validation, error text, flag help, and completion all consume
// this slice; a repository test keeps it aligned with the schema CHECK.
var InteractionKinds = []string{"call", "meeting", "email", "message", "note"}

// ValidInteractionKind reports whether kind is accepted by the shared enum.
func ValidInteractionKind(kind string) bool {
	for _, candidate := range InteractionKinds {
		if kind == candidate {
			return true
		}
	}

	return false
}

// Interaction is the complete persisted interaction record plus its derived
// ref and contact junction projection. ContactIDs is always non-nil so empty
// participant sets encode as [] rather than null.
type Interaction struct {
	Ref            string  `json:"ref"`
	ID             int64   `json:"id"`
	Kind           string  `json:"kind"`
	OccurredOn     string  `json:"occurred_on"`
	Summary        string  `json:"summary"`
	Body           *string `json:"body"`
	TranscriptPath *string `json:"transcript_path"`
	OrgID          *int64  `json:"org_id"`
	DealID         *int64  `json:"deal_id"`
	ContactIDs     []int64 `json:"contact_ids"`
	CreatedAt      string  `json:"created_at"`
	UpdatedAt      string  `json:"updated_at"`
	ArchivedAt     *string `json:"archived_at"`
}

// Reference returns the pasteable prefixed ref for the interaction.
func (interaction Interaction) Reference() string {
	if interaction.Ref != "" {
		return interaction.Ref
	}

	return fmt.Sprintf("i%d", interaction.ID)
}

// CreateInteractionInput contains already-resolved links and validated file
// content for one atomic interaction write.
type CreateInteractionInput struct {
	Kind           string
	OccurredOn     string
	Summary        string
	Body           *string
	TranscriptPath *string
	OrgID          *int64
	DealID         *int64
	ContactIDs     []int64
}

// UpdateInteractionInput is a true PATCH. Nullable scalar and FK fields use
// double pointers so nil means absent and pointer-to-nil means clear.
type UpdateInteractionInput struct {
	Kind             *string
	OccurredOn       *string
	Summary          *string
	Body             **string
	TranscriptPath   **string
	OrgID            **int64
	DealID           **int64
	AddContactIDs    []int64
	RemoveContactIDs []int64
}

// InteractionFilters controls deterministic interaction listings.
type InteractionFilters struct {
	ContactID *int64
	OrgID     *int64
	DealID    *int64
	Kind      *string
	All       bool
	Limit     int
}
