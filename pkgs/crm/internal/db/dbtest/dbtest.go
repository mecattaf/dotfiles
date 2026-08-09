// Package dbtest supplies an in-memory database using crm's production funnel.
package dbtest

import (
	"database/sql"
	"testing"

	"github.com/mecattaf/crm/internal/db"
)

// Open returns an in-memory database with production pragmas and migrations.
func Open(t testing.TB) *sql.DB {
	t.Helper()

	database, err := db.Open(":memory:")
	if err != nil {
		t.Fatalf("open in-memory CRM database: %v", err)
	}
	t.Cleanup(func() {
		if err := database.Close(); err != nil {
			t.Errorf("close in-memory CRM database: %v", err)
		}
	})

	return database
}
