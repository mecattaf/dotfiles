package tallysource

import (
	"bufio"
	"bytes"
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"sort"
	"strconv"
	"strings"
	"time"
)

const (
	defaultIterations = 512
	defaultHorizon    = 7 * 24 * time.Hour
)

type commandRunner func(ctx context.Context, name string, args ...string) ([]byte, error)

type calendarExpander struct {
	run        commandRunner
	iterations int
	horizon    time.Duration
}

func newCalendarExpander() calendarExpander {
	return calendarExpander{
		run:        runCommand,
		iterations: defaultIterations,
		horizon:    defaultHorizon,
	}
}

func (e calendarExpander) future(ctx context.Context, expression string, base time.Time) ([]time.Time, error) {
	expression = strings.TrimSpace(expression)
	if expression == "" {
		return nil, errors.New("empty calendar expression")
	}
	iterations := e.iterations
	if iterations <= 0 || iterations > defaultIterations {
		iterations = defaultIterations
	}
	horizon := e.horizon
	if horizon <= 0 {
		horizon = defaultHorizon
	}

	output, err := e.run(
		ctx,
		"systemd-analyze",
		"calendar",
		"--iterations="+strconv.Itoa(iterations),
		"--base-time="+base.Format(time.RFC3339Nano),
		expression,
	)
	if err != nil {
		message := strings.TrimSpace(string(output))
		if message == "" {
			message = err.Error()
		}
		return nil, fmt.Errorf("systemd-analyze calendar %q: %s", expression, message)
	}

	times, err := parseCalendarOutput(output)
	if err != nil {
		return nil, fmt.Errorf("systemd-analyze calendar %q: %w", expression, err)
	}
	limit := base.Add(horizon)
	out := times[:0]
	for _, at := range times {
		if at.After(base) && !at.After(limit) {
			out = append(out, at)
		}
	}
	return out, nil
}

func runCommand(ctx context.Context, name string, args ...string) ([]byte, error) {
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.Env = localeC(os.Environ())
	return cmd.CombinedOutput()
}

func localeC(env []string) []string {
	out := make([]string, 0, len(env)+2)
	for _, item := range env {
		if strings.HasPrefix(item, "LC_ALL=") || strings.HasPrefix(item, "LANG=") {
			continue
		}
		out = append(out, item)
	}
	return append(out, "LC_ALL=C", "LANG=C")
}

func parseCalendarOutput(output []byte) ([]time.Time, error) {
	seen := make(map[time.Time]struct{})
	var out []time.Time
	scanner := bufio.NewScanner(bytes.NewReader(output))
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		isUTCDetail := strings.HasPrefix(line, "(in UTC):")
		isIteration := strings.HasPrefix(line, "Next elapse:") || strings.HasPrefix(line, "Iteration #")
		if (!isUTCDetail && !isIteration) || !strings.HasSuffix(line, " UTC") {
			continue
		}
		colon := strings.IndexByte(line, ':')
		if colon < 0 {
			continue
		}
		at, err := time.Parse("Mon 2006-01-02 15:04:05 MST", strings.TrimSpace(line[colon+1:]))
		if err != nil {
			return nil, fmt.Errorf("parse UTC firing %q: %w", line, err)
		}
		at = at.UTC()
		if _, ok := seen[at]; ok {
			continue
		}
		seen[at] = struct{}{}
		out = append(out, at)
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	if len(out) == 0 && !bytes.Contains(output, []byte("never")) {
		return nil, errors.New("output contained no UTC firing times")
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Before(out[j]) })
	return out, nil
}
