package repo

import (
	"context"
	"database/sql"
	"fmt"
	"math"
	"sort"

	"github.com/mecattaf/crm/internal/model"
)

// DupeRepo owns the strictly read-only duplicate candidate report.
type DupeRepo struct {
	database *sql.DB
}

// NewDupeRepo constructs a duplicate report repository.
func NewDupeRepo(database *sql.DB) *DupeRepo {
	return &DupeRepo{database: database}
}

// Find scores every live pair of the requested types, sorts candidates
// deterministically, and applies the result limit only after global ranking.
func (repository *DupeRepo) Find(
	ctx context.Context,
	filters model.DupeFilters,
) ([]model.DupeResult, error) {
	if filters.Type != "" && !model.ValidDupeType(filters.Type) {
		return nil, model.NewExitError(
			model.ErrValidation,
			"invalid dupes type %q (accepted: contact,org)",
			filters.Type,
		)
	}
	if math.IsNaN(filters.Threshold) || math.IsInf(filters.Threshold, 0) ||
		filters.Threshold < 0 || filters.Threshold > 1 {
		return nil, model.NewExitError(
			model.ErrValidation,
			"threshold must be between 0 and 1",
		)
	}
	if filters.Limit < 0 {
		return nil, model.NewExitError(model.ErrValidation, "limit must not be negative")
	}

	results := make([]model.DupeResult, 0)
	if filters.Type == "" || filters.Type == "contact" {
		contacts, err := NewContactRepo(repository.database).List(
			ctx,
			model.ContactFilters{},
		)
		if err != nil {
			return nil, err
		}
		for leftIndex := 0; leftIndex < len(contacts); leftIndex++ {
			for rightIndex := leftIndex + 1; rightIndex < len(contacts); rightIndex++ {
				score, reasons := model.ContactDuplicateScore(
					contacts[leftIndex],
					contacts[rightIndex],
				)
				if score < filters.Threshold {
					continue
				}
				results = append(results, model.DupeResult{
					Left:    contacts[leftIndex],
					Right:   contacts[rightIndex],
					Score:   score,
					Reasons: reasons,
				})
			}
		}
	}
	if filters.Type == "" || filters.Type == "org" {
		organizations, err := NewOrgRepo(repository.database).List(ctx, model.OrgFilters{})
		if err != nil {
			return nil, err
		}
		for leftIndex := 0; leftIndex < len(organizations); leftIndex++ {
			for rightIndex := leftIndex + 1; rightIndex < len(organizations); rightIndex++ {
				score, reasons := model.OrgDuplicateScore(
					organizations[leftIndex],
					organizations[rightIndex],
				)
				if score < filters.Threshold {
					continue
				}
				results = append(results, model.DupeResult{
					Left:    organizations[leftIndex],
					Right:   organizations[rightIndex],
					Score:   score,
					Reasons: reasons,
				})
			}
		}
	}

	sort.Slice(results, func(leftIndex, rightIndex int) bool {
		left := results[leftIndex]
		right := results[rightIndex]
		if left.Score != right.Score {
			return left.Score > right.Score
		}
		leftRef := duplicateRecordRef(left.Left)
		rightRef := duplicateRecordRef(right.Left)
		if leftRef != rightRef {
			return leftRef < rightRef
		}

		return duplicateRecordRef(left.Right) < duplicateRecordRef(right.Right)
	})
	if filters.Limit > 0 && len(results) > filters.Limit {
		results = results[:filters.Limit]
	}

	return results, nil
}

func duplicateRecordRef(record any) string {
	switch value := record.(type) {
	case model.Contact:
		return value.Reference()
	case model.Org:
		return value.Reference()
	default:
		return fmt.Sprintf("%T", record)
	}
}
