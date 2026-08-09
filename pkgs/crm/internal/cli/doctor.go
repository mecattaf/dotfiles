package cli

import (
	"errors"
	"fmt"
	"strings"

	"github.com/mecattaf/crm/internal/db"
	"github.com/mecattaf/crm/internal/db/repo"
	crmformat "github.com/mecattaf/crm/internal/format"
	"github.com/mecattaf/crm/internal/model"
	"github.com/spf13/cobra"
)

type doctorOptions struct {
	rebuildFTS bool
	format     string
}

func newDoctorCmd(root *rootOptions) *cobra.Command {
	options := &doctorOptions{}
	command := &cobra.Command{
		Use:   "doctor",
		Short: "Audit CRM database integrity",
		Long: `Audit CRM database integrity and report all eight checks independently.

JSON output is one object keyed by integrity_check, foreign_key_check, fts,
journal_mode, transcript_paths, deal_stages, interaction_links, and
user_version. --rebuild-fts repairs every FTS index atomically before the
report runs.`,
		Args: func(command *cobra.Command, arguments []string) error {
			if err := cobra.NoArgs(command, arguments); err != nil {
				return err
			}

			_, _, err := resolveDoctorFormat(command, options.format)
			return err
		},
		Example: `  crm doctor
  crm doctor --format json
  crm doctor --rebuild-fts`,
		RunE: func(command *cobra.Command, _ []string) error {
			selected, terminal, err := resolveDoctorFormat(command, options.format)
			if err != nil {
				return err
			}
			paths, err := root.resolvePaths()
			if err != nil {
				return err
			}
			database, err := db.Open(paths.database)
			if err != nil {
				var journalModeError *db.JournalModeError
				if errors.As(err, &journalModeError) {
					return writeDoctorResult(
						command,
						doctorJournalFailureReport(journalModeError),
						selected,
						terminal,
					)
				}
				return err
			}
			defer func() {
				_ = database.Close()
			}()

			doctor := repo.NewDoctorRepo(database)
			if options.rebuildFTS {
				if err := doctor.RebuildFTS(command.Context()); err != nil {
					return err
				}
			}
			latestMigration, err := db.LatestMigrationVersion()
			if err != nil {
				return fmt.Errorf("discover embedded migrations: %w", err)
			}

			report := model.DoctorReport{
				IntegrityCheck:   doctor.IntegrityCheck(command.Context()),
				ForeignKeyCheck:  doctor.ForeignKeyCheck(command.Context()),
				FTS:              doctor.FTSCheck(command.Context()),
				JournalMode:      doctor.JournalModeCheck(command.Context()),
				DealStages:       doctor.DealStagesCheck(command.Context()),
				InteractionLinks: doctor.InteractionLinksCheck(command.Context()),
				UserVersion:      doctor.UserVersionCheck(command.Context(), latestMigration),
			}
			transcripts, transcriptErr := doctor.TranscriptPaths(command.Context())
			report.TranscriptPaths = auditTranscriptPaths(paths.base, transcripts, transcriptErr)

			if err := writeDoctorResult(command, report, selected, terminal); err != nil {
				return err
			}
			if options.rebuildFTS {
				recordPostWrite(
					command,
					"doctor",
					"fts",
					nil,
					[]any{report},
				)
			}

			return nil
		},
	}
	command.Flags().BoolVar(
		&options.rebuildFTS,
		"rebuild-fts",
		false,
		"rebuild every FTS index in one transaction before auditing",
	)
	command.Flags().StringVar(
		&options.format,
		"format",
		"",
		"output format ("+crmformat.AcceptedList(crmformat.DoctorFormats())+")",
	)

	return command
}

func resolveDoctorFormat(
	command *cobra.Command,
	requested string,
) (crmformat.Format, bool, error) {
	terminal := crmformat.IsTerminal(command.OutOrStdout())
	selected, err := crmformat.Resolve(requested, terminal, crmformat.DoctorFormats())

	return selected, terminal, err
}

func writeDoctorResult(
	command *cobra.Command,
	report model.DoctorReport,
	selected crmformat.Format,
	terminal bool,
) error {
	if err := crmformat.WriteDoctorReport(
		command.OutOrStdout(),
		report,
		selected,
		terminal,
	); err != nil {
		return err
	}
	if !report.Healthy() {
		return model.NewExitError(model.ErrValidation, "doctor found integrity drift")
	}

	return nil
}

func doctorJournalFailureReport(journalModeError *db.JournalModeError) model.DoctorReport {
	notRun := model.DoctorCheck{
		OK:     false,
		Detail: "not run: unsafe journal mode prevented database open",
	}

	return model.DoctorReport{
		IntegrityCheck:  notRun,
		ForeignKeyCheck: notRun,
		FTS: model.DoctorFTSCheck{
			OK: false,
			Tables: []model.DoctorFTSTableCheck{
				{Table: "orgs", OK: false, Detail: notRun.Detail},
				{Table: "contacts", OK: false, Detail: notRun.Detail},
				{Table: "interactions", OK: false, Detail: notRun.Detail},
				{Table: "deals", OK: false, Detail: notRun.Detail},
			},
		},
		JournalMode:      model.DoctorCheck{OK: false, Detail: journalModeError.Error()},
		TranscriptPaths:  notRun,
		DealStages:       notRun,
		InteractionLinks: notRun,
		UserVersion:      notRun,
	}
}

func auditTranscriptPaths(
	base string,
	transcripts []model.DoctorTranscript,
	loadErr error,
) model.DoctorCheck {
	if loadErr != nil {
		return model.DoctorCheck{OK: false, Detail: fmt.Sprintf("query failed: %v", loadErr)}
	}

	issues := make([]string, 0)
	for _, transcript := range transcripts {
		if strings.TrimSpace(transcript.Path) == "" {
			issues = append(
				issues,
				fmt.Sprintf("i%d has an empty transcript path", transcript.InteractionID),
			)
			continue
		}
		if _, err := resolveTranscriptPath(base, transcript.Path); err != nil {
			issues = append(issues, fmt.Sprintf("i%d: %v", transcript.InteractionID, err))
		}
	}
	if len(issues) > 0 {
		return model.DoctorCheck{OK: false, Detail: strings.Join(issues, "; ")}
	}

	return model.DoctorCheck{
		OK:     true,
		Detail: fmt.Sprintf("%d checked", len(transcripts)),
	}
}
