package tallysource

import (
	"context"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

const sampleCalendarOutput = `Normalized form: *-*-* 03:00:00
    Next elapse: Tue 2026-08-11 03:00:00 CEST
       (in UTC): Tue 2026-08-11 01:00:00 UTC
       From now: 15h left
   Iteration #2: Wed 2026-08-12 03:00:00 CEST
       (in UTC): Wed 2026-08-12 01:00:00 UTC
       From now: 1 day 15h left
`

func TestParseCalendarOutputUsesUTCProjection(t *testing.T) {
	times, err := parseCalendarOutput([]byte(sampleCalendarOutput))
	require.NoError(t, err)
	require.Len(t, times, 2)
	assert.Equal(t, time.Date(2026, 8, 11, 1, 0, 0, 0, time.UTC), times[0])
	assert.Equal(t, time.Date(2026, 8, 12, 1, 0, 0, 0, time.UTC), times[1])
}

func TestCalendarExpanderCapsIterationsAndHorizon(t *testing.T) {
	base := time.Date(2026, 8, 10, 10, 0, 0, 0, time.UTC)
	var commandArgs []string
	expander := calendarExpander{
		iterations: defaultIterations + 1,
		horizon:    36 * time.Hour,
		run: func(_ context.Context, name string, args ...string) ([]byte, error) {
			assert.Equal(t, "systemd-analyze", name)
			commandArgs = append([]string(nil), args...)
			return []byte(sampleCalendarOutput), nil
		},
	}

	times, err := expander.future(context.Background(), "*-*-* 03:00:00", base)
	require.NoError(t, err)
	require.Len(t, times, 1)
	assert.Contains(t, strings.Join(commandArgs, " "), "--iterations=512")
	assert.Contains(t, strings.Join(commandArgs, " "), "--base-time=2026-08-10T10:00:00Z")
}
