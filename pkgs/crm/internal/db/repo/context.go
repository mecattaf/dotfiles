package repo

import (
	"context"
	"database/sql"
	"fmt"

	"github.com/mecattaf/crm/internal/model"
)

// ContextRepo owns the one briefing assembler used by both context
// renderers.
type ContextRepo struct {
	database *sql.DB
}

// NewContextRepo constructs the context briefing repository.
func NewContextRepo(database *sql.DB) *ContextRepo {
	return &ContextRepo{database: database}
}

// Assemble loads one complete, capped context briefing for both renderers.
func (repository *ContextRepo) Assemble(
	ctx context.Context,
	target model.ContextTarget,
	limit int,
) (*model.Briefing, error) {
	if target.ID <= 0 {
		return nil, model.NewExitError(model.ErrValidation, "context target id must be positive")
	}
	if limit < 0 {
		return nil, model.NewExitError(model.ErrValidation, "limit must not be negative")
	}

	briefing := &model.Briefing{
		Links:    make([]model.ContextLink, 0),
		Deals:    make([]model.ContextDeal, 0),
		Timeline: make([]model.Interaction, 0),
	}

	switch target.Entity {
	case model.ContextContact:
		contact, err := NewContactRepo(repository.database).FindByID(ctx, target.ID)
		if err != nil {
			return nil, err
		}
		briefing.Contact = contact
		briefing.Links = contact.Links
		if contact.OrgID != nil {
			organization, findErr := NewOrgRepo(repository.database).FindByID(ctx, *contact.OrgID)
			if findErr != nil {
				return nil, findErr
			}
			briefing.Org = organization
		}
	case model.ContextOrg:
		organization, err := NewOrgRepo(repository.database).FindByID(ctx, target.ID)
		if err != nil {
			return nil, err
		}
		briefing.Org = organization
	default:
		return nil, model.NewExitError(
			model.ErrValidation,
			"unsupported context entity %q",
			target.Entity,
		)
	}

	deals, err := repository.loadDeals(ctx, target)
	if err != nil {
		return nil, err
	}
	briefing.Deals = deals

	timeline, total, err := repository.loadTimeline(ctx, target, limit)
	if err != nil {
		return nil, err
	}
	briefing.Timeline = timeline
	briefing.TimelineTotal = total

	return briefing, nil
}

func (repository *ContextRepo) loadDeals(
	ctx context.Context,
	target model.ContextTarget,
) ([]model.ContextDeal, error) {
	predicate := ""
	arguments := make([]any, 0, 2)
	switch target.Entity {
	case model.ContextContact:
		predicate = `(d.contact_id = ? OR d.org_id = (
            SELECT c.org_id FROM contacts c WHERE c.id = ?
        ))`
		arguments = append(arguments, target.ID, target.ID)
	case model.ContextOrg:
		predicate = `(d.org_id = ? OR EXISTS (
            SELECT 1 FROM contacts c
            WHERE c.id = d.contact_id AND c.org_id = ?
        ))`
		arguments = append(arguments, target.ID, target.ID)
	default:
		return nil, model.NewExitError(
			model.ErrValidation,
			"unsupported context entity %q",
			target.Entity,
		)
	}

	rows, err := repository.database.QueryContext(
		ctx,
		`SELECT d.id, d.title, s.name,
                CAST(julianday('now', 'utc') - julianday(d.stage_changed_at, 'utc') AS INTEGER)
         FROM deals d
         JOIN stages s ON s.id = d.stage_id
         WHERE d.archived_at IS NULL AND d.status = 'open' AND `+predicate+`
         ORDER BY d.title_norm ASC, d.id ASC`,
		arguments...,
	)
	if err != nil {
		return nil, fmt.Errorf("load context deals: %w", err)
	}
	deals := make([]model.ContextDeal, 0)
	for rows.Next() {
		var deal model.ContextDeal
		if err := rows.Scan(&deal.ID, &deal.Title, &deal.Stage, &deal.DaysInStage); err != nil {
			_ = rows.Close()
			return nil, fmt.Errorf("scan context deal: %w", err)
		}
		deal.Ref = fmt.Sprintf("d%d", deal.ID)
		deals = append(deals, deal)
	}
	if err := rows.Err(); err != nil {
		_ = rows.Close()
		return nil, fmt.Errorf("iterate context deals: %w", err)
	}
	if err := rows.Close(); err != nil {
		return nil, fmt.Errorf("close context deal rows: %w", err)
	}

	return deals, nil
}

func (repository *ContextRepo) loadTimeline(
	ctx context.Context,
	target model.ContextTarget,
	limit int,
) ([]model.Interaction, int, error) {
	predicate, arguments, err := contextTimelinePredicate(target)
	if err != nil {
		return nil, 0, err
	}

	var total int
	countQuery := "SELECT COUNT(*) FROM interactions i WHERE i.archived_at IS NULL AND " + predicate
	if err := repository.database.QueryRowContext(ctx, countQuery, arguments...).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count context timeline: %w", err)
	}

	query := "SELECT " + interactionColumns +
		" FROM interactions i WHERE i.archived_at IS NULL AND " + predicate +
		" ORDER BY i.occurred_on DESC, i.id DESC"
	queryArguments := append([]any(nil), arguments...)
	if limit > 0 {
		query += " LIMIT ?"
		queryArguments = append(queryArguments, limit)
	}

	rows, err := repository.database.QueryContext(ctx, query, queryArguments...)
	if err != nil {
		return nil, 0, fmt.Errorf("load context timeline: %w", err)
	}
	interactions := make([]model.Interaction, 0)
	for rows.Next() {
		interaction, scanErr := scanInteraction(rows)
		if scanErr != nil {
			_ = rows.Close()
			return nil, 0, fmt.Errorf("scan context timeline: %w", scanErr)
		}
		interactions = append(interactions, *interaction)
	}
	if err := rows.Err(); err != nil {
		_ = rows.Close()
		return nil, 0, fmt.Errorf("iterate context timeline: %w", err)
	}
	if err := rows.Close(); err != nil {
		return nil, 0, fmt.Errorf("close context timeline rows: %w", err)
	}

	// SetMaxOpenConns(1) makes a second query while sql.Rows is open
	// self-deadlock. The timeline is deliberately drained and closed before
	// this single batch participant query.
	if err := NewInteractionRepo(repository.database).loadContactIDs(ctx, interactions); err != nil {
		return nil, 0, err
	}

	return interactions, total, nil
}

func contextTimelinePredicate(target model.ContextTarget) (string, []any, error) {
	switch target.Entity {
	case model.ContextContact:
		return `EXISTS (
            SELECT 1 FROM interaction_people ip
            WHERE ip.interaction_id = i.id AND ip.contact_id = ?
        )`, []any{target.ID}, nil
	case model.ContextOrg:
		return `(i.org_id = ? OR EXISTS (
            SELECT 1
            FROM interaction_people ip
            JOIN contacts c ON c.id = ip.contact_id
            WHERE ip.interaction_id = i.id AND c.org_id = ?
        ))`, []any{target.ID, target.ID}, nil
	default:
		return "", nil, model.NewExitError(
			model.ErrValidation,
			"unsupported context entity %q",
			target.Entity,
		)
	}
}
