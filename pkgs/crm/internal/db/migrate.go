package db

import (
	"database/sql"
	"embed"
	"fmt"
	"io/fs"
	"net/url"
	"os"
	"path"
	"sort"
	"strconv"
	"strings"
)

//go:embed migrations/*.sql
var embeddedMigrations embed.FS

type migration struct {
	name    string
	version int
}

// LatestMigrationVersion returns the highest ordinal embedded in this binary.
func LatestMigrationVersion() (int, error) {
	migrations, err := discoverMigrations(embeddedMigrations)
	if err != nil {
		return 0, err
	}
	if len(migrations) == 0 {
		return 0, nil
	}

	return migrations[len(migrations)-1].version, nil
}

func runMigrations(database *sql.DB, databasePath string, migrationSet fs.FS) error {
	var currentVersion int
	if err := database.QueryRow("PRAGMA user_version").Scan(&currentVersion); err != nil {
		return fmt.Errorf("read user_version: %w", err)
	}

	migrations, err := discoverMigrations(migrationSet)
	if err != nil {
		return err
	}

	for _, next := range migrations {
		if next.version <= currentVersion {
			continue
		}

		if currentVersion > 0 && !isMemoryDatabase(databasePath) {
			if err := copyBeforeMigration(databasePath, currentVersion); err != nil {
				return fmt.Errorf("back up database before migration %s: %w", next.name, err)
			}
		}

		migrationSQL, err := fs.ReadFile(migrationSet, path.Join("migrations", next.name))
		if err != nil {
			return fmt.Errorf("read migration %s: %w", next.name, err)
		}
		if err := applyMigration(database, next, string(migrationSQL)); err != nil {
			return err
		}

		currentVersion = next.version
	}

	return nil
}

func discoverMigrations(migrationSet fs.FS) ([]migration, error) {
	entries, err := fs.ReadDir(migrationSet, "migrations")
	if err != nil {
		return nil, fmt.Errorf("read migrations directory: %w", err)
	}

	migrations := make([]migration, 0, len(entries))
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".sql") {
			continue
		}

		prefix, _, found := strings.Cut(entry.Name(), "_")
		if !found {
			return nil, fmt.Errorf("migration %s has no ordinal prefix", entry.Name())
		}
		version, err := strconv.Atoi(prefix)
		if err != nil || version < 1 {
			return nil, fmt.Errorf("migration %s has invalid ordinal %q", entry.Name(), prefix)
		}

		migrations = append(migrations, migration{name: entry.Name(), version: version})
	}

	sort.Slice(migrations, func(left, right int) bool {
		return migrations[left].version < migrations[right].version
	})
	for index := 1; index < len(migrations); index++ {
		if migrations[index-1].version == migrations[index].version {
			return nil, fmt.Errorf(
				"migrations %s and %s share ordinal %d",
				migrations[index-1].name,
				migrations[index].name,
				migrations[index].version,
			)
		}
	}

	return migrations, nil
}

func applyMigration(database *sql.DB, next migration, migrationSQL string) error {
	transaction, err := database.Begin()
	if err != nil {
		return fmt.Errorf("begin migration %s: %w", next.name, err)
	}
	defer func() {
		_ = transaction.Rollback()
	}()

	if _, err := transaction.Exec(migrationSQL); err != nil {
		return fmt.Errorf("execute migration %s: %w", next.name, err)
	}

	// Placeholders are illegal in PRAGMA user_version; the ordinal is parsed
	// from an embedded migration filename and never comes from user input.
	versionStatement := fmt.Sprintf("PRAGMA user_version = %d", next.version)
	if _, err := transaction.Exec(versionStatement); err != nil {
		return fmt.Errorf("set user_version to %d: %w", next.version, err)
	}
	if err := transaction.Commit(); err != nil {
		return fmt.Errorf("commit migration %s: %w", next.name, err)
	}

	return nil
}

func copyBeforeMigration(databasePath string, version int) error {
	filePath, err := databaseFilePath(databasePath)
	if err != nil {
		return err
	}

	info, err := os.Stat(filePath)
	if err != nil {
		return fmt.Errorf("inspect database file %s: %w", filePath, err)
	}
	contents, err := os.ReadFile(filePath)
	if err != nil {
		return fmt.Errorf("read database file %s: %w", filePath, err)
	}

	backupPath := fmt.Sprintf("%s.pre-migrate-%d", filePath, version)
	if err := os.WriteFile(backupPath, contents, info.Mode().Perm()); err != nil {
		return fmt.Errorf("write migration backup %s: %w", backupPath, err)
	}

	return nil
}

func databaseFilePath(databasePath string) (string, error) {
	if !strings.HasPrefix(databasePath, "file:") {
		return databasePath, nil
	}

	parsed, err := url.Parse(databasePath)
	if err != nil {
		return "", fmt.Errorf("parse database URI: %w", err)
	}

	filePath := parsed.Path
	if filePath == "" {
		filePath = parsed.Opaque
	}
	filePath, err = url.PathUnescape(filePath)
	if err != nil {
		return "", fmt.Errorf("decode database URI path: %w", err)
	}
	if filePath == "" {
		return "", fmt.Errorf("database URI has no file path: %s", databasePath)
	}

	return filePath, nil
}
