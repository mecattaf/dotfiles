// Package config loads dcal's XDG-scoped configuration.
package config

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/caarlos0/env/v11"

	dcalpaths "github.com/mecattaf/dcal/internal/support/paths"
)

const fileName = "config.json"

// Config is dcal's complete runtime configuration. The three storage and
// calendar fields are the user-facing core; the remaining fields preserve the
// daemon's headless service and reminder controls without depending on the old
// UI settings file.
type Config struct {
	ICSDir          string `json:"ics_dir" env:"DCAL_ICS_DIR"`
	DefaultCalendar string `json:"default_calendar" env:"DCAL_DEFAULT_CALENDAR"`
	DatabasePath    string `json:"database_path" env:"DCAL_DB_PATH"`

	APIAddr           string `json:"api_addr" env:"DCAL_API_ADDR"`
	OAuthBindAddr     string `json:"oauth_bind_addr" env:"DCAL_OAUTH_ADDR"`
	GoogleClientID    string `json:"google_client_id,omitempty" env:"DCAL_GOOGLE_CLIENT_ID"`
	GoogleSecret      string `json:"google_client_secret,omitempty" env:"DCAL_GOOGLE_CLIENT_SECRET"`
	MicrosoftClientID string `json:"microsoft_client_id,omitempty" env:"DCAL_MICROSOFT_CLIENT_ID"`
	DisableHTTP       bool   `json:"disable_http" env:"DCAL_DISABLE_HTTP"`
	DisableIPC        bool   `json:"disable_ipc" env:"DCAL_DISABLE_IPC"`

	Use24HourClock           bool   `json:"use_24_hour_clock"`
	RemindersEnabled         bool   `json:"reminders_enabled"`
	ReminderPersist          bool   `json:"reminder_persist"`
	AllDayReminders          bool   `json:"all_day_reminders"`
	AllDayReminderTime       string `json:"all_day_reminder_time"`
	AllDayReminderDaysBefore int    `json:"all_day_reminder_days_before"`
	DefaultReminderMinutes   int    `json:"default_reminder_minutes"`
	SnoozeMinutes            int    `json:"snooze_minutes"`
	NotificationSounds       bool   `json:"notification_sounds"`
	SyncIntervalMinutes      int    `json:"sync_interval_minutes"`
}

// ReminderOverride holds per-calendar reminder settings. Nil fields inherit
// their global value from Config.
type ReminderOverride struct {
	Enabled                *bool   `json:"enabled,omitempty"`
	Persist                *bool   `json:"persist,omitempty"`
	AllDay                 *bool   `json:"all_day,omitempty"`
	AllDayTime             *string `json:"all_day_time,omitempty"`
	AllDayDaysBefore       *int    `json:"all_day_days_before,omitempty"`
	DefaultReminderMinutes *int    `json:"default_reminder_minutes,omitempty"`
	SnoozeMinutes          *int    `json:"snooze_minutes,omitempty"`
}

// Defaults returns a configuration suitable for a fresh XDG tree. An empty
// DefaultCalendar selects the first writable Google calendar when one exists,
// otherwise the CLI creates and uses a local Personal calendar.
func Defaults() Config {
	dataDir := filepath.Join(dcalpaths.XDGDataHome(), "dcal")
	return Config{
		ICSDir:                   filepath.Join(dataDir, "collections"),
		DatabasePath:             filepath.Join(dataDir, "dcal.db"),
		APIAddr:                  "127.0.0.1:0",
		OAuthBindAddr:            "127.0.0.1:0",
		Use24HourClock:           true,
		RemindersEnabled:         true,
		ReminderPersist:          true,
		AllDayReminderTime:       "09:00",
		DefaultReminderMinutes:   10,
		SnoozeMinutes:            5,
		SyncIntervalMinutes:      60,
		AllDayReminderDaysBefore: 0,
		AllDayReminders:          false,
		NotificationSounds:       false,
	}
}

// Path returns the XDG configuration file path without creating it.
func Path() string {
	return filepath.Join(dcalpaths.XDGConfigHome(), "dcal", fileName)
}

// Load reads config.json when present, overlays DCAL_* environment variables,
// and resolves storage paths. A missing file is the normal fresh-run case.
func Load() (*Config, error) {
	cfg := Defaults()
	data, err := os.ReadFile(Path())
	switch {
	case err == nil:
		if err := json.Unmarshal(data, &cfg); err != nil {
			return nil, fmt.Errorf("parse %s: %w", Path(), err)
		}
	case errors.Is(err, os.ErrNotExist):
	case err != nil:
		return nil, fmt.Errorf("read %s: %w", Path(), err)
	}

	if err := env.Parse(&cfg); err != nil {
		return nil, fmt.Errorf("parse dcal environment: %w", err)
	}
	if err := cfg.normalize(); err != nil {
		return nil, err
	}
	return &cfg, nil
}

// Current is the no-error loader used by long-running reminder code. The
// daemon validates the same file during startup, so falling back here only
// protects callers that use reminder formatting independently.
func Current() Config {
	cfg, err := Load()
	if err != nil {
		return Defaults()
	}
	return *cfg
}

func (c *Config) normalize() error {
	defaults := Defaults()
	c.DefaultCalendar = strings.TrimSpace(c.DefaultCalendar)
	if strings.TrimSpace(c.ICSDir) == "" {
		c.ICSDir = defaults.ICSDir
	}
	if strings.TrimSpace(c.DatabasePath) == "" {
		c.DatabasePath = defaults.DatabasePath
	}
	if strings.TrimSpace(c.APIAddr) == "" {
		c.APIAddr = defaults.APIAddr
	}
	if strings.TrimSpace(c.OAuthBindAddr) == "" {
		c.OAuthBindAddr = defaults.OAuthBindAddr
	}
	if c.SnoozeMinutes <= 0 {
		c.SnoozeMinutes = defaults.SnoozeMinutes
	}
	if c.SyncIntervalMinutes <= 0 {
		c.SyncIntervalMinutes = defaults.SyncIntervalMinutes
	}
	if _, err := time.Parse("15:04", c.AllDayReminderTime); err != nil {
		c.AllDayReminderTime = defaults.AllDayReminderTime
	}

	for label, target := range map[string]*string{
		"ics_dir":       &c.ICSDir,
		"database_path": &c.DatabasePath,
	} {
		expanded, err := dcalpaths.ExpandPath(*target)
		if err != nil {
			return fmt.Errorf("resolve %s: %w", label, err)
		}
		if !filepath.IsAbs(expanded) {
			return fmt.Errorf("%s must be an absolute path", label)
		}
		*target = expanded
	}
	return nil
}

// Clock formats t according to the configured 12/24-hour preference.
func (c Config) Clock(t time.Time) string {
	if c.Use24HourClock {
		return t.Format("15:04")
	}
	return t.Format("3:04 PM")
}

// AllDayClock resolves the configured all-day reminder time.
func (c Config) AllDayClock() (hour, minute int) {
	t, err := time.Parse("15:04", c.AllDayReminderTime)
	if err != nil {
		t, _ = time.Parse("15:04", Defaults().AllDayReminderTime)
	}
	return t.Hour(), t.Minute()
}

// IsEmpty reports whether no per-calendar reminder field is overridden.
func (o *ReminderOverride) IsEmpty() bool {
	if o == nil {
		return true
	}
	return o.Enabled == nil &&
		o.Persist == nil &&
		o.AllDay == nil &&
		o.AllDayTime == nil &&
		o.AllDayDaysBefore == nil &&
		o.DefaultReminderMinutes == nil &&
		o.SnoozeMinutes == nil
}

// Resolve applies this override to base. The global enabled switch remains a
// master switch: a calendar may mute reminders but cannot force them on.
func (o *ReminderOverride) Resolve(base Config) Config {
	if o == nil {
		return base
	}
	if o.Enabled != nil && base.RemindersEnabled {
		base.RemindersEnabled = *o.Enabled
	}
	if o.Persist != nil {
		base.ReminderPersist = *o.Persist
	}
	if o.AllDay != nil {
		base.AllDayReminders = *o.AllDay
	}
	if o.AllDayTime != nil {
		base.AllDayReminderTime = *o.AllDayTime
	}
	if o.AllDayDaysBefore != nil {
		base.AllDayReminderDaysBefore = *o.AllDayDaysBefore
	}
	if o.DefaultReminderMinutes != nil {
		base.DefaultReminderMinutes = *o.DefaultReminderMinutes
	}
	if o.SnoozeMinutes != nil && *o.SnoozeMinutes > 0 {
		base.SnoozeMinutes = *o.SnoozeMinutes
	}
	return base
}
