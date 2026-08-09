package repo

import (
	"context"
	"database/sql"
	"fmt"
	"strings"

	"github.com/mecattaf/crm/internal/model"
)

const contactLastCTE = `entity_last AS (
    SELECT c.id, c.name, MAX(i.occurred_on) AS last
    FROM contacts c
    LEFT JOIN interaction_people ip ON ip.contact_id = c.id
    LEFT JOIN interactions i
        ON i.id = ip.interaction_id AND i.archived_at IS NULL
    WHERE c.archived_at IS NULL
    GROUP BY c.id, c.name
)`

const orgLastCTE = `org_interactions AS (
    SELECT i.org_id, i.id AS interaction_id, i.occurred_on
    FROM interactions i
    WHERE i.archived_at IS NULL AND i.org_id IS NOT NULL
    UNION
    SELECT c.org_id, i.id AS interaction_id, i.occurred_on
    FROM contacts c
    JOIN interaction_people ip ON ip.contact_id = c.id
    JOIN interactions i ON i.id = ip.interaction_id
    WHERE c.archived_at IS NULL
      AND c.org_id IS NOT NULL
      AND i.archived_at IS NULL
),
entity_last AS (
    SELECT o.id, o.name, MAX(oi.occurred_on) AS last
    FROM orgs o
    LEFT JOIN org_interactions oi ON oi.org_id = o.id
    WHERE o.archived_at IS NULL
    GROUP BY o.id, o.name
)`

const statusQuery = `WITH ` + contactLastCTE + `,
last_logged AS (
    SELECT MAX(occurred_on) AS occurred_on
    FROM interactions
    WHERE archived_at IS NULL
)
SELECT
    COALESCE((SELECT COUNT(*) FROM orgs WHERE archived_at IS NULL), 0),
    COALESCE((SELECT COUNT(*) FROM contacts WHERE archived_at IS NULL), 0),
    COALESCE((SELECT COUNT(*) FROM interactions WHERE archived_at IS NULL), 0),
    COALESCE((SELECT COUNT(*) FROM deals
              WHERE archived_at IS NULL AND status = 'open'), 0),
    last_logged.occurred_on,
    COALESCE(CAST(
        julianday(date('now', 'localtime')) - julianday(last_logged.occurred_on)
        AS INTEGER
    ), 0),
    COALESCE((SELECT COUNT(*) FROM entity_last WHERE last IS NULL), 0),
    COALESCE((SELECT COUNT(*) FROM entity_last
              WHERE last IS NULL
                 OR last < date('now', 'localtime', '-90 days')), 0),
    COALESCE((SELECT COUNT(*)
              FROM deals d
              JOIN stages s ON s.id = d.stage_id
              WHERE d.archived_at IS NULL AND ` + rottingDealPredicate + `), 0)
FROM last_logged`

const staleQuerySuffix = `
SELECT id, name, last
FROM entity_last
WHERE last IS NULL
   OR last < date('now', 'localtime', printf('-%d days', ?))`

// ReportRepo owns dashboard aggregates and last-touch worklists.
type ReportRepo struct {
	database *sql.DB
}

// NewReportRepo constructs the read-only report repository.
func NewReportRepo(database *sql.DB) *ReportRepo {
	return &ReportRepo{database: database}
}

// Status loads the fixed dashboard aggregates in one query. The command adds
// its already-resolved database path because filesystem resolution is not a
// repository concern.
func (repository *ReportRepo) Status(ctx context.Context) (*model.StatusReport, error) {
	var status model.StatusReport
	var lastLogged sql.NullString
	if err := repository.database.QueryRowContext(ctx, statusQuery).Scan(
		&status.Orgs,
		&status.Contacts,
		&status.Interactions,
		&status.OpenDeals,
		&lastLogged,
		&status.LastLoggedDaysAgo,
		&status.NeverContacted,
		&status.Stale90Days,
		&status.RottingDeals,
	); err != nil {
		return nil, fmt.Errorf("load status dashboard: %w", err)
	}
	status.LastLogged = nullString(lastLogged)

	return &status, nil
}

// Stale returns live contacts or organizations whose newest live interaction
// predates the requested window, including entities that have never been
// contacted. The explicit NULL ordering is part of the public contract.
func (repository *ReportRepo) Stale(
	ctx context.Context,
	filters model.StaleFilters,
) ([]model.StaleResult, error) {
	if filters.Days <= 0 {
		return nil, model.NewExitError(model.ErrValidation, "stale days must be positive")
	}

	entityType := filters.Type
	if entityType == "" {
		entityType = model.StaleTypeContact
	}
	if !model.ValidStaleType(entityType) {
		return nil, model.NewExitError(
			model.ErrValidation,
			"invalid stale type %q (accepted: %s)",
			entityType,
			strings.Join(model.StaleTypes, ","),
		)
	}

	cte := contactLastCTE
	prefix := "c"
	if entityType == model.StaleTypeOrg {
		cte = orgLastCTE
		prefix = "o"
	}
	query := "WITH " + cte + staleQuerySuffix
	if filters.RecentFirst {
		query += " ORDER BY (last IS NULL) ASC, last DESC, id DESC"
	} else {
		query += " ORDER BY (last IS NULL) DESC, last ASC, id ASC"
	}

	rows, err := repository.database.QueryContext(ctx, query, filters.Days)
	if err != nil {
		return nil, fmt.Errorf("load stale %ss: %w", entityType, err)
	}
	results := make([]model.StaleResult, 0)
	for rows.Next() {
		var result model.StaleResult
		var last sql.NullString
		if err := rows.Scan(&result.ID, &result.Name, &last); err != nil {
			_ = rows.Close()
			return nil, fmt.Errorf("scan stale %s: %w", entityType, err)
		}
		result.Type = entityType
		result.Ref = fmt.Sprintf("%s%d", prefix, result.ID)
		result.Last = nullString(last)
		results = append(results, result)
	}
	if err := rows.Err(); err != nil {
		_ = rows.Close()
		return nil, fmt.Errorf("iterate stale %ss: %w", entityType, err)
	}
	if err := rows.Close(); err != nil {
		return nil, fmt.Errorf("close stale %s rows: %w", entityType, err)
	}

	return results, nil
}
