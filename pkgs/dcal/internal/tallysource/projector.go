package tallysource

import (
	"context"
	"crypto/sha256"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/mecattaf/dcal/ent"
	"github.com/mecattaf/dcal/ent/account"
	"github.com/mecattaf/dcal/internal/calendar"
	"github.com/mecattaf/dcal/internal/eventconv"
	"github.com/mecattaf/dcal/internal/paths"
	"github.com/mecattaf/dcal/internal/providers/local"
	"github.com/mecattaf/dcal/repo"
)

const (
	AccountID    = "dcal-tally-source"
	CalendarID   = "dcal-tally-calendar"
	CalendarName = "tally"

	calendarFile       = "tally.ics"
	calendarRemoteID   = "file:" + calendarFile
	managedSourceKey   = "managedSource"
	managedSourceValue = "tally"
	eventDuration      = 15 * time.Minute
)

type Projector struct {
	repo     *repo.Repo
	root     string
	now      func() time.Time
	expander calendarExpander
}

type ProjectionResult struct {
	CalendarID string
	Events     int
	Pruned     int
}

func NewProjector(r *repo.Repo) *Projector {
	return &Projector{
		repo:     r,
		now:      time.Now,
		expander: newCalendarExpander(),
	}
}

// Sync replaces the complete managed tally snapshot. Stable UIDs make every
// upsert idempotent; pruning the complement removes firings from vanished or
// disabled producers.
func (p *Projector) Sync(ctx context.Context, inventory Inventory) (ProjectionResult, error) {
	if p == nil || p.repo == nil {
		return ProjectionResult{}, errors.New("tally projector requires a repository")
	}
	now := p.now().UTC()
	events, err := p.projectEvents(ctx, inventory.Items, now)
	if err != nil {
		return ProjectionResult{}, err
	}

	root, err := p.storageRoot()
	if err != nil {
		return ProjectionResult{}, err
	}
	provider, storedCalendar, err := p.ensureCalendar(ctx, root)
	if err != nil {
		return ProjectionResult{}, err
	}

	domainCalendar := calendar.Calendar{
		ID:                  storedCalendar.ID,
		AccountID:           AccountID,
		RemoteID:            calendarRemoteID,
		Name:                CalendarName,
		ReadOnly:            true,
		SupportedComponents: []string{calendar.ComponentVEvent},
	}
	if err := provider.ReplaceEvents(domainCalendar, events); err != nil {
		return ProjectionResult{}, fmt.Errorf("write tally calendar snapshot: %w", err)
	}

	uids := make([]string, 0, len(events))
	for i := range events {
		events[i].CalendarID = storedCalendar.ID
		if _, err := p.repo.UpsertEvent(ctx, eventconv.UpsertInput(storedCalendar.ID, &events[i])); err != nil {
			return ProjectionResult{}, fmt.Errorf("upsert tally event %q: %w", events[i].UID, err)
		}
		uids = append(uids, events[i].UID)
	}
	pruned, err := p.repo.DeleteEventsNotInUIDs(ctx, storedCalendar.ID, uids)
	if err != nil {
		return ProjectionResult{}, fmt.Errorf("prune tally events: %w", err)
	}

	return ProjectionResult{CalendarID: storedCalendar.ID, Events: len(events), Pruned: pruned}, nil
}

func (p *Projector) storageRoot() (string, error) {
	if p.root != "" {
		return p.root, nil
	}
	dataDir, err := paths.DataDir()
	if err != nil {
		return "", fmt.Errorf("resolve tally calendar data directory: %w", err)
	}
	return filepath.Join(dataDir, "tally"), nil
}

func (p *Projector) ensureCalendar(ctx context.Context, root string) (*local.Provider, *ent.Calendar, error) {
	absRoot, err := filepath.Abs(root)
	if err != nil {
		return nil, nil, fmt.Errorf("resolve tally calendar root: %w", err)
	}
	if err := os.MkdirAll(absRoot, 0o700); err != nil {
		return nil, nil, fmt.Errorf("create tally calendar root: %w", err)
	}

	settings := map[string]any{
		"root":                absRoot,
		local.SettingReadOnly: true,
		managedSourceKey:      managedSourceValue,
	}
	storedAccount, err := p.repo.GetAccount(ctx, AccountID)
	switch {
	case err == nil:
		if storedAccount.Kind != account.KindLocal {
			return nil, nil, fmt.Errorf("reserved tally account %q has kind %q", AccountID, storedAccount.Kind)
		}
		displayName := "Tally"
		storedAccount, err = p.repo.UpdateAccount(ctx, AccountID, repo.UpdateAccountInput{
			DisplayName: &displayName,
			Settings:    settings,
		})
	case repo.IsNotFound(err):
		storedAccount, err = p.repo.CreateAccount(ctx, repo.CreateAccountInput{
			ID:          AccountID,
			Kind:        account.KindLocal,
			DisplayName: "Tally",
			Settings:    settings,
		})
	}
	if err != nil {
		return nil, nil, fmt.Errorf("ensure tally account: %w", err)
	}

	domainAccount := calendar.Account{
		ID:          storedAccount.ID,
		Kind:        calendar.AccountLocal,
		DisplayName: storedAccount.DisplayName,
		Settings:    storedAccount.Settings,
	}
	provider, err := local.New(domainAccount, absRoot)
	if err != nil {
		return nil, nil, fmt.Errorf("open tally local provider: %w", err)
	}

	calendarPath := filepath.Join(absRoot, calendarFile)
	if info, statErr := os.Stat(calendarPath); statErr != nil {
		if !errors.Is(statErr, os.ErrNotExist) {
			return nil, nil, fmt.Errorf("stat tally calendar: %w", statErr)
		}
		if _, err := local.CreateCalendar(absRoot, CalendarName); err != nil {
			return nil, nil, fmt.Errorf("create tally calendar: %w", err)
		}
	} else if info.IsDir() {
		return nil, nil, fmt.Errorf("tally calendar path %q is a directory", calendarPath)
	}

	storedCalendar, err := p.repo.UpsertCalendar(ctx, repo.UpsertCalendarInput{
		ID:                  CalendarID,
		AccountID:           AccountID,
		RemoteID:            calendarRemoteID,
		Name:                CalendarName,
		Description:         "Scheduled and recent tally producer runs",
		ReadOnly:            true,
		SupportedComponents: []string{calendar.ComponentVEvent},
	})
	if err != nil {
		return nil, nil, fmt.Errorf("ensure tally calendar: %w", err)
	}
	return provider, storedCalendar, nil
}

type firing struct {
	producer     Producer
	at           time.Time
	scheduled    bool
	pollTick     bool
	lastTrigger  bool
	lastEmission bool
}

func (p *Projector) projectEvents(ctx context.Context, producers []Producer, now time.Time) ([]calendar.Event, error) {
	firings := make(map[string]*firing)
	names := make(map[string]struct{}, len(producers))
	for _, producer := range producers {
		if !producer.Configured || !producer.Enabled {
			continue
		}
		producer.Name = strings.TrimSpace(producer.Name)
		if producer.Name == "" {
			return nil, errors.New("tally producer has an empty name")
		}
		if _, exists := names[producer.Name]; exists {
			return nil, fmt.Errorf("duplicate tally producer name %q", producer.Name)
		}
		names[producer.Name] = struct{}{}

		isCalendar := producer.Kind == "calendar"
		isPoll := producer.Kind == "poll" || producer.Schedule.PollCadenceSec != nil
		if !isCalendar && !isPoll {
			continue
		}

		if isCalendar {
			if producer.Schedule.CalendarExpression == nil || strings.TrimSpace(*producer.Schedule.CalendarExpression) == "" {
				return nil, fmt.Errorf("calendar producer %q has no calendarExpression", producer.Name)
			}
			times, err := p.expander.future(ctx, *producer.Schedule.CalendarExpression, now)
			if err != nil {
				return nil, fmt.Errorf("expand tally producer %q: %w", producer.Name, err)
			}
			for _, at := range times {
				addFiring(firings, producer, at).scheduled = true
			}
		} else if at, ok, err := nextPollTick(producer); err != nil {
			return nil, err
		} else if ok && at.After(now) {
			addFiring(firings, producer, at).pollTick = true
		}

		if at, ok, err := runtimeTime(producer.Name, "lastTrigger", producer.Runtime.LastTrigger); err != nil {
			return nil, err
		} else if ok {
			addFiring(firings, producer, at).lastTrigger = true
		}
		if at, ok, err := runtimeTime(producer.Name, "lastEmission", producer.Runtime.LastEmission); err != nil {
			return nil, err
		} else if ok {
			addFiring(firings, producer, at).lastEmission = true
		}
	}

	events := make([]calendar.Event, 0, len(firings))
	for _, point := range firings {
		events = append(events, eventForFiring(*point))
	}
	sort.Slice(events, func(i, j int) bool {
		if events[i].Start.Equal(events[j].Start) {
			return events[i].UID < events[j].UID
		}
		return events[i].Start.Before(events[j].Start)
	})
	return events, nil
}

func addFiring(firings map[string]*firing, producer Producer, at time.Time) *firing {
	at = at.UTC()
	key := producer.Name + "\x00" + at.Format(time.RFC3339Nano)
	if existing := firings[key]; existing != nil {
		return existing
	}
	point := &firing{producer: producer, at: at}
	firings[key] = point
	return point
}

func nextPollTick(producer Producer) (time.Time, bool, error) {
	if producer.Schedule.NextTrigger != nil && strings.TrimSpace(*producer.Schedule.NextTrigger) != "" {
		at, err := time.Parse(time.RFC3339Nano, strings.TrimSpace(*producer.Schedule.NextTrigger))
		if err != nil {
			return time.Time{}, false, fmt.Errorf("tally producer %q nextTrigger is not RFC3339: %w", producer.Name, err)
		}
		return at.UTC(), true, nil
	}
	if producer.Schedule.PollCadenceSec == nil || producer.Runtime.LastTrigger == nil {
		return time.Time{}, false, nil
	}
	last, ok, err := runtimeTime(producer.Name, "lastTrigger", producer.Runtime.LastTrigger)
	if err != nil || !ok {
		return time.Time{}, false, err
	}
	seconds := *producer.Schedule.PollCadenceSec
	if seconds > uint64((1<<63-1)/int64(time.Second)) {
		return time.Time{}, false, fmt.Errorf("tally producer %q pollCadenceSec is too large", producer.Name)
	}
	return last.Add(time.Duration(seconds) * time.Second), true, nil
}

func runtimeTime(producerName, field string, raw *string) (time.Time, bool, error) {
	if raw == nil || strings.TrimSpace(*raw) == "" {
		return time.Time{}, false, nil
	}
	at, err := time.Parse(time.RFC3339Nano, strings.TrimSpace(*raw))
	if err != nil {
		return time.Time{}, false, fmt.Errorf("tally producer %q %s is not RFC3339: %w", producerName, field, err)
	}
	return at.UTC(), true, nil
}

func eventForFiring(point firing) calendar.Event {
	markers := make([]string, 0, 4)
	categories := []string{"tally"}
	if point.scheduled {
		markers = append(markers, "scheduled calendar firing")
		categories = append(categories, "scheduled")
	}
	if point.pollTick {
		markers = append(markers, "next poll tick")
		categories = append(categories, "scheduled")
	}
	if point.lastTrigger {
		markers = append(markers, "last trigger")
	}
	if point.lastEmission {
		markers = append(markers, "last emission")
	}
	if point.lastTrigger || point.lastEmission {
		categories = append(categories, "retrospective")
	}

	description := []string{
		"Tally producer: " + point.producer.Name,
		"Kind: " + point.producer.Kind,
		"Projection: " + strings.Join(markers, ", "),
	}
	if point.producer.Schedule.CalendarExpression != nil && strings.TrimSpace(*point.producer.Schedule.CalendarExpression) != "" {
		description = append(description, "Schedule: "+strings.TrimSpace(*point.producer.Schedule.CalendarExpression))
	}
	if point.producer.Schedule.PollCadenceSec != nil {
		description = append(description, fmt.Sprintf("Poll cadence: %ds", *point.producer.Schedule.PollCadenceSec))
	}
	if service := strings.TrimSpace(point.producer.Unit.Service); service != "" {
		description = append(description, "Unit: "+service)
	}

	uid := eventUID(point.producer.Name, point.at)
	return calendar.Event{
		UID:          uid,
		RemoteID:     uid,
		Summary:      point.producer.Name,
		Description:  strings.Join(description, "\n"),
		Status:       calendar.EventConfirmed,
		Start:        point.at,
		End:          point.at.Add(eventDuration),
		Categories:   categories,
		Transparency: "transparent",
	}
}

func eventUID(producerName string, at time.Time) string {
	identity := producerName + "\x00" + at.UTC().Format(time.RFC3339Nano)
	digest := sha256.Sum256([]byte(identity))
	return fmt.Sprintf("tally-%x@dcal", digest)
}
