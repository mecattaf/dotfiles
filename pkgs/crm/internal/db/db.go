// Package db owns the only SQLite open funnel used by crm.
package db

import (
	"database/sql"
	"errors"
	"fmt"
	"net/url"
	"strings"

	_ "modernc.org/sqlite" // Register the pure-Go SQLite database/sql driver.
)

type pragma struct {
	name      string
	statement string
}

var connectionPragmas = []pragma{
	{name: "journal_mode", statement: "PRAGMA journal_mode = DELETE"},
	{name: "busy_timeout", statement: "PRAGMA busy_timeout = 5000"},
	{name: "foreign_keys", statement: "PRAGMA foreign_keys = ON"},
	{name: "synchronous", statement: "PRAGMA synchronous = FULL"},
	{name: "temp_store", statement: "PRAGMA temp_store = MEMORY"},
	{name: "cache_size", statement: "PRAGMA cache_size = -64000"},
}

// JournalModeError reports a persistent journal mode that the open funnel
// refuses to normalize silently.
type JournalModeError struct {
	Actual   string
	Expected string
}

// Error describes the observed and required journal modes.
func (e *JournalModeError) Error() string {
	return fmt.Sprintf("got %q, want %q", e.Actual, e.Expected)
}

// Open returns a fully configured, migrated SQLite handle or no handle at all.
func Open(databasePath string) (*sql.DB, error) {
	database, err := sql.Open("sqlite", driverDataSourceName(databasePath))
	if err != nil {
		return nil, fmt.Errorf("open database: %w", err)
	}

	database.SetMaxOpenConns(1)

	if err := setPragmas(database, databasePath); err != nil {
		return closeAfterFailure(database, err)
	}
	if err := runMigrations(database, databasePath, embeddedMigrations); err != nil {
		return closeAfterFailure(database, fmt.Errorf("run migrations: %w", err))
	}

	return database, nil
}

func driverDataSourceName(databasePath string) string {
	separator := "?"
	if strings.Contains(databasePath, "?") {
		separator = "&"
	}

	// modernc applies _pragma options whenever database/sql creates a physical
	// connection. The explicit pragma loop below remains the fail-loud funnel;
	// this connection option ensures a replacement connection cannot silently
	// lose the busy handler between Open and a contended write. Immediate write
	// transactions acquire write intent at Begin, where that busy handler can
	// wait; a deferred transaction's later lock upgrade may return SQLITE_BUSY
	// immediately to avoid a lock-upgrade deadlock.
	return databasePath + separator +
		"_pragma=busy_timeout%3d5000&_txlock=immediate"
}

func setPragmas(database *sql.DB, databasePath string) error {
	// Check before applying journal_mode=DELETE so a database left in WAL (or
	// any other mode) fails loudly instead of being silently repaired merely by
	// opening it. Doctor relies on this preflight to distinguish journal drift.
	if err := assertJournalMode(database, databasePath); err != nil {
		return err
	}

	for _, setting := range connectionPragmas {
		if _, err := database.Exec(setting.statement); err != nil {
			return fmt.Errorf("pragma %s: %w", setting.name, err)
		}
	}

	return assertJournalMode(database, databasePath)
}

func assertJournalMode(database *sql.DB, databasePath string) error {
	var actualJournalMode string
	if err := database.QueryRow("PRAGMA journal_mode").Scan(&actualJournalMode); err != nil {
		return fmt.Errorf("pragma journal_mode read-back: %w", err)
	}

	expectedJournalMode := "delete"
	if isMemoryDatabase(databasePath) {
		expectedJournalMode = "memory"
	}
	if !strings.EqualFold(actualJournalMode, expectedJournalMode) {
		return fmt.Errorf(
			"pragma journal_mode read-back: %w",
			&JournalModeError{Actual: actualJournalMode, Expected: expectedJournalMode},
		)
	}

	return nil
}

func closeAfterFailure(database *sql.DB, failure error) (*sql.DB, error) {
	if err := database.Close(); err != nil {
		return nil, errors.Join(failure, fmt.Errorf("close database: %w", err))
	}

	return nil, failure
}

func isMemoryDatabase(databasePath string) bool {
	if databasePath == ":memory:" {
		return true
	}
	if !strings.HasPrefix(databasePath, "file:") {
		return false
	}

	parsed, err := url.Parse(databasePath)
	if err != nil {
		return false
	}

	return strings.EqualFold(parsed.Query().Get("mode"), "memory") ||
		parsed.Opaque == ":memory:" || parsed.Path == ":memory:"
}
