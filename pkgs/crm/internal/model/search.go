package model

// FindTypes is the accepted set for crm find --type.
var FindTypes = []string{"org", "contact", "interaction", "deal"}

// ValidFindType reports whether entityType names one searchable entity.
func ValidFindType(entityType string) bool {
	for _, candidate := range FindTypes {
		if entityType == candidate {
			return true
		}
	}

	return false
}

// FindFilters controls the entity subset and global result cap for find.
// An empty Type searches every entity. A zero Limit selects the default cap.
type FindFilters struct {
	Type  string
	Limit int
}

// FindResult is the uniform cross-entity search projection.
type FindResult struct {
	Type   string  `json:"type"`
	Ref    string  `json:"ref"`
	Name   string  `json:"name"`
	Detail string  `json:"detail"`
	Rank   float64 `json:"rank"`
}
