package model

const (
	// StaleTypeContact selects contact last-touch rows.
	StaleTypeContact = "contact"
	// StaleTypeOrg selects organization last-touch rows.
	StaleTypeOrg = "org"
)

// StaleTypes is the single accepted set for crm stale --type.
var StaleTypes = []string{StaleTypeContact, StaleTypeOrg}

// ValidStaleType reports whether entityType names a supported stale report.
func ValidStaleType(entityType string) bool {
	for _, candidate := range StaleTypes {
		if entityType == candidate {
			return true
		}
	}

	return false
}

// StatusReport is the stable one-row dashboard projection. LastLogged is nil
// when the live interaction log is empty; its derived age remains zero.
type StatusReport struct {
	Orgs              int     `json:"orgs"`
	Contacts          int     `json:"contacts"`
	Interactions      int     `json:"interactions"`
	OpenDeals         int     `json:"open_deals"`
	LastLogged        *string `json:"last_logged"`
	LastLoggedDaysAgo int     `json:"last_logged_days_ago"`
	NeverContacted    int     `json:"never_contacted"`
	Stale90Days       int     `json:"stale_90d"`
	RottingDeals      int     `json:"rotting_deals"`
	DBPath            string  `json:"db_path"`
}

// StaleFilters controls one contact or organization outreach worklist.
type StaleFilters struct {
	Days        int
	Type        string
	RecentFirst bool
}

// StaleResult is the stable last-touch projection shared by contacts and
// organizations. Last is nil for an entity with no live interaction.
type StaleResult struct {
	Type string  `json:"type"`
	Ref  string  `json:"ref"`
	ID   int64   `json:"id"`
	Name string  `json:"name"`
	Last *string `json:"last"`
}
