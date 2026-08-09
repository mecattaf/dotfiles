package model

// DoctorCheck is one independently reported integrity assertion.
type DoctorCheck struct {
	OK     bool   `json:"ok"`
	Detail string `json:"detail"`
}

// DoctorFTSTableCheck reports both the FTS5 integrity command and the
// external-content-to-index row-count comparison for one searchable table.
type DoctorFTSTableCheck struct {
	Table       string `json:"table"`
	OK          bool   `json:"ok"`
	ContentRows int64  `json:"content_rows"`
	IndexRows   int64  `json:"index_rows"`
	Detail      string `json:"detail"`
}

// DoctorFTSCheck is the aggregate FTS assertion with a stable per-table
// breakdown. Tables is always an array, including when no table can be read.
type DoctorFTSCheck struct {
	OK     bool                  `json:"ok"`
	Tables []DoctorFTSTableCheck `json:"tables"`
}

// DoctorReport is the stable JSON report shape for crm doctor. Its eight
// keys correspond one-for-one with the integrity checks in the public spec.
type DoctorReport struct {
	IntegrityCheck   DoctorCheck    `json:"integrity_check"`
	ForeignKeyCheck  DoctorCheck    `json:"foreign_key_check"`
	FTS              DoctorFTSCheck `json:"fts"`
	JournalMode      DoctorCheck    `json:"journal_mode"`
	TranscriptPaths  DoctorCheck    `json:"transcript_paths"`
	DealStages       DoctorCheck    `json:"deal_stages"`
	InteractionLinks DoctorCheck    `json:"interaction_links"`
	UserVersion      DoctorCheck    `json:"user_version"`
}

// Healthy reports whether every doctor assertion passed.
func (report DoctorReport) Healthy() bool {
	return report.IntegrityCheck.OK &&
		report.ForeignKeyCheck.OK &&
		report.FTS.OK &&
		report.JournalMode.OK &&
		report.TranscriptPaths.OK &&
		report.DealStages.OK &&
		report.InteractionLinks.OK &&
		report.UserVersion.OK
}

// DoctorTranscript identifies one stored transcript path for the filesystem
// portion of the doctor audit.
type DoctorTranscript struct {
	InteractionID int64
	Path          string
}
