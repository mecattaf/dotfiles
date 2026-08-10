package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

const helperEnv = "GO_WANT_DCAL_CLI_HELPER"

func TestCLIHelperProcess(t *testing.T) {
	if os.Getenv(helperEnv) != "1" {
		return
	}
	separator := -1
	for i, arg := range os.Args {
		if arg == "--" {
			separator = i
			break
		}
	}
	if separator < 0 {
		fmt.Fprintln(os.Stderr, "missing helper argument separator")
		os.Exit(1)
	}
	rootCmd.SetArgs(os.Args[separator+1:])
	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintf(os.Stderr, "dcal: %v\n", err)
		os.Exit(exitCode(err))
	}
	os.Exit(0)
}

func TestDaemonBackedEventRoundTrip(t *testing.T) {
	root := shortTempRoot(t)
	setCLIEnv(t, root)
	t.Setenv("DCAL_DISABLE_HTTP", "true")
	require.NoError(t, os.MkdirAll(filepath.Join(root, "config", "dcal"), 0o755))
	require.NoError(t, os.WriteFile(filepath.Join(root, "config", "dcal", "config.json"), []byte(`{"default_calendar":"Work"}`), 0o600))

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	services, err := bootDaemonServices(ctx)
	require.NoError(t, err)
	t.Cleanup(services.Close)

	stdout, stderr, code := runCLI(t, services.SocketPath(), "calendar", "add", "Work")
	require.Equal(t, 0, code, stderr)
	assert.Equal(t, "Work", strings.TrimSpace(stdout))

	stdout, stderr, code = runCLI(t, services.SocketPath(),
		"add", "Design review",
		"--calendar", "Work",
		"--start", "2026-08-10T09:00:00+02:00",
		"--end", "2026-08-10T10:00:00+02:00",
	)
	require.Equal(t, 0, code, stderr)
	eventRef := strings.TrimSpace(stdout)
	require.NotEmpty(t, eventRef)
	assert.NotContains(t, eventRef, "\n")

	stdout, stderr, code = runCLI(t, services.SocketPath(), "ls", "--calendar", "Work")
	require.Equal(t, 0, code, stderr)
	assert.Contains(t, stdout, "Design review")
	assert.Contains(t, stdout, eventRef)

	stdout, stderr, code = runCLI(t, services.SocketPath(),
		"add", "Uses configured default",
		"--start", "2026-08-10T11:00:00+02:00",
		"--end", "2026-08-10T12:00:00+02:00",
	)
	require.Equal(t, 0, code, stderr)
	defaultEventRef := strings.TrimSpace(stdout)
	require.NotEmpty(t, defaultEventRef)

	stdout, stderr, code = runCLI(t, services.SocketPath(), "agenda", "--from", "2026-08-10", "--to", "2026-08-10")
	require.Equal(t, 0, code, stderr)
	assert.Contains(t, stdout, "Design review")
	assert.Contains(t, stdout, "Work")
	assert.Contains(t, stdout, "Uses configured default")

	stdout, stderr, code = runCLI(t, services.SocketPath(), "show", eventRef)
	require.Equal(t, 0, code, stderr)
	assert.Contains(t, stdout, "Design review")
	assert.Contains(t, stdout, eventRef)

	stdout, stderr, code = runCLI(t, services.SocketPath(), "edit", eventRef, "--title", "Reviewed design")
	require.Equal(t, 0, code, stderr)
	assert.Equal(t, eventRef, strings.TrimSpace(stdout))

	stdout, stderr, code = runCLI(t, services.SocketPath(), "show", eventRef, "--format", "json")
	require.Equal(t, 0, code, stderr)
	assert.JSONEq(t, fmt.Sprintf(`{"id":%q,"uid":%q,"calendarId":%q,"calendarName":"Work","summary":"Reviewed design","start":"2026-08-10T07:00:00Z","end":"2026-08-10T08:00:00Z","allDay":false,"status":"confirmed"}`,
		eventRef, jsonStringField(t, stdout, "uid"), jsonStringField(t, stdout, "calendarId")), stdout)

	icsPath := filepath.Join(root, "data", "dcal", "collections", "Work.ics")
	require.FileExists(t, icsPath)
	ics, err := os.ReadFile(icsPath)
	require.NoError(t, err)
	assert.Contains(t, string(ics), "SUMMARY:Reviewed design")

	stdout, stderr, code = runCLI(t, services.SocketPath(), "rm", eventRef)
	require.Equal(t, 0, code, stderr)
	assert.Equal(t, eventRef, strings.TrimSpace(stdout))
	_, stderr, code = runCLI(t, services.SocketPath(), "rm", defaultEventRef)
	require.Equal(t, 0, code, stderr)

	_, stderr, code = runCLI(t, services.SocketPath(), "show", eventRef)
	assert.Equal(t, exitNotFound, code, stderr)
}

func TestAddCRMContactUsesStubAndPersistsICSProperties(t *testing.T) {
	root := shortTempRoot(t)
	setCLIEnv(t, root)
	t.Setenv("DCAL_DISABLE_HTTP", "true")
	require.NoError(t, os.MkdirAll(filepath.Join(root, "config", "dcal"), 0o755))
	require.NoError(t, os.WriteFile(filepath.Join(root, "config", "dcal", "config.json"), []byte(`{"default_calendar":"Work"}`), 0o600))

	fakeCRM := filepath.Join(root, "fake-crm")
	crmLog := filepath.Join(root, "crm-argv.log")
	fake := `#!/bin/sh
printf '%s\n' "$*" >>"$DCAL_CRM_FAKE_LOG"
case "$2" in
  c42) printf '%s\n' '[{"ref":"c42","name":"Nick Dupont"}]' ;;
  c404) printf '%s\n' 'crm: error: contact not found: c404' >&2; exit 2 ;;
  c3) printf '%s\n' 'crm: error: ambiguous contact: c3' >&2; exit 3 ;;
  *) printf '%s\n' 'unexpected fake crm invocation' >&2; exit 1 ;;
esac
`
	require.NoError(t, os.WriteFile(fakeCRM, []byte(fake), 0o700))
	t.Setenv("DCAL_CRM_BIN", fakeCRM)
	t.Setenv("DCAL_CRM_FAKE_LOG", crmLog)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	services, err := bootDaemonServices(ctx)
	require.NoError(t, err)
	t.Cleanup(services.Close)

	_, stderr, code := runCLI(t, services.SocketPath(), "calendar", "add", "Work")
	require.Equal(t, 0, code, stderr)

	stdout, stderr, code := runCLI(t, services.SocketPath(),
		"add",
		"--calendar", "Work",
		"--crm", "c42",
		"--start", "2026-08-10T15:00:00+02:00",
		"--end", "2026-08-10T16:00:00+02:00",
	)
	require.Equal(t, 0, code, stderr)
	eventRef := strings.TrimSpace(stdout)
	require.NotEmpty(t, eventRef)

	stdout, stderr, code = runCLI(t, services.SocketPath(), "show", eventRef, "--format", "json")
	require.Equal(t, 0, code, stderr)
	var event eventRecord
	require.NoError(t, json.Unmarshal([]byte(stdout), &event))
	assert.Equal(t, "call with Nick Dupont", event.Summary)
	assert.Equal(t, "c42", event.CRMRef)
	assert.Equal(t, "call", event.CRMKind)

	argv, err := os.ReadFile(crmLog)
	require.NoError(t, err)
	assert.Equal(t, "show c42 --format json\n", string(argv))

	ics, err := os.ReadFile(filepath.Join(root, "data", "dcal", "collections", "Work.ics"))
	require.NoError(t, err)
	assert.Contains(t, string(ics), "SUMMARY:call with Nick Dupont")
	assert.Contains(t, string(ics), "X-CRM-REF:c42")
	assert.Contains(t, string(ics), "X-CRM-KIND:call")

	_, stderr, code = runCLI(t, services.SocketPath(),
		"add", "missing",
		"--calendar", "Work", "--crm", "c404",
		"--start", "2026-08-10T17:00:00+02:00", "--end", "2026-08-10T18:00:00+02:00",
	)
	assert.Equal(t, exitNotFound, code)
	assert.Contains(t, stderr, "contact not found: c404")

	_, stderr, code = runCLI(t, services.SocketPath(),
		"add", "ambiguous",
		"--calendar", "Work", "--crm", "c3",
		"--start", "2026-08-10T17:00:00+02:00", "--end", "2026-08-10T18:00:00+02:00",
	)
	assert.Equal(t, exitAmbiguous, code)
	assert.Contains(t, stderr, "ambiguous contact: c3")
}

func TestFreshSyncAndStatusAreCleanNoOps(t *testing.T) {
	root := shortTempRoot(t)
	setCLIEnv(t, root)

	stdout, stderr, code := runCLI(t, "", "sync")
	require.Equal(t, 0, code, stderr)
	assert.Empty(t, stdout)
	assert.Contains(t, stderr, "tally source skipped")

	stdout, stderr, code = runCLI(t, "", "status", "--format", "json")
	require.Equal(t, 0, code, stderr)
	assert.JSONEq(t, `{"accounts":[],"calendars":[],"eventCount":0,"lastSync":null}`, stdout)

	stdout, stderr, code = runCLI(t, "", "account", "ls", "--format", "json")
	require.Equal(t, 0, code, stderr)
	assert.JSONEq(t, `[]`, stdout)
}

func TestTallyFixtureSyncIsIdempotentAndReadOnly(t *testing.T) {
	root := shortTempRoot(t)
	setCLIEnv(t, root)
	t.Setenv("DCAL_DISABLE_HTTP", "true")
	fixture, err := filepath.Abs(filepath.Join("..", "..", "testdata", "tally-producers.json"))
	require.NoError(t, err)

	_, stderr, code := runCLI(t, "", "sync", "--tally-fixture", fixture)
	require.Equal(t, 0, code, stderr)
	first := cliStatus(t)
	require.Len(t, first.Calendars, 1)
	assert.Equal(t, "tally", first.Calendars[0].Name)
	require.Greater(t, first.Events, 0)

	_, stderr, code = runCLI(t, "", "sync", "--tally-fixture", fixture)
	require.Equal(t, 0, code, stderr)
	second := cliStatus(t)
	assert.Equal(t, first.Events, second.Events)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	services, err := bootDaemonServices(ctx)
	require.NoError(t, err)
	t.Cleanup(services.Close)

	stdout, stderr, code := runCLI(t, services.SocketPath(), "ls", "--calendar", "tally", "--format", "json")
	require.Equal(t, 0, code, stderr)
	var events []eventRecord
	require.NoError(t, json.Unmarshal([]byte(stdout), &events))
	require.NotEmpty(t, events)
	assert.True(t, hasFutureEvent(events, time.Now()))

	_, stderr, code = runCLI(t, services.SocketPath(), "edit", events[0].ID, "--title", "changed")
	assert.NotEqual(t, 0, code)
	assert.Contains(t, stderr, "read-only")
	_, stderr, code = runCLI(t, services.SocketPath(), "rm", events[0].ID)
	assert.NotEqual(t, 0, code)
	assert.Contains(t, stderr, "read-only")
}

func cliStatus(t *testing.T) statusResult {
	t.Helper()
	stdout, stderr, code := runCLI(t, "", "status", "--format", "json")
	require.Equal(t, 0, code, stderr)
	var result statusResult
	require.NoError(t, json.Unmarshal([]byte(stdout), &result))
	return result
}

func hasFutureEvent(events []eventRecord, now time.Time) bool {
	for _, event := range events {
		if event.Start.After(now) {
			return true
		}
	}
	return false
}

func shortTempRoot(t *testing.T) string {
	t.Helper()
	root, err := os.MkdirTemp("", "dc-")
	require.NoError(t, err)
	t.Cleanup(func() { require.NoError(t, os.RemoveAll(root)) })
	return root
}

func setCLIEnv(t *testing.T, root string) {
	t.Helper()
	for _, key := range []string{
		"DCAL_ICS_DIR",
		"DCAL_DEFAULT_CALENDAR",
		"DCAL_DB_PATH",
		"DCAL_SOCKET",
		"DCAL_GOOGLE_CLIENT_ID",
		"DCAL_GOOGLE_CLIENT_SECRET",
		"DCAL_MICROSOFT_CLIENT_ID",
		"TALLY_SOCKET",
	} {
		unsetEnv(t, key)
	}
	t.Setenv("HOME", root)
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(root, "config"))
	t.Setenv("XDG_DATA_HOME", filepath.Join(root, "data"))
	t.Setenv("XDG_CACHE_HOME", filepath.Join(root, "cache"))
	t.Setenv("XDG_STATE_HOME", filepath.Join(root, "state"))
	t.Setenv("XDG_RUNTIME_DIR", filepath.Join(root, "run"))
	t.Setenv("DBUS_SESSION_BUS_ADDRESS", "unix:path="+filepath.Join(root, "missing-bus"))
	t.Setenv("DCAL_LOG_LEVEL", "error")
}

func unsetEnv(t *testing.T, key string) {
	t.Helper()
	old, present := os.LookupEnv(key)
	require.NoError(t, os.Unsetenv(key))
	t.Cleanup(func() {
		if present {
			require.NoError(t, os.Setenv(key, old))
			return
		}
		require.NoError(t, os.Unsetenv(key))
	})
}

func runCLI(t *testing.T, socket string, args ...string) (stdout, stderr string, exit int) {
	t.Helper()
	commandArgs := []string{"-test.run=^TestCLIHelperProcess$", "--"}
	commandArgs = append(commandArgs, args...)
	cmd := exec.Command(os.Args[0], commandArgs...)
	cmd.Env = append(os.Environ(), helperEnv+"=1")
	if socket != "" {
		cmd.Env = append(cmd.Env, "DCAL_SOCKET="+socket)
	}
	var out, errOut bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &errOut
	err := cmd.Run()
	if err == nil {
		return out.String(), errOut.String(), 0
	}
	var exitErr *exec.ExitError
	require.ErrorAs(t, err, &exitErr)
	return out.String(), errOut.String(), exitErr.ExitCode()
}

func jsonStringField(t *testing.T, raw, field string) string {
	t.Helper()
	needle := `"` + field + `": "`
	start := strings.Index(raw, needle)
	require.NotEqual(t, -1, start, raw)
	start += len(needle)
	end := strings.Index(raw[start:], `"`)
	require.NotEqual(t, -1, end, raw)
	return raw[start : start+end]
}
