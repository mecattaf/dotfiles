package model

// ImportAction describes one row-level decision in a dry-run plan.
type ImportAction struct {
	Operation string
	Entity    string
	Ref       string
	Name      string
}
