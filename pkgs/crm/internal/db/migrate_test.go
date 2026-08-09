package db

import (
	"bytes"
	"database/sql"
	"os"
	"path/filepath"
	"testing"
	"testing/fstest"
)

const firstFixtureMigration = `
CREATE TABLE records (id INTEGER PRIMARY KEY, value TEXT NOT NULL);
INSERT INTO records (id, value) VALUES (1, 'before');
`

func TestRunMigrationsCreatesPreMigrationCopy(t *testing.T) {
	t.Parallel()

	databasePath := filepath.Join(t.TempDir(), "fixture.db")
	database := openFixtureDatabase(t, databasePath)

	firstSet := fstest.MapFS{
		"migrations/001_initial.sql": &fstest.MapFile{Data: []byte(firstFixtureMigration)},
	}
	if err := runMigrations(database, databasePath, firstSet); err != nil {
		t.Fatalf("apply first migration: %v", err)
	}

	before, err := os.ReadFile(databasePath)
	if err != nil {
		t.Fatalf("read pre-migration database: %v", err)
	}

	secondSet := fstest.MapFS{
		"migrations/001_initial.sql": &fstest.MapFile{Data: []byte(firstFixtureMigration)},
		"migrations/002_label.sql": {
			Data: []byte(`
ALTER TABLE records ADD COLUMN label TEXT;
UPDATE records SET label = 'after' WHERE id = 1;
`),
		},
	}
	if err := runMigrations(database, databasePath, secondSet); err != nil {
		t.Fatalf("apply second migration: %v", err)
	}

	backup, err := os.ReadFile(databasePath + ".pre-migrate-1")
	if err != nil {
		t.Fatalf("read pre-migration copy: %v", err)
	}
	if !bytes.Equal(backup, before) {
		t.Fatal("pre-migration copy does not match the database bytes before migration 2")
	}
	if got := readUserVersion(t, database); got != 2 {
		t.Fatalf("user_version = %d, want 2", got)
	}

	var label string
	if err := database.QueryRow("SELECT label FROM records WHERE id = 1").Scan(&label); err != nil {
		t.Fatalf("read migrated record: %v", err)
	}
	if label != "after" {
		t.Fatalf("migrated label = %q, want %q", label, "after")
	}
}

func TestRunMigrationsRollsBackFailedMigration(t *testing.T) {
	t.Parallel()

	databasePath := filepath.Join(t.TempDir(), "fixture.db")
	database := openFixtureDatabase(t, databasePath)
	firstSet := fstest.MapFS{
		"migrations/001_initial.sql": &fstest.MapFile{Data: []byte(firstFixtureMigration)},
	}
	if err := runMigrations(database, databasePath, firstSet); err != nil {
		t.Fatalf("apply first migration: %v", err)
	}

	failingSet := fstest.MapFS{
		"migrations/001_initial.sql": &fstest.MapFile{Data: []byte(firstFixtureMigration)},
		"migrations/002_broken.sql": {
			Data: []byte(`
CREATE TABLE rolled_back (id INTEGER PRIMARY KEY);
INSERT INTO table_that_does_not_exist (id) VALUES (1);
`),
		},
	}
	if err := runMigrations(database, databasePath, failingSet); err == nil {
		t.Fatal("failing migration unexpectedly succeeded")
	}

	if got := readUserVersion(t, database); got != 1 {
		t.Fatalf("user_version after rollback = %d, want 1", got)
	}
	var rolledBackTableCount int
	if err := database.QueryRow(
		"SELECT count(*) FROM sqlite_master WHERE type = 'table' AND name = 'rolled_back'",
	).Scan(&rolledBackTableCount); err != nil {
		t.Fatalf("inspect rolled-back table: %v", err)
	}
	if rolledBackTableCount != 0 {
		t.Fatalf("rolled_back table count = %d, want 0", rolledBackTableCount)
	}
}

func TestDiscoverMigrationsUsesFilenameOrdinals(t *testing.T) {
	t.Parallel()

	migrationSet := fstest.MapFS{
		"migrations/010_tenth.sql":  &fstest.MapFile{Data: []byte("SELECT 10;")},
		"migrations/002_second.sql": &fstest.MapFile{Data: []byte("SELECT 2;")},
		"migrations/README.md":      &fstest.MapFile{Data: []byte("ignored")},
	}

	migrations, err := discoverMigrations(migrationSet)
	if err != nil {
		t.Fatalf("discover migrations: %v", err)
	}
	if len(migrations) != 2 {
		t.Fatalf("migration count = %d, want 2", len(migrations))
	}
	if migrations[0].version != 2 || migrations[1].version != 10 {
		t.Fatalf(
			"migration versions = [%d, %d], want [2, 10]",
			migrations[0].version,
			migrations[1].version,
		)
	}
}

func openFixtureDatabase(t *testing.T, databasePath string) *sql.DB {
	t.Helper()

	database, err := sql.Open("sqlite", databasePath)
	if err != nil {
		t.Fatalf("open fixture database: %v", err)
	}
	database.SetMaxOpenConns(1)
	if err := setPragmas(database, databasePath); err != nil {
		_ = database.Close()
		t.Fatalf("set fixture pragmas: %v", err)
	}
	t.Cleanup(func() {
		if err := database.Close(); err != nil {
			t.Errorf("close fixture database: %v", err)
		}
	})

	return database
}

func readUserVersion(t *testing.T, database *sql.DB) int {
	t.Helper()

	var version int
	if err := database.QueryRow("PRAGMA user_version").Scan(&version); err != nil {
		t.Fatalf("read user_version: %v", err)
	}

	return version
}
