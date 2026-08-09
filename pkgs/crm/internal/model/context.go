package model

// ContextEntity identifies the two entity families accepted by crm context.
type ContextEntity string

const (
	// ContextContact selects a contact briefing.
	ContextContact ContextEntity = "contact"
	// ContextOrg selects an organization briefing.
	ContextOrg ContextEntity = "org"
)

// ContextTarget is the already-resolved subject passed to the briefing
// assembler.
type ContextTarget struct {
	Entity ContextEntity
	ID     int64
}

// ContextLink is the stable context projection for one directed contact
// link. T08 owns populating this section; t05b establishes its shape and
// renderer so the assembler remains the single source for both outputs.
type ContextLink struct {
	Direction string  `json:"direction"`
	Type      string  `json:"type"`
	Note      *string `json:"note"`
	Contact   Contact `json:"contact"`
}

// ContextDeal is the stable context projection for one open deal. T07 owns
// populating this section; t05b establishes its shape and renderer.
type ContextDeal struct {
	Ref         string `json:"ref"`
	ID          int64  `json:"id"`
	Title       string `json:"title"`
	Stage       string `json:"stage"`
	DaysInStage int    `json:"days_in_stage"`
}

// Briefing is the sole assembled context document. Contact is present for a
// contact target. Org is either that contact's organization or the primary
// organization target. Collection fields are always non-nil so JSON renders
// [] rather than null. TimelineTotal records the uncapped count for the
// document heading without widening the specified JSON shape.
type Briefing struct {
	Contact       *Contact      `json:"contact,omitempty"`
	Org           *Org          `json:"org,omitempty"`
	Links         []ContextLink `json:"links"`
	Deals         []ContextDeal `json:"deals"`
	Timeline      []Interaction `json:"timeline"`
	TimelineTotal int           `json:"-"`
}
