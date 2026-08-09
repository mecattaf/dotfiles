package repo

import (
	"context"
	"database/sql"
	"fmt"
	"sort"
	"strings"

	"github.com/mecattaf/crm/internal/model"
)

const defaultFindLimit = 20

type scoredFindResult struct {
	result model.FindResult
	id     int64
	score  float64
}

// SearchRepo owns cross-entity FTS search and its global rank merge.
type SearchRepo struct {
	database *sql.DB
}

// NewSearchRepo constructs a search repository.
func NewSearchRepo(database *sql.DB) *SearchRepo {
	return &SearchRepo{database: database}
}

// Find searches the selected external-content FTS tables, normalizes bm25
// within each table, and returns one deterministic global result set.
func (repository *SearchRepo) Find(
	ctx context.Context,
	query string,
	filters model.FindFilters,
) ([]model.FindResult, error) {
	if filters.Type != "" && !model.ValidFindType(filters.Type) {
		return nil, model.NewExitError(
			model.ErrValidation,
			"invalid find type %q (accepted: %s)",
			filters.Type,
			strings.Join(model.FindTypes, ","),
		)
	}
	if filters.Limit < 0 {
		return nil, model.NewExitError(model.ErrValidation, "limit must be positive")
	}
	limit := filters.Limit
	if limit == 0 {
		limit = defaultFindLimit
	}

	ftsQuery, err := buildFTSQuery(query)
	if err != nil {
		return nil, err
	}

	results := make([]scoredFindResult, 0)
	matchedOrganizations := make([]scoredFindResult, 0)
	if filters.Type == "" || filters.Type == "org" || filters.Type == "contact" {
		matchedOrganizations, err = repository.searchOrganizations(ctx, ftsQuery)
		if err != nil {
			return nil, err
		}
		normalizeScores(matchedOrganizations)
		if filters.Type == "" || filters.Type == "org" {
			results = append(results, matchedOrganizations...)
		}
	}

	if filters.Type == "" || filters.Type == "contact" {
		contactResults, searchErr := repository.searchContacts(ctx, ftsQuery)
		if searchErr != nil {
			return nil, searchErr
		}
		normalizeScores(contactResults)
		results = append(results, contactResults...)

		linkedContacts, linkedErr := repository.contactsForOrganizations(
			ctx,
			matchedOrganizations,
		)
		if linkedErr != nil {
			return nil, linkedErr
		}
		results = append(results, linkedContacts...)
	}

	if filters.Type == "" || filters.Type == "interaction" {
		interactionResults, searchErr := repository.searchInteractions(ctx, ftsQuery)
		if searchErr != nil {
			return nil, searchErr
		}
		normalizeScores(interactionResults)
		results = append(results, interactionResults...)
	}

	if filters.Type == "" || filters.Type == "deal" {
		dealResults, searchErr := repository.searchDeals(ctx, ftsQuery)
		if searchErr != nil {
			return nil, searchErr
		}
		normalizeScores(dealResults)
		results = append(results, dealResults...)
	}

	results = strongestUniqueResults(results)
	sort.Slice(results, func(left, right int) bool {
		if results[left].score != results[right].score {
			return results[left].score > results[right].score
		}
		if results[left].result.Type != results[right].result.Type {
			return results[left].result.Type < results[right].result.Type
		}

		return results[left].id < results[right].id
	})
	if len(results) > limit {
		results = results[:limit]
	}

	rows := make([]model.FindResult, 0, len(results))
	for _, result := range results {
		result.result.Rank = result.score
		rows = append(rows, result.result)
	}

	return rows, nil
}

func buildFTSQuery(query string) (string, error) {
	tokens := strings.Fields(query)
	if len(tokens) == 0 {
		return "", model.NewExitError(model.ErrValidation, "find query must not be empty")
	}

	escaped := make([]string, len(tokens))
	for index, token := range tokens {
		token = strings.ReplaceAll(token, `"`, `""`)
		escaped[index] = `"` + token + `"`
	}
	escaped[len(escaped)-1] += "*"

	return strings.Join(escaped, " "), nil
}

func (repository *SearchRepo) searchOrganizations(
	ctx context.Context,
	ftsQuery string,
) ([]scoredFindResult, error) {
	rows, err := repository.database.QueryContext(
		ctx,
		`SELECT o.id, o.name, o.category, o.location, bm25(orgs_fts) AS score
		 FROM orgs_fts
		 JOIN orgs o ON o.id = orgs_fts.rowid
		 WHERE orgs_fts MATCH ? AND o.archived_at IS NULL
		 ORDER BY score ASC, o.id ASC`,
		ftsQuery,
	)
	if err != nil {
		return nil, fmt.Errorf("search organizations: %w", err)
	}

	results := make([]scoredFindResult, 0)
	for rows.Next() {
		var id int64
		var name string
		var category sql.NullString
		var location sql.NullString
		var score float64
		if err := rows.Scan(&id, &name, &category, &location, &score); err != nil {
			_ = rows.Close()
			return nil, fmt.Errorf("scan organization search result: %w", err)
		}
		results = append(results, scoredFindResult{
			result: model.FindResult{
				Type:   "org",
				Ref:    fmt.Sprintf("o%d", id),
				Name:   name,
				Detail: joinFindDetail(category, location),
			},
			id:    id,
			score: score,
		})
	}
	if err := rows.Err(); err != nil {
		_ = rows.Close()
		return nil, fmt.Errorf("iterate organization search results: %w", err)
	}
	if err := rows.Close(); err != nil {
		return nil, fmt.Errorf("close organization search results: %w", err)
	}

	return results, nil
}

func (repository *SearchRepo) searchContacts(
	ctx context.Context,
	ftsQuery string,
) ([]scoredFindResult, error) {
	rows, err := repository.database.QueryContext(
		ctx,
		`SELECT c.id, c.name, c.email, o.name, bm25(contacts_fts) AS score
		 FROM contacts_fts
		 JOIN contacts c ON c.id = contacts_fts.rowid
		 LEFT JOIN orgs o ON o.id = c.org_id
		 WHERE contacts_fts MATCH ? AND c.archived_at IS NULL
		 ORDER BY score ASC, c.id ASC`,
		ftsQuery,
	)
	if err != nil {
		return nil, fmt.Errorf("search contacts: %w", err)
	}

	results := make([]scoredFindResult, 0)
	for rows.Next() {
		result, scanErr := scanContactSearchResult(rows)
		if scanErr != nil {
			_ = rows.Close()
			return nil, fmt.Errorf("scan contact search result: %w", scanErr)
		}
		results = append(results, result)
	}
	if err := rows.Err(); err != nil {
		_ = rows.Close()
		return nil, fmt.Errorf("iterate contact search results: %w", err)
	}
	if err := rows.Close(); err != nil {
		return nil, fmt.Errorf("close contact search results: %w", err)
	}

	return results, nil
}

func scanContactSearchResult(row scanner) (scoredFindResult, error) {
	var id int64
	var name string
	var email sql.NullString
	var organizationName sql.NullString
	var score float64
	if err := row.Scan(&id, &name, &email, &organizationName, &score); err != nil {
		return scoredFindResult{}, err
	}

	return scoredFindResult{
		result: model.FindResult{
			Type:   "contact",
			Ref:    fmt.Sprintf("c%d", id),
			Name:   name,
			Detail: joinFindDetail(email, organizationName),
		},
		id:    id,
		score: score,
	}, nil
}

func (repository *SearchRepo) contactsForOrganizations(
	ctx context.Context,
	organizations []scoredFindResult,
) ([]scoredFindResult, error) {
	if len(organizations) == 0 {
		return []scoredFindResult{}, nil
	}

	placeholders := make([]string, len(organizations))
	arguments := make([]any, len(organizations))
	scoreByOrganizationID := make(map[int64]float64, len(organizations))
	for index, organization := range organizations {
		placeholders[index] = "?"
		arguments[index] = organization.id
		scoreByOrganizationID[organization.id] = organization.score
	}
	rows, err := repository.database.QueryContext(
		ctx,
		`SELECT c.id, c.name, c.email, o.name, c.org_id
		 FROM contacts c
		 JOIN orgs o ON o.id = c.org_id
		 WHERE c.archived_at IS NULL AND c.org_id IN (`+strings.Join(placeholders, ",")+`)
		 ORDER BY c.id ASC`,
		arguments...,
	)
	if err != nil {
		return nil, fmt.Errorf("find contacts of matched organizations: %w", err)
	}

	results := make([]scoredFindResult, 0)
	for rows.Next() {
		var id int64
		var name string
		var email sql.NullString
		var organizationName sql.NullString
		var organizationID int64
		if err := rows.Scan(
			&id,
			&name,
			&email,
			&organizationName,
			&organizationID,
		); err != nil {
			_ = rows.Close()
			return nil, fmt.Errorf("scan contact of matched organization: %w", err)
		}
		results = append(results, scoredFindResult{
			result: model.FindResult{
				Type:   "contact",
				Ref:    fmt.Sprintf("c%d", id),
				Name:   name,
				Detail: joinFindDetail(email, organizationName),
			},
			id:    id,
			score: scoreByOrganizationID[organizationID],
		})
	}
	if err := rows.Err(); err != nil {
		_ = rows.Close()
		return nil, fmt.Errorf("iterate contacts of matched organizations: %w", err)
	}
	if err := rows.Close(); err != nil {
		return nil, fmt.Errorf("close contacts of matched organizations: %w", err)
	}

	return results, nil
}

func (repository *SearchRepo) searchInteractions(
	ctx context.Context,
	ftsQuery string,
) ([]scoredFindResult, error) {
	rows, err := repository.database.QueryContext(
		ctx,
		`SELECT i.id, i.summary, i.occurred_on, i.kind,
		        bm25(interactions_fts) AS score
		 FROM interactions_fts
		 JOIN interactions i ON i.id = interactions_fts.rowid
		 WHERE interactions_fts MATCH ? AND i.archived_at IS NULL
		 ORDER BY score ASC, i.id ASC`,
		ftsQuery,
	)
	if err != nil {
		return nil, fmt.Errorf("search interactions: %w", err)
	}

	results := make([]scoredFindResult, 0)
	for rows.Next() {
		var id int64
		var summary string
		var occurredOn string
		var kind string
		var score float64
		if err := rows.Scan(&id, &summary, &occurredOn, &kind, &score); err != nil {
			_ = rows.Close()
			return nil, fmt.Errorf("scan interaction search result: %w", err)
		}
		results = append(results, scoredFindResult{
			result: model.FindResult{
				Type:   "interaction",
				Ref:    fmt.Sprintf("i%d", id),
				Name:   summary,
				Detail: occurredOn + " · " + kind,
			},
			id:    id,
			score: score,
		})
	}
	if err := rows.Err(); err != nil {
		_ = rows.Close()
		return nil, fmt.Errorf("iterate interaction search results: %w", err)
	}
	if err := rows.Close(); err != nil {
		return nil, fmt.Errorf("close interaction search results: %w", err)
	}

	return results, nil
}

func (repository *SearchRepo) searchDeals(
	ctx context.Context,
	ftsQuery string,
) ([]scoredFindResult, error) {
	rows, err := repository.database.QueryContext(
		ctx,
		`SELECT d.id, d.title, p.name, s.name, bm25(deals_fts) AS score
		 FROM deals_fts
		 JOIN deals d ON d.id = deals_fts.rowid
		 JOIN pipelines p ON p.id = d.pipeline_id
		 JOIN stages s ON s.id = d.stage_id
		 WHERE deals_fts MATCH ? AND d.archived_at IS NULL
		 ORDER BY score ASC, d.id ASC`,
		ftsQuery,
	)
	if err != nil {
		return nil, fmt.Errorf("search deals: %w", err)
	}

	results := make([]scoredFindResult, 0)
	for rows.Next() {
		var id int64
		var title string
		var pipelineName string
		var stageName string
		var score float64
		if err := rows.Scan(&id, &title, &pipelineName, &stageName, &score); err != nil {
			_ = rows.Close()
			return nil, fmt.Errorf("scan deal search result: %w", err)
		}
		results = append(results, scoredFindResult{
			result: model.FindResult{
				Type:   "deal",
				Ref:    fmt.Sprintf("d%d", id),
				Name:   title,
				Detail: pipelineName + " · " + stageName,
			},
			id:    id,
			score: score,
		})
	}
	if err := rows.Err(); err != nil {
		_ = rows.Close()
		return nil, fmt.Errorf("iterate deal search results: %w", err)
	}
	if err := rows.Close(); err != nil {
		return nil, fmt.Errorf("close deal search results: %w", err)
	}

	return results, nil
}

func normalizeScores(results []scoredFindResult) {
	if len(results) == 0 {
		return
	}

	best := results[0].score
	for index := range results {
		if results[index].score < best {
			best = results[index].score
		}
	}
	if best == 0 {
		for index := range results {
			results[index].score = 1
		}
		return
	}
	for index := range results {
		results[index].score /= best
	}
}

func strongestUniqueResults(results []scoredFindResult) []scoredFindResult {
	unique := make(map[string]scoredFindResult, len(results))
	for _, result := range results {
		key := result.result.Type + ":" + result.result.Ref
		current, exists := unique[key]
		if !exists || result.score > current.score {
			unique[key] = result
		}
	}

	merged := make([]scoredFindResult, 0, len(unique))
	for _, result := range unique {
		merged = append(merged, result)
	}

	return merged
}

func joinFindDetail(values ...sql.NullString) string {
	parts := make([]string, 0, len(values))
	for _, value := range values {
		if value.Valid && value.String != "" {
			parts = append(parts, value.String)
		}
	}

	return strings.Join(parts, " · ")
}
