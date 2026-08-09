package resolve

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"unicode"

	"github.com/mecattaf/crm/internal/model"
)

// Entity identifies one resolvable CRM record family.
type Entity string

// Supported reference entities and their CLI nouns.
const (
	EntityOrg         Entity = "org"
	EntityContact     Entity = "contact"
	EntityInteraction Entity = "interaction"
	EntityDeal        Entity = "deal"
	EntityPipeline    Entity = "pipeline"
	EntityStage       Entity = "stage"
)

// Match is the stable identity returned by reference resolution.
type Match struct {
	Entity Entity
	ID     int64
	Ref    string
}

// Candidate is one ambiguity choice. Line starts with a pasteable prefixed
// ref and then adds human disambiguation fields.
type Candidate struct {
	Ref       string
	Label     string
	Detail    string
	Secondary string
}

// Line renders one candidate for an ambiguity error.
func (candidate Candidate) Line() string {
	parts := []string{candidate.Ref}
	for _, value := range []string{candidate.Label, candidate.Detail, candidate.Secondary} {
		cleaned := strings.Join(strings.Fields(value), " ")
		if cleaned != "" {
			parts = append(parts, cleaned)
		}
	}

	return strings.Join(parts, "  ")
}

// AmbiguousError classifies a reference collision and preserves the two
// pasteable candidates selected by the rung's LIMIT 2 query.
type AmbiguousError struct {
	*model.ExitError
	Candidates []Candidate
}

// NotFoundError classifies an unresolved reference.
type NotFoundError struct {
	*model.ExitError
	wrongPrefix bool
}

type entitySpec struct {
	entity          Entity
	prefix          string
	from            string
	selectList      string
	idColumn        string
	liveColumn      string
	emailColumn     string
	linkedInColumn  string
	nameColumn      string
	nameNormColumn  string
	scopedNamesOnly bool
}

// Ref walks the shared seven-rung ladder for one entity. Each rung is a
// separate LIMIT 2 query; a unique hit returns immediately and a collision
// never falls through to a later rung.
func Ref(
	ctx context.Context,
	database *sql.DB,
	entity Entity,
	rawRef string,
) (Match, error) {
	spec, err := specFor(entity)
	if err != nil {
		return Match{}, err
	}
	value := strings.TrimSpace(rawRef)

	if prefixedEntity, id, recognized := parsePrefixedID(value); recognized {
		if prefixedEntity != entity {
			return Match{}, wrongPrefixError(value, prefixedEntity, entity)
		}
		if id > 0 {
			if match, found, queryErr := resolveRung(
				ctx,
				database,
				spec,
				value,
				spec.idColumn+" = ?",
				id,
			); queryErr != nil || found {
				return match, queryErr
			}
		}
	}

	if id, ok := parseBareID(value); ok {
		if match, found, queryErr := resolveRung(
			ctx,
			database,
			spec,
			value,
			spec.idColumn+" = ?",
			id,
		); queryErr != nil || found {
			return match, queryErr
		}
	}

	if spec.scopedNamesOnly {
		return Match{}, notFound(entity, value)
	}

	match, found, err := resolveNamedRungs(
		ctx,
		database,
		spec,
		value,
		spec.liveColumn+" IS NULL",
	)
	if err != nil || found {
		return match, err
	}

	return Match{}, notFound(entity, value)
}

// ArchivedRefForConflict applies the non-ID resolver rungs only to archived
// rows. Lifecycle commands use it solely after normal resolution misses, so
// they can report that a retried archive already succeeded without making an
// archived row reachable for show, edit, or any other name-based operation.
func ArchivedRefForConflict(
	ctx context.Context,
	database *sql.DB,
	entity Entity,
	rawRef string,
) (Match, error) {
	spec, err := specFor(entity)
	if err != nil {
		return Match{}, err
	}
	value := strings.TrimSpace(rawRef)

	if prefixedEntity, id, recognized := parsePrefixedID(value); recognized {
		if prefixedEntity != entity {
			return Match{}, wrongPrefixError(value, prefixedEntity, entity)
		}
		if id > 0 {
			if match, found, queryErr := resolveRung(
				ctx,
				database,
				spec,
				value,
				spec.idColumn+" = ? AND "+spec.liveColumn+" IS NOT NULL",
				id,
			); queryErr != nil || found {
				return match, queryErr
			}
		}
	}

	if id, ok := parseBareID(value); ok {
		if match, found, queryErr := resolveRung(
			ctx,
			database,
			spec,
			value,
			spec.idColumn+" = ? AND "+spec.liveColumn+" IS NOT NULL",
			id,
		); queryErr != nil || found {
			return match, queryErr
		}
	}

	if spec.scopedNamesOnly {
		return Match{}, notFound(entity, value)
	}
	match, found, err := resolveNamedRungs(
		ctx,
		database,
		spec,
		value,
		spec.liveColumn+" IS NOT NULL",
	)
	if err != nil || found {
		return match, err
	}

	return Match{}, notFound(entity, value)
}

func resolveNamedRungs(
	ctx context.Context,
	database *sql.DB,
	spec entitySpec,
	value string,
	stateCondition string,
) (Match, bool, error) {
	if spec.emailColumn != "" {
		if email, ok := model.TryNormalizeEmail(value); ok {
			if match, found, queryErr := resolveRung(
				ctx,
				database,
				spec,
				value,
				stateCondition+" AND "+spec.emailColumn+" = ?",
				email,
			); queryErr != nil || found {
				return match, found, queryErr
			}
		}
	}

	if spec.linkedInColumn != "" {
		linkedIn, normalizeErr := model.NormalizeLinkedIn(value)
		if normalizeErr != nil {
			return Match{}, false, normalizeErr
		}
		if linkedIn != "" {
			if match, found, queryErr := resolveRung(
				ctx,
				database,
				spec,
				value,
				stateCondition+" AND "+spec.linkedInColumn+" = ?",
				linkedIn,
			); queryErr != nil || found {
				return match, found, queryErr
			}
		}
	}

	if spec.nameColumn != "" && value != "" {
		if match, found, queryErr := resolveRung(
			ctx,
			database,
			spec,
			value,
			stateCondition+" AND "+spec.nameColumn+" = ?",
			value,
		); queryErr != nil || found {
			return match, found, queryErr
		}
	}

	if spec.nameNormColumn != "" {
		nameNorm, ok := model.TryNormalizeName(value)
		if ok {
			if match, found, queryErr := resolveRung(
				ctx,
				database,
				spec,
				value,
				stateCondition+" AND "+spec.nameNormColumn+" = ?",
				nameNorm,
			); queryErr != nil || found {
				return match, found, queryErr
			}

			if match, found, queryErr := resolveRung(
				ctx,
				database,
				spec,
				value,
				stateCondition+" AND "+spec.nameNormColumn+" LIKE ? ESCAPE '\\'",
				"%"+escapeLike(nameNorm)+"%",
			); queryErr != nil || found {
				return match, found, queryErr
			}
		}
	}

	return Match{}, false, nil
}

// ContactOrOrgRef walks the shared resolution ladder across the two entity
// families accepted by crm context. A collision across families is
// ambiguous rather than silently preferring contacts or organizations.
func ContactOrOrgRef(
	ctx context.Context,
	database *sql.DB,
	rawRef string,
) (Match, error) {
	value := strings.TrimSpace(rawRef)
	entities := []Entity{EntityContact, EntityOrg}

	if prefixedEntity, _, recognized := parsePrefixedID(value); recognized {
		if prefixedEntity != EntityContact && prefixedEntity != EntityOrg {
			return Match{}, &NotFoundError{
				ExitError: model.NewExitError(
					model.ErrNotFound,
					"ref %q names %s, not a contact or org",
					value,
					entityWithArticle(prefixedEntity),
				),
				wrongPrefix: true,
			}
		}

		return Ref(ctx, database, prefixedEntity, value)
	}

	if id, ok := parseBareID(value); ok {
		return resolveAcrossEntities(
			ctx,
			database,
			entities,
			value,
			func(spec entitySpec) (string, []any, bool) {
				return spec.idColumn + " = ?", []any{id}, true
			},
		)
	}

	if email, ok := model.TryNormalizeEmail(value); ok {
		match, found, err := resolveAcrossEntitiesRung(
			ctx,
			database,
			entities,
			value,
			func(spec entitySpec) (string, []any, bool) {
				if spec.emailColumn == "" {
					return "", nil, false
				}
				return spec.liveColumn + " IS NULL AND " + spec.emailColumn + " = ?",
					[]any{email}, true
			},
		)
		if err != nil || found {
			return match, err
		}
	}

	linkedIn, normalizeErr := model.NormalizeLinkedIn(value)
	if normalizeErr != nil {
		return Match{}, normalizeErr
	}
	if linkedIn != "" {
		match, found, err := resolveAcrossEntitiesRung(
			ctx,
			database,
			entities,
			value,
			func(spec entitySpec) (string, []any, bool) {
				if spec.linkedInColumn == "" {
					return "", nil, false
				}
				return spec.liveColumn + " IS NULL AND " + spec.linkedInColumn + " = ?",
					[]any{linkedIn}, true
			},
		)
		if err != nil || found {
			return match, err
		}
	}

	if value != "" {
		match, found, err := resolveAcrossEntitiesRung(
			ctx,
			database,
			entities,
			value,
			func(spec entitySpec) (string, []any, bool) {
				return spec.liveColumn + " IS NULL AND " + spec.nameColumn + " = ?",
					[]any{value}, true
			},
		)
		if err != nil || found {
			return match, err
		}
	}

	if nameNorm, ok := model.TryNormalizeName(value); ok {
		match, found, err := resolveAcrossEntitiesRung(
			ctx,
			database,
			entities,
			value,
			func(spec entitySpec) (string, []any, bool) {
				return spec.liveColumn + " IS NULL AND " + spec.nameNormColumn + " = ?",
					[]any{nameNorm}, true
			},
		)
		if err != nil || found {
			return match, err
		}

		match, found, err = resolveAcrossEntitiesRung(
			ctx,
			database,
			entities,
			value,
			func(spec entitySpec) (string, []any, bool) {
				return spec.liveColumn + " IS NULL AND " +
						spec.nameNormColumn + " LIKE ? ESCAPE '\\'",
					[]any{"%" + escapeLike(nameNorm) + "%"}, true
			},
		)
		if err != nil || found {
			return match, err
		}
	}

	return Match{}, &NotFoundError{ExitError: model.NewExitError(
		model.ErrNotFound,
		"no contact or org %q — try: crm find %s",
		value,
		commandArgument(value),
	)}
}

type entityRung func(spec entitySpec) (condition string, arguments []any, applicable bool)

func resolveAcrossEntities(
	ctx context.Context,
	database *sql.DB,
	entities []Entity,
	rawRef string,
	rung entityRung,
) (Match, error) {
	match, found, err := resolveAcrossEntitiesRung(ctx, database, entities, rawRef, rung)
	if err != nil || found {
		return match, err
	}

	return Match{}, &NotFoundError{ExitError: model.NewExitError(
		model.ErrNotFound,
		"no contact or org %q — try: crm find %s",
		rawRef,
		commandArgument(rawRef),
	)}
}

func resolveAcrossEntitiesRung(
	ctx context.Context,
	database *sql.DB,
	entities []Entity,
	rawRef string,
	rung entityRung,
) (Match, bool, error) {
	candidates := make([]Candidate, 0, 2)
	for _, entity := range entities {
		spec, err := specFor(entity)
		if err != nil {
			return Match{}, false, err
		}
		condition, arguments, applicable := rung(spec)
		if !applicable {
			continue
		}
		matches, err := queryCandidates(ctx, database, spec, condition, arguments...)
		if err != nil {
			return Match{}, false, err
		}
		remaining := 2 - len(candidates)
		if len(matches) > remaining {
			matches = matches[:remaining]
		}
		candidates = append(candidates, matches...)
		if len(candidates) >= 2 {
			break
		}
	}

	switch len(candidates) {
	case 0:
		return Match{}, false, nil
	case 1:
		entity, id, recognized := parsePrefixedID(candidates[0].Ref)
		if !recognized || id <= 0 {
			return Match{}, false, fmt.Errorf("parse resolved ref %q", candidates[0].Ref)
		}
		return Match{Entity: entity, ID: id, Ref: candidates[0].Ref}, true, nil
	default:
		lines := make([]string, len(candidates))
		for index, candidate := range candidates {
			lines[index] = candidate.Line()
		}
		message := fmt.Sprintf(
			"ambiguous contact or org %q:\n%s",
			rawRef,
			strings.Join(lines, "\n"),
		)
		return Match{}, false, &AmbiguousError{
			ExitError:  model.NewExitError(model.ErrAmbiguous, "%s", message),
			Candidates: candidates,
		}
	}
}

// LinkRef resolves a relationship-bearing flag through the same ladder as
// Ref, replacing only an ordinary miss with the runnable create-command
// remedy. Ambiguity and wrong-entity prefixes retain their original errors.
func LinkRef(
	ctx context.Context,
	database *sql.DB,
	entity Entity,
	rawRef string,
) (Match, error) {
	match, err := Ref(ctx, database, entity, rawRef)
	if err == nil {
		return match, nil
	}

	var notFoundError *NotFoundError
	if errors.As(err, &notFoundError) && !notFoundError.wrongPrefix {
		return Match{}, LinkNotFound(entity, rawRef)
	}

	return Match{}, err
}

// PrefixedEntity recognizes a positive, pasteable prefixed id and returns
// the entity named by its prefix.
func PrefixedEntity(rawRef string) (Entity, bool) {
	entity, id, recognized := parsePrefixedID(strings.TrimSpace(rawRef))
	if !recognized || id <= 0 {
		return "", false
	}

	return entity, true
}

// StageRef resolves a stage inside one pipeline. Stage names have no global
// scope: after the prefixed-id rung, only exact and substring name_norm rungs
// are attempted within the named pipeline.
func StageRef(
	ctx context.Context,
	database *sql.DB,
	pipelineID int64,
	rawRef string,
) (Match, error) {
	if pipelineID <= 0 {
		return Match{}, model.NewExitError(model.ErrValidation, "pipeline id must be positive")
	}
	spec, err := specFor(EntityStage)
	if err != nil {
		return Match{}, err
	}
	value := strings.TrimSpace(rawRef)

	if prefixedEntity, id, recognized := parsePrefixedID(value); recognized {
		if prefixedEntity != EntityStage {
			return Match{}, wrongPrefixError(value, prefixedEntity, EntityStage)
		}
		if id > 0 {
			if match, found, queryErr := resolveRung(
				ctx,
				database,
				spec,
				value,
				spec.idColumn+" = ? AND e.pipeline_id = ?",
				id,
				pipelineID,
			); queryErr != nil || found {
				return match, queryErr
			}
		}
	}

	nameNorm, ok := model.TryNormalizeName(value)
	if !ok {
		return Match{}, notFound(EntityStage, value)
	}
	liveAndScoped := spec.liveColumn + " IS NULL AND e.pipeline_id = ?"
	if match, found, queryErr := resolveRung(
		ctx,
		database,
		spec,
		value,
		liveAndScoped+" AND "+spec.nameNormColumn+" = ?",
		pipelineID,
		nameNorm,
	); queryErr != nil || found {
		return match, queryErr
	}

	if match, found, queryErr := resolveRung(
		ctx,
		database,
		spec,
		value,
		liveAndScoped+" AND "+spec.nameNormColumn+" LIKE ? ESCAPE '\\'",
		pipelineID,
		"%"+escapeLike(nameNorm)+"%",
	); queryErr != nil || found {
		return match, queryErr
	}

	return Match{}, notFound(EntityStage, value)
}

// ArchivedStageRefForConflict is the pipeline-scoped counterpart to
// ArchivedRefForConflict. It exists only so a repeated name-based stage
// archive reports an idempotent conflict while ordinary StageRef remains
// live-only for name rungs.
func ArchivedStageRefForConflict(
	ctx context.Context,
	database *sql.DB,
	pipelineID int64,
	rawRef string,
) (Match, error) {
	if pipelineID <= 0 {
		return Match{}, model.NewExitError(model.ErrValidation, "pipeline id must be positive")
	}
	spec, err := specFor(EntityStage)
	if err != nil {
		return Match{}, err
	}
	value := strings.TrimSpace(rawRef)

	if prefixedEntity, id, recognized := parsePrefixedID(value); recognized {
		if prefixedEntity != EntityStage {
			return Match{}, wrongPrefixError(value, prefixedEntity, EntityStage)
		}
		if id > 0 {
			if match, found, queryErr := resolveRung(
				ctx,
				database,
				spec,
				value,
				spec.idColumn+" = ? AND e.pipeline_id = ? AND "+
					spec.liveColumn+" IS NOT NULL",
				id,
				pipelineID,
			); queryErr != nil || found {
				return match, queryErr
			}
		}
	}

	nameNorm, ok := model.TryNormalizeName(value)
	if !ok {
		return Match{}, notFound(EntityStage, value)
	}
	archivedAndScoped := spec.liveColumn + " IS NOT NULL AND e.pipeline_id = ?"
	if match, found, queryErr := resolveRung(
		ctx,
		database,
		spec,
		value,
		archivedAndScoped+" AND "+spec.nameNormColumn+" = ?",
		pipelineID,
		nameNorm,
	); queryErr != nil || found {
		return match, queryErr
	}

	if match, found, queryErr := resolveRung(
		ctx,
		database,
		spec,
		value,
		archivedAndScoped+" AND "+spec.nameNormColumn+" LIKE ? ESCAPE '\\'",
		pipelineID,
		"%"+escapeLike(nameNorm)+"%",
	); queryErr != nil || found {
		return match, queryErr
	}

	return Match{}, notFound(EntityStage, value)
}

// LinkNotFound returns the create-command remedy used at link-flag sites.
func LinkNotFound(entity Entity, rawRef string) error {
	if _, err := specFor(entity); err != nil {
		return err
	}
	value := strings.TrimSpace(rawRef)
	command := fmt.Sprintf("crm %s add %q", entity, value)

	return &NotFoundError{ExitError: model.NewExitError(
		model.ErrNotFound,
		"no %s %q — try: %s",
		entity,
		value,
		command,
	)}
}

func resolveRung(
	ctx context.Context,
	database *sql.DB,
	spec entitySpec,
	rawRef string,
	condition string,
	arguments ...any,
) (Match, bool, error) {
	candidates, err := queryCandidates(ctx, database, spec, condition, arguments...)
	if err != nil {
		return Match{}, false, err
	}
	switch len(candidates) {
	case 0:
		return Match{}, false, nil
	case 1:
		id, parseErr := idFromRef(candidates[0].Ref)
		if parseErr != nil {
			return Match{}, false, parseErr
		}

		return Match{Entity: spec.entity, ID: id, Ref: candidates[0].Ref}, true, nil
	default:
		lines := make([]string, len(candidates))
		for index, candidate := range candidates {
			lines[index] = candidate.Line()
		}
		message := fmt.Sprintf(
			"ambiguous %s %q:\n%s",
			spec.entity,
			rawRef,
			strings.Join(lines, "\n"),
		)

		return Match{}, false, &AmbiguousError{
			ExitError:  model.NewExitError(model.ErrAmbiguous, "%s", message),
			Candidates: candidates,
		}
	}
}

func queryCandidates(
	ctx context.Context,
	database *sql.DB,
	spec entitySpec,
	condition string,
	arguments ...any,
) ([]Candidate, error) {
	query := fmt.Sprintf(
		"SELECT %s FROM %s WHERE %s ORDER BY %s ASC LIMIT 2",
		spec.selectList,
		spec.from,
		condition,
		spec.idColumn,
	)
	rows, err := database.QueryContext(ctx, query, arguments...)
	if err != nil {
		return nil, fmt.Errorf("resolve %s reference: %w", spec.entity, err)
	}

	candidates := make([]Candidate, 0, 2)
	for rows.Next() {
		var id int64
		var candidate Candidate
		if err := rows.Scan(&id, &candidate.Label, &candidate.Detail, &candidate.Secondary); err != nil {
			_ = rows.Close()
			return nil, fmt.Errorf("scan %s reference candidate: %w", spec.entity, err)
		}
		candidate.Ref = spec.prefix + strconv.FormatInt(id, 10)
		candidates = append(candidates, candidate)
	}
	if err := rows.Err(); err != nil {
		_ = rows.Close()
		return nil, fmt.Errorf("iterate %s reference candidates: %w", spec.entity, err)
	}
	if err := rows.Close(); err != nil {
		return nil, fmt.Errorf("close %s reference candidates: %w", spec.entity, err)
	}

	return candidates, nil
}

func specFor(entity Entity) (entitySpec, error) {
	switch entity {
	case EntityOrg:
		return entitySpec{
			entity:         entity,
			prefix:         "o",
			from:           "orgs e",
			selectList:     "e.id, e.name, COALESCE(e.category, ''), COALESCE(e.location, '')",
			idColumn:       "e.id",
			liveColumn:     "e.archived_at",
			linkedInColumn: "e.linkedin",
			nameColumn:     "e.name",
			nameNormColumn: "e.name_norm",
		}, nil
	case EntityContact:
		return entitySpec{
			entity:         entity,
			prefix:         "c",
			from:           "contacts e LEFT JOIN orgs o ON o.id = e.org_id",
			selectList:     "e.id, e.name, COALESCE(e.email, ''), CASE WHEN o.name IS NULL THEN '' ELSE '@' || o.name END",
			idColumn:       "e.id",
			liveColumn:     "e.archived_at",
			emailColumn:    "e.email",
			linkedInColumn: "e.linkedin",
			nameColumn:     "e.name",
			nameNormColumn: "e.name_norm",
		}, nil
	case EntityInteraction:
		return entitySpec{
			entity:     entity,
			prefix:     "i",
			from:       "interactions e",
			selectList: "e.id, e.summary, e.occurred_on, e.kind",
			idColumn:   "e.id",
			liveColumn: "e.archived_at",
		}, nil
	case EntityDeal:
		return entitySpec{
			entity:         entity,
			prefix:         "d",
			from:           "deals e JOIN pipelines p ON p.id = e.pipeline_id JOIN stages s ON s.id = e.stage_id",
			selectList:     "e.id, e.title, p.name, s.name",
			idColumn:       "e.id",
			liveColumn:     "e.archived_at",
			nameColumn:     "e.title",
			nameNormColumn: "e.title_norm",
		}, nil
	case EntityPipeline:
		return entitySpec{
			entity:         entity,
			prefix:         "p",
			from:           "pipelines e",
			selectList:     "e.id, e.name, '', ''",
			idColumn:       "e.id",
			liveColumn:     "e.archived_at",
			nameColumn:     "e.name",
			nameNormColumn: "e.name_norm",
		}, nil
	case EntityStage:
		return entitySpec{
			entity:          entity,
			prefix:          "s",
			from:            "stages e JOIN pipelines p ON p.id = e.pipeline_id",
			selectList:      "e.id, e.name, p.name, ''",
			idColumn:        "e.id",
			liveColumn:      "e.archived_at",
			nameColumn:      "e.name",
			nameNormColumn:  "e.name_norm",
			scopedNamesOnly: true,
		}, nil
	default:
		return entitySpec{}, model.NewExitError(
			model.ErrValidation,
			"unsupported reference entity %q",
			entity,
		)
	}
}

func parsePrefixedID(value string) (Entity, int64, bool) {
	if len(value) < 2 || !allASCIIDigits(value[1:]) {
		return "", 0, false
	}
	entity, ok := entityForPrefix(value[:1])
	if !ok {
		return "", 0, false
	}
	id, err := strconv.ParseInt(value[1:], 10, 64)
	if err != nil {
		return entity, 0, true
	}

	return entity, id, true
}

func parseBareID(value string) (int64, bool) {
	if !allASCIIDigits(value) {
		return 0, false
	}
	id, err := strconv.ParseInt(value, 10, 64)
	if err != nil || id <= 0 {
		return 0, false
	}

	return id, true
}

func allASCIIDigits(value string) bool {
	if value == "" {
		return false
	}
	for _, current := range value {
		if current < '0' || current > '9' {
			return false
		}
	}

	return true
}

func entityForPrefix(prefix string) (Entity, bool) {
	switch prefix {
	case "o":
		return EntityOrg, true
	case "c":
		return EntityContact, true
	case "i":
		return EntityInteraction, true
	case "d":
		return EntityDeal, true
	case "p":
		return EntityPipeline, true
	case "s":
		return EntityStage, true
	default:
		return "", false
	}
}

func idFromRef(ref string) (int64, error) {
	id, err := strconv.ParseInt(ref[1:], 10, 64)
	if err != nil {
		return 0, fmt.Errorf("parse resolved ref %q: %w", ref, err)
	}

	return id, nil
}

func wrongPrefixError(value string, actual, expected Entity) error {
	return &NotFoundError{ExitError: model.NewExitError(
		model.ErrNotFound,
		"ref %q names %s, not %s",
		value,
		entityWithArticle(actual),
		entityWithArticle(expected),
	), wrongPrefix: true}
}

func entityWithArticle(entity Entity) string {
	article := "a"
	if entity == EntityOrg || entity == EntityInteraction {
		article = "an"
	}

	return article + " " + string(entity)
}

func notFound(entity Entity, value string) error {
	return &NotFoundError{ExitError: model.NewExitError(
		model.ErrNotFound,
		"no %s %q — try: crm find %s",
		entity,
		value,
		commandArgument(value),
	)}
}

func commandArgument(value string) string {
	if value != "" && strings.IndexFunc(value, func(current rune) bool {
		return !unicode.IsLetter(current) && !unicode.IsDigit(current) &&
			!strings.ContainsRune("-._@/:+", current)
	}) == -1 {
		return value
	}

	return strconv.Quote(value)
}

func escapeLike(value string) string {
	value = strings.ReplaceAll(value, "\\", "\\\\")
	value = strings.ReplaceAll(value, "%", "\\%")
	return strings.ReplaceAll(value, "_", "\\_")
}
