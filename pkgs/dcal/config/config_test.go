package config_test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/mecattaf/dcal/config"
)

var configEnvVars = []string{
	"DCAL_ICS_DIR",
	"DCAL_DEFAULT_CALENDAR",
	"DCAL_API_ADDR",
	"DCAL_OAUTH_ADDR",
	"DCAL_DB_PATH",
	"DCAL_GOOGLE_CLIENT_ID",
	"DCAL_GOOGLE_CLIENT_SECRET",
	"DCAL_MICROSOFT_CLIENT_ID",
	"DCAL_DISABLE_HTTP",
	"DCAL_DISABLE_IPC",
}

func clearConfigEnv(t *testing.T) {
	t.Helper()
	for _, key := range configEnvVars {
		t.Setenv(key, "")
		require.NoError(t, os.Unsetenv(key))
	}
}

func setXDG(t *testing.T, root string) {
	t.Helper()
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(root, "config"))
	t.Setenv("XDG_DATA_HOME", filepath.Join(root, "data"))
}

func TestConfigDefaultsNeedNoFile(t *testing.T) {
	clearConfigEnv(t)
	root := t.TempDir()
	setXDG(t, root)

	cfg, err := config.Load()
	require.NoError(t, err)
	assert.Equal(t, filepath.Join(root, "config", "dcal", "config.json"), config.Path())
	assert.Equal(t, filepath.Join(root, "data", "dcal", "collections"), cfg.ICSDir)
	assert.Equal(t, filepath.Join(root, "data", "dcal", "dcal.db"), cfg.DatabasePath)
	assert.Empty(t, cfg.DefaultCalendar)
	assert.Equal(t, 60, cfg.SyncIntervalMinutes)
	assert.NoFileExists(t, config.Path())
}

func TestConfigReadsPartialFile(t *testing.T) {
	clearConfigEnv(t)
	root := t.TempDir()
	setXDG(t, root)
	require.NoError(t, os.MkdirAll(filepath.Dir(config.Path()), 0o755))
	require.NoError(t, os.WriteFile(config.Path(), []byte(`{
  "ics_dir": "/srv/calendars",
  "default_calendar": "Work",
  "database_path": "/srv/index/dcal.db",
  "reminders_enabled": false,
  "snooze_minutes": 15
}`), 0o600))

	cfg, err := config.Load()
	require.NoError(t, err)
	assert.Equal(t, "/srv/calendars", cfg.ICSDir)
	assert.Equal(t, "Work", cfg.DefaultCalendar)
	assert.Equal(t, "/srv/index/dcal.db", cfg.DatabasePath)
	assert.False(t, cfg.RemindersEnabled)
	assert.Equal(t, 15, cfg.SnoozeMinutes)
	assert.Equal(t, "127.0.0.1:0", cfg.APIAddr)
}

func TestEnvironmentOverridesFile(t *testing.T) {
	clearConfigEnv(t)
	root := t.TempDir()
	setXDG(t, root)
	require.NoError(t, os.MkdirAll(filepath.Dir(config.Path()), 0o755))
	require.NoError(t, os.WriteFile(config.Path(), []byte(`{"ics_dir":"/from/file","default_calendar":"File"}`), 0o600))
	t.Setenv("DCAL_ICS_DIR", "/from/environment")
	t.Setenv("DCAL_DEFAULT_CALENDAR", "Environment")
	t.Setenv("DCAL_DISABLE_HTTP", "true")

	cfg, err := config.Load()
	require.NoError(t, err)
	assert.Equal(t, "/from/environment", cfg.ICSDir)
	assert.Equal(t, "Environment", cfg.DefaultCalendar)
	assert.True(t, cfg.DisableHTTP)
}

func TestInvalidConfigReturnsError(t *testing.T) {
	clearConfigEnv(t)
	root := t.TempDir()
	setXDG(t, root)
	require.NoError(t, os.MkdirAll(filepath.Dir(config.Path()), 0o755))
	require.NoError(t, os.WriteFile(config.Path(), []byte(`{not json`), 0o600))

	_, err := config.Load()
	require.ErrorContains(t, err, "parse")
}

func TestStoragePathsMustBeAbsolute(t *testing.T) {
	clearConfigEnv(t)
	root := t.TempDir()
	setXDG(t, root)
	require.NoError(t, os.MkdirAll(filepath.Dir(config.Path()), 0o755))
	require.NoError(t, os.WriteFile(config.Path(), []byte(`{"ics_dir":"relative"}`), 0o600))

	_, err := config.Load()
	require.EqualError(t, err, "ics_dir must be an absolute path")
}

func TestReminderOverrideResolve(t *testing.T) {
	ptrBool := func(v bool) *bool { return &v }
	ptrInt := func(v int) *int { return &v }
	ptrString := func(v string) *string { return &v }

	base := config.Defaults()
	override := &config.ReminderOverride{
		Enabled:                ptrBool(false),
		AllDayTime:             ptrString("07:30"),
		DefaultReminderMinutes: ptrInt(30),
	}
	got := override.Resolve(base)
	assert.False(t, got.RemindersEnabled)
	assert.Equal(t, "07:30", got.AllDayReminderTime)
	assert.Equal(t, 30, got.DefaultReminderMinutes)
	assert.False(t, override.IsEmpty())
	assert.True(t, (*config.ReminderOverride)(nil).IsEmpty())
}
