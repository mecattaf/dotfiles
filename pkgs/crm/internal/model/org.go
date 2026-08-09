package model

import "fmt"

// Org is the complete persisted organization record plus its derived ref.
// Pointer fields encode SQL NULL explicitly in JSON.
type Org struct {
	Ref               string  `json:"ref"`
	ID                int64   `json:"id"`
	Name              string  `json:"name"`
	NameNorm          string  `json:"name_norm"`
	Category          *string `json:"category"`
	Website           *string `json:"website"`
	LinkedIn          *string `json:"linkedin"`
	Location          *string `json:"location"`
	Focus             *string `json:"focus"`
	Context           *string `json:"context"`
	RelationshipHint  *string `json:"relationship_hint"`
	ProvenanceSources *string `json:"provenance_sources"`
	ProvenanceDetails *string `json:"provenance_details"`
	CreatedAt         string  `json:"created_at"`
	UpdatedAt         string  `json:"updated_at"`
	ArchivedAt        *string `json:"archived_at"`
}

// Reference returns the pasteable prefixed ref for the organization.
func (organization Org) Reference() string {
	if organization.Ref != "" {
		return organization.Ref
	}

	return fmt.Sprintf("o%d", organization.ID)
}

// CreateOrgInput contains all fields accepted by crm org add.
type CreateOrgInput struct {
	Name              string
	Category          string
	Website           string
	LinkedIn          string
	Location          string
	Focus             string
	Context           string
	RelationshipHint  string
	ProvenanceSources []string
	ProvenanceDetails []string
}

// UpdateOrgInput is a true PATCH. A nil pointer means absent, a pointer to
// the empty string means clear to SQL NULL, and a non-empty value means set.
// Provenance slices and ContextAppend are append-only.
type UpdateOrgInput struct {
	Category          *string
	Website           *string
	LinkedIn          *string
	Location          *string
	Focus             *string
	Context           *string
	ContextAppend     *string
	RelationshipHint  *string
	ProvenanceSources []string
	ProvenanceDetails []string
}

// OrgFilters controls the bounded organization listing query.
type OrgFilters struct {
	Category *string
	All      bool
	Limit    int
}
