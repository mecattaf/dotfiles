package model

import "fmt"

// Contact is the complete persisted contact record plus its derived ref and
// assembled links. Pointer fields encode SQL NULL explicitly in JSON.
type Contact struct {
	Ref               string        `json:"ref"`
	ID                int64         `json:"id"`
	Name              string        `json:"name"`
	NameNorm          string        `json:"name_norm"`
	OrgID             *int64        `json:"org_id"`
	JobTitle          *string       `json:"job_title"`
	Email             *string       `json:"email"`
	Phone             *string       `json:"phone"`
	LinkedIn          *string       `json:"linkedin"`
	Location          *string       `json:"location"`
	Context           *string       `json:"context"`
	RelationshipHint  *string       `json:"relationship_hint"`
	ProvenanceSources *string       `json:"provenance_sources"`
	ProvenanceDetails *string       `json:"provenance_details"`
	CreatedAt         string        `json:"created_at"`
	UpdatedAt         string        `json:"updated_at"`
	ArchivedAt        *string       `json:"archived_at"`
	Links             []ContextLink `json:"links"`
}

// Reference returns the pasteable prefixed ref for the contact.
func (contact Contact) Reference() string {
	if contact.Ref != "" {
		return contact.Ref
	}

	return fmt.Sprintf("c%d", contact.ID)
}

// CreateContactInput contains all fields accepted by crm contact add.
type CreateContactInput struct {
	Name              string
	OrgID             *int64
	JobTitle          string
	Email             string
	Phone             string
	LinkedIn          string
	Location          string
	Context           string
	RelationshipHint  string
	ProvenanceSources []string
	ProvenanceDetails []string
}

// UpdateContactInput is a true PATCH. Nil field pointers mean absent and
// pointers to empty strings clear nullable text fields. OrgID uses a double
// pointer so nil means absent, pointer-to-nil means clear, and pointer-to-id
// means set.
type UpdateContactInput struct {
	OrgID             **int64
	JobTitle          *string
	Email             *string
	Phone             *string
	LinkedIn          *string
	Location          *string
	Context           *string
	ContextAppend     *string
	RelationshipHint  *string
	ProvenanceSources []string
	ProvenanceDetails []string
}

// ContactFilters controls the bounded contact listing query.
type ContactFilters struct {
	OrgID *int64
	All   bool
	Limit int
}
