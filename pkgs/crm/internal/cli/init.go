package cli

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"time"

	"github.com/mecattaf/crm/internal/db"
	crmformat "github.com/mecattaf/crm/internal/format"
	"github.com/spf13/cobra"
)

const orientationREADME = `# CRM data

This directory contains the private data managed by the crm CLI.

## Authority

- crm.db is authoritative. Never hand-edit it; use crm commands.
- Transcripts are evidence of record. Keep them under transcripts/YYYY/;
  summaries and dossiers do not replace the source files.

## References

Commands accept a prefixed ref (c12, o4, i9, d3, p2, s7), a bare
numeric id, or a matching name, email, or LinkedIn handle where applicable.
If a reference is ambiguous, choose one of the candidate refs printed by the
CLI; never guess.

Run crm doctor to audit the database and crm doctor --rebuild-fts to repair
search indexes. Do not repair crm.db with a SQLite editor.
`

func newInitCmd(options *rootOptions) *cobra.Command {
	return &cobra.Command{
		Use:   "init",
		Short: "Initialize the CRM database and data directories",
		Args:  cobra.NoArgs,
		Example: `  crm init
  crm --db /path/to/crm.db init`,
		Annotations: map[string]string{
			allowMissingDatabase:      "true",
			postWriteEntityAnnotation: "database",
		},
		RunE: func(cmd *cobra.Command, _ []string) error {
			paths, err := options.resolvePaths()
			if err != nil {
				return err
			}

			transcriptYear := filepath.Join(
				paths.base,
				"transcripts",
				strconv.Itoa(time.Now().Year()),
			)
			if err := os.MkdirAll(transcriptYear, 0o700); err != nil {
				return fmt.Errorf("create transcript directory %s: %w", transcriptYear, err)
			}

			database, err := db.Open(paths.database)
			if err != nil {
				return err
			}
			if err := database.Close(); err != nil {
				return fmt.Errorf("close database: %w", err)
			}

			if err := ensureOrientationREADME(filepath.Join(paths.base, "README.md")); err != nil {
				return err
			}

			if err := crmformat.WritePath(cmd.OutOrStdout(), paths.database); err != nil {
				return err
			}
			recordPostWrite(
				cmd,
				"init",
				"database",
				nil,
				[]any{map[string]string{"path": paths.database}},
			)

			return nil
		},
	}
}

func ensureOrientationREADME(path string) error {
	file, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if errors.Is(err, os.ErrExist) {
		info, statErr := os.Stat(path)
		if statErr != nil {
			return fmt.Errorf("inspect orientation README %s: %w", path, statErr)
		}
		if !info.Mode().IsRegular() {
			return fmt.Errorf("orientation README path is not a file: %s", path)
		}

		return nil
	}
	if err != nil {
		return fmt.Errorf("create orientation README %s: %w", path, err)
	}

	if _, err := file.WriteString(orientationREADME); err != nil {
		_ = file.Close()
		return fmt.Errorf("write orientation README %s: %w", path, err)
	}
	if err := file.Close(); err != nil {
		return fmt.Errorf("close orientation README %s: %w", path, err)
	}

	return nil
}
