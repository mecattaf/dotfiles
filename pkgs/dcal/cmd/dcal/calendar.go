package main

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/spf13/cobra"

	"github.com/mecattaf/dcal/config"
)

const fallbackCalendarName = "Personal"

var calendarCmd = &cobra.Command{
	Use:   "calendar",
	Short: "Manage calendars",
	Args:  cobra.NoArgs,
}

var calendarAddCmd = &cobra.Command{
	Use:   "add <name>",
	Short: "Create a local calendar",
	Args:  cobra.ExactArgs(1),
	RunE: func(_ *cobra.Command, args []string) error {
		name := strings.TrimSpace(args[0])
		if name == "" {
			return errors.New("calendar name is required")
		}
		cfg, err := config.Load()
		if err != nil {
			return err
		}
		client, err := dialDaemon()
		if err != nil {
			return err
		}
		defer client.Close()

		account, err := ensureLocalAccount(client, cfg, "", true)
		if err != nil {
			return err
		}
		var created struct {
			AccountID string `json:"accountId"`
			Name      string `json:"name"`
			RemoteID  string `json:"remoteId"`
		}
		if err := client.call("calendars.create", map[string]any{
			"accountId": account.ID,
			"name":      name,
		}, &created); err != nil {
			return err
		}
		if jsonOutput {
			return printJSON(created)
		}
		fmt.Fprintln(os.Stdout, created.Name)
		return nil
	},
}

func init() {
	calendarCmd.AddCommand(calendarAddCmd)
}

func listAccounts(client *daemonClient) ([]accountRecord, error) {
	var accounts []accountRecord
	if err := client.call("accounts.list", nil, &accounts); err != nil {
		return nil, err
	}
	return accounts, nil
}

func listCalendars(client *daemonClient) ([]calendarRecord, error) {
	var calendars []calendarRecord
	if err := client.call("calendars.list", nil, &calendars); err != nil {
		return nil, err
	}
	return calendars, nil
}

func ensureLocalAccount(client *daemonClient, cfg *config.Config, seedName string, skipSeed bool) (accountRecord, error) {
	accounts, err := listAccounts(client)
	if err != nil {
		return accountRecord{}, err
	}
	for _, account := range accounts {
		root, _ := account.Settings["root"].(string)
		if account.Kind == "local" && filepath.Clean(root) == filepath.Clean(cfg.ICSDir) {
			return account, nil
		}
	}

	var created struct {
		AccountID   string `json:"accountId"`
		DisplayName string `json:"displayName"`
	}
	if err := client.call("accounts.local.add", map[string]any{
		"root":            cfg.ICSDir,
		"displayName":     "Local",
		"defaultCalendar": seedName,
		"skipSeed":        skipSeed,
	}, &created); err != nil {
		return accountRecord{}, err
	}

	accounts, err = listAccounts(client)
	if err != nil {
		return accountRecord{}, err
	}
	for _, account := range accounts {
		if account.ID == created.AccountID {
			root, _ := account.Settings["root"].(string)
			if filepath.Clean(root) != filepath.Clean(cfg.ICSDir) {
				return accountRecord{}, withCode(exitConflict, "local account %q points to %s, not configured ics_dir %s", account.ID, root, cfg.ICSDir)
			}
			return account, nil
		}
	}
	return accountRecord{}, withCode(exitNotFound, "new local account %q was not found", created.AccountID)
}

func resolveCalendar(calendars []calendarRecord, ref string, writable bool) (calendarRecord, error) {
	ref = strings.TrimSpace(ref)
	for _, item := range calendars {
		if item.ID == ref {
			if item.SyncDisabled {
				return calendarRecord{}, withCode(exitConflict, "calendar %q is disabled", item.Name)
			}
			if writable && item.ReadOnly {
				return calendarRecord{}, withCode(exitConflict, "calendar %q is read-only", item.Name)
			}
			if !item.holdsEvents() {
				return calendarRecord{}, withCode(exitConflict, "calendar %q does not hold events", item.Name)
			}
			return item, nil
		}
	}

	var matches []calendarRecord
	for _, item := range calendars {
		if strings.EqualFold(item.Name, ref) {
			matches = append(matches, item)
		}
	}
	switch len(matches) {
	case 0:
		return calendarRecord{}, withCode(exitNotFound, "calendar %q not found", ref)
	case 1:
		if matches[0].SyncDisabled {
			return calendarRecord{}, withCode(exitConflict, "calendar %q is disabled", matches[0].Name)
		}
		if writable && matches[0].ReadOnly {
			return calendarRecord{}, withCode(exitConflict, "calendar %q is read-only", matches[0].Name)
		}
		if !matches[0].holdsEvents() {
			return calendarRecord{}, withCode(exitConflict, "calendar %q does not hold events", matches[0].Name)
		}
		return matches[0], nil
	default:
		ids := make([]string, 0, len(matches))
		for _, item := range matches {
			ids = append(ids, item.ID)
		}
		sort.Strings(ids)
		return calendarRecord{}, withCode(exitAmbiguous, "calendar %q is ambiguous; use one of these ids: %s", ref, strings.Join(ids, ", "))
	}
}

func calendarForWrite(client *daemonClient, cfg *config.Config, requested string) (calendarRecord, error) {
	calendars, err := listCalendars(client)
	if err != nil {
		return calendarRecord{}, err
	}

	if requested = strings.TrimSpace(requested); requested != "" {
		return resolveCalendar(calendars, requested, true)
	}
	if cfg.DefaultCalendar != "" {
		return resolveCalendar(calendars, cfg.DefaultCalendar, true)
	}

	// The primary Google calendar normally has the account email as its remote
	// id. Prefer it, then any other writable Google event calendar.
	for _, item := range calendars {
		if usableGoogleCalendar(item) && item.RemoteID == item.AccountID {
			return item, nil
		}
	}
	for _, item := range calendars {
		if usableGoogleCalendar(item) {
			return item, nil
		}
	}
	for _, item := range calendars {
		if item.AccountKind == "local" && strings.EqualFold(item.Name, fallbackCalendarName) && usableCalendar(item) {
			return item, nil
		}
	}
	for _, item := range calendars {
		if item.AccountKind == "local" && usableCalendar(item) {
			return item, nil
		}
	}

	account, err := ensureLocalAccount(client, cfg, fallbackCalendarName, false)
	if err != nil {
		return calendarRecord{}, err
	}
	calendars, err = listCalendars(client)
	if err != nil {
		return calendarRecord{}, err
	}
	for _, item := range calendars {
		if item.AccountID == account.ID && strings.EqualFold(item.Name, fallbackCalendarName) && usableCalendar(item) {
			return item, nil
		}
	}

	// An existing but empty local account was not seeded by accounts.local.add.
	var created struct {
		Name string `json:"name"`
	}
	if err := client.call("calendars.create", map[string]any{
		"accountId": account.ID,
		"name":      fallbackCalendarName,
	}, &created); err != nil {
		return calendarRecord{}, err
	}
	calendars, err = listCalendars(client)
	if err != nil {
		return calendarRecord{}, err
	}
	return resolveCalendar(calendars, created.Name, true)
}

func usableGoogleCalendar(item calendarRecord) bool {
	return item.AccountKind == "google" && usableCalendar(item)
}

func usableCalendar(item calendarRecord) bool {
	return !item.ReadOnly && !item.SyncDisabled && item.holdsEvents()
}
