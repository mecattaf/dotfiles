package repo_test

import (
	"reflect"
	"regexp"
	"testing"

	"github.com/mecattaf/crm/internal/db/dbtest"
	"github.com/mecattaf/crm/internal/model"
)

func TestDealStatusesMatchSQLiteCheckConstraint(t *testing.T) {
	t.Parallel()

	database := dbtest.Open(t)
	var tableSQL string
	if err := database.QueryRow(
		"SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'deals'",
	).Scan(&tableSQL); err != nil {
		t.Fatalf("read deals DDL: %v", err)
	}

	checkPattern := regexp.MustCompile(`(?i)status\s+IN\s*\(([^)]*)\)`)
	match := checkPattern.FindStringSubmatch(tableSQL)
	if len(match) != 2 {
		t.Fatalf("deals DDL has no parsable status CHECK: %s", tableSQL)
	}
	quotedValue := regexp.MustCompile(`'([^']*)'`)
	valueMatches := quotedValue.FindAllStringSubmatch(match[1], -1)
	databaseStatuses := make([]string, 0, len(valueMatches))
	for _, valueMatch := range valueMatches {
		databaseStatuses = append(databaseStatuses, valueMatch[1])
	}
	if !reflect.DeepEqual(databaseStatuses, model.DealStatuses) {
		t.Fatalf("database statuses = %v, Go statuses = %v", databaseStatuses, model.DealStatuses)
	}
}
