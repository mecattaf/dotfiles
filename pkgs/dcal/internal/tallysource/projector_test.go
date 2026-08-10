package tallysource

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/mecattaf/dcal/internal/calendar"
	"github.com/mecattaf/dcal/internal/providers/local"
	"github.com/mecattaf/dcal/repo"
)

func TestProjectorIsIdempotentReadOnlyAndPrunesVanishedProducers(t *testing.T) {
	ctx := context.Background()
	client, err := repo.OpenFile(ctx, filepath.Join(t.TempDir(), "dcal.db"))
	require.NoError(t, err)
	r := repo.New(client)
	t.Cleanup(func() { require.NoError(t, r.Close()) })

	now := time.Date(2026, 8, 10, 10, 0, 0, 0, time.UTC)
	root := filepath.Join(t.TempDir(), "tally")
	projector := NewProjector(r)
	projector.root = root
	projector.now = func() time.Time { return now }
	projector.expander = calendarExpander{
		iterations: 2,
		horizon:    defaultHorizon,
		run: func(context.Context, string, ...string) ([]byte, error) {
			return []byte(sampleCalendarOutput), nil
		},
	}

	calendarExpression := "*-*-* 03:00:00"
	pollCadence := uint64(300)
	pollNext := now.Add(30 * time.Minute).Format(time.RFC3339)
	calendarLast := now.Add(-time.Hour).Format(time.RFC3339)
	pollLast := now.Add(-2 * time.Hour).Format(time.RFC3339)
	inventory := Inventory{SchemaVersion: 1, ProtocolVersion: 5, Items: []Producer{
		{
			Name:       "nightly-eval",
			Kind:       "calendar",
			Configured: true,
			Enabled:    true,
			Schedule: Schedule{
				CalendarExpression: &calendarExpression,
			},
			Runtime: Runtime{LastTrigger: &calendarLast, LastEmission: &calendarLast},
		},
		{
			Name:       "poll-sample",
			Kind:       "poll",
			Configured: true,
			Enabled:    true,
			Schedule: Schedule{
				PollCadenceSec: &pollCadence,
				NextTrigger:    &pollNext,
			},
			Runtime: Runtime{LastTrigger: &pollLast},
		},
	}}

	first, err := projector.Sync(ctx, inventory)
	require.NoError(t, err)
	assert.Equal(t, CalendarID, first.CalendarID)
	assert.Equal(t, 5, first.Events)
	assert.Zero(t, first.Pruned)

	cal, err := r.GetCalendar(ctx, CalendarID)
	require.NoError(t, err)
	assert.True(t, cal.ReadOnly)

	events, total, err := r.ListEvents(ctx, repo.ListEventsParams{
		Filter: repo.EventFilter{CalendarIDs: []string{CalendarID}},
	})
	require.NoError(t, err)
	require.Equal(t, 5, total)
	firstIDs := make(map[string]string, len(events))
	for _, event := range events {
		firstIDs[event.UID] = event.ID
	}

	second, err := projector.Sync(ctx, inventory)
	require.NoError(t, err)
	assert.Equal(t, first.Events, second.Events)
	assert.Zero(t, second.Pruned)
	events, total, err = r.ListEvents(ctx, repo.ListEventsParams{
		Filter: repo.EventFilter{CalendarIDs: []string{CalendarID}},
	})
	require.NoError(t, err)
	require.Equal(t, 5, total)
	for _, event := range events {
		assert.Equal(t, firstIDs[event.UID], event.ID)
	}

	ics, err := os.ReadFile(filepath.Join(root, calendarFile))
	require.NoError(t, err)
	assert.Equal(t, 5, strings.Count(string(ics), "BEGIN:VEVENT"))

	account, err := r.GetAccount(ctx, AccountID)
	require.NoError(t, err)
	provider, err := local.New(calendar.Account{
		ID:       account.ID,
		Kind:     calendar.AccountLocal,
		Settings: account.Settings,
	}, root)
	require.NoError(t, err)
	calendars, err := provider.ListCalendars(ctx)
	require.NoError(t, err)
	require.Len(t, calendars, 1)
	assert.True(t, calendars[0].ReadOnly)

	empty, err := projector.Sync(ctx, Inventory{SchemaVersion: 1, ProtocolVersion: 5, Items: []Producer{}})
	require.NoError(t, err)
	assert.Zero(t, empty.Events)
	assert.Equal(t, 5, empty.Pruned)
	_, total, err = r.ListEvents(ctx, repo.ListEventsParams{
		Filter: repo.EventFilter{CalendarIDs: []string{CalendarID}},
	})
	require.NoError(t, err)
	assert.Zero(t, total)
	ics, err = os.ReadFile(filepath.Join(root, calendarFile))
	require.NoError(t, err)
	assert.NotContains(t, string(ics), "BEGIN:VEVENT")
}

func TestEventUIDDependsOnlyOnProducerAndFiringInstant(t *testing.T) {
	at := time.Date(2026, 8, 11, 1, 0, 0, 0, time.UTC)
	assert.Equal(t, eventUID("nightly-eval", at), eventUID("nightly-eval", at.In(time.FixedZone("offset", 2*60*60))))
	assert.NotEqual(t, eventUID("nightly-eval", at), eventUID("poll-sample", at))
}
