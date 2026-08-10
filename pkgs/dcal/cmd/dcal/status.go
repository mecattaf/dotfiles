package main

import (
	"context"
	"fmt"
	"os"
	"sort"
	"text/tabwriter"
	"time"

	"github.com/spf13/cobra"

	"github.com/mecattaf/dcal/internal/accounts"
	"github.com/mecattaf/dcal/repo"
)

type statusAccount struct {
	ID          string `json:"id"`
	Kind        string `json:"kind"`
	DisplayName string `json:"displayName"`
	Authorized  bool   `json:"authorized"`
	NeedsReauth bool   `json:"needsReauth"`
}

type statusCalendar struct {
	ID         string    `json:"id"`
	AccountID  string    `json:"accountId"`
	Name       string    `json:"name"`
	EventCount int       `json:"eventCount"`
	LastSync   time.Time `json:"lastSync"`
}

type statusResult struct {
	Accounts     []statusAccount  `json:"accounts"`
	Calendars    []statusCalendar `json:"calendars"`
	Events       int              `json:"eventCount"`
	LastSync     *time.Time       `json:"lastSync"`
	PendingCalls []pendingCall    `json:"pendingCalls,omitempty"`
}

type pendingCall struct {
	EventRef string    `json:"eventRef"`
	CRMRef   string    `json:"crmRef,omitempty"`
	Summary  string    `json:"summary"`
	End      time.Time `json:"end"`
	Date     string    `json:"date"`
}

var statusCmd = &cobra.Command{
	Use:   "status",
	Short: "Show calendar health and overdue call work",
	Args:  cobra.NoArgs,
	RunE: func(_ *cobra.Command, _ []string) error {
		result, err := loadStatus(context.Background())
		if err != nil {
			return err
		}
		if jsonOutput {
			return printJSON(result)
		}
		return printStatus(result)
	},
}

func loadStatus(ctx context.Context) (statusResult, error) {
	st, closer, err := openStores(ctx)
	if err != nil {
		return statusResult{}, err
	}
	defer closer()

	storedAccounts, err := st.repo.ListAccounts(ctx)
	if err != nil {
		return statusResult{}, err
	}
	storedCalendars, err := st.repo.ListCalendars(ctx)
	if err != nil {
		return statusResult{}, err
	}

	result := statusResult{
		Accounts:     make([]statusAccount, 0, len(storedAccounts)),
		Calendars:    make([]statusCalendar, 0, len(storedCalendars)),
		PendingCalls: []pendingCall{},
	}
	now := time.Now()
	loggedCalls := make(map[string]bool)
	checkedCalls := make(map[string]bool)
	for _, account := range storedAccounts {
		result.Accounts = append(result.Accounts, statusAccount{
			ID:          account.ID,
			Kind:        string(account.Kind),
			DisplayName: account.DisplayName,
			Authorized:  accounts.Authorized(ctx, st.secrets, account),
			NeedsReauth: account.NeedsReauth,
		})
	}
	for _, cal := range storedCalendars {
		events, count, err := st.repo.ListEvents(ctx, repo.ListEventsParams{
			Filter: repo.EventFilter{CalendarIDs: []string{cal.ID}},
		})
		if err != nil {
			return statusResult{}, err
		}
		name := cal.Name
		if cal.NameOverride != "" {
			name = cal.NameOverride
		}
		accountID := ""
		if cal.Edges.Account != nil {
			accountID = cal.Edges.Account.ID
		}
		result.Calendars = append(result.Calendars, statusCalendar{
			ID:         cal.ID,
			AccountID:  accountID,
			Name:       name,
			EventCount: count,
			LastSync:   cal.UpdatedAt,
		})
		result.Events += count
		if result.LastSync == nil || cal.UpdatedAt.After(*result.LastSync) {
			lastSync := cal.UpdatedAt
			result.LastSync = &lastSync
		}

		for _, event := range events {
			if event.CrmKind != "call" || !event.End.Before(now) || event.Status == "cancelled" {
				continue
			}
			date := callEventDate(event.Start)
			logged := false
			if event.CrmRef != "" {
				key := event.CrmRef + "\x00" + date
				if checkedCalls[key] {
					logged = loggedCalls[key]
				} else {
					logged, err = crmCallLogged(ctx, event.CrmRef, date)
					if err != nil {
						return statusResult{}, fmt.Errorf("check logged call for event %s: %w", event.ID, err)
					}
					checkedCalls[key] = true
					loggedCalls[key] = logged
				}
			}
			if !logged {
				result.PendingCalls = append(result.PendingCalls, pendingCall{
					EventRef: event.ID,
					CRMRef:   event.CrmRef,
					Summary:  event.Summary,
					End:      event.End,
					Date:     date,
				})
			}
		}
	}
	sort.Slice(result.PendingCalls, func(i, j int) bool {
		return result.PendingCalls[i].End.Before(result.PendingCalls[j].End)
	})
	return result, nil
}

func printStatus(result statusResult) error {
	w := tabwriter.NewWriter(os.Stdout, 0, 4, 2, ' ', 0)
	fmt.Fprintln(w, "ACCOUNTS")
	fmt.Fprintln(w, "ID\tKIND\tNAME\tSTATUS")
	for _, account := range result.Accounts {
		state := "ok"
		switch {
		case account.NeedsReauth:
			state = "needs reauth"
		case !account.Authorized:
			state = "needs auth"
		}
		fmt.Fprintf(w, "%s\t%s\t%s\t%s\n", account.ID, account.Kind, account.DisplayName, state)
	}
	fmt.Fprintln(w)
	fmt.Fprintln(w, "CALENDARS")
	fmt.Fprintln(w, "ID\tACCOUNT\tNAME\tEVENTS\tLAST SYNC")
	for _, cal := range result.Calendars {
		fmt.Fprintf(w, "%s\t%s\t%s\t%d\t%s\n", cal.ID, cal.AccountID, cal.Name, cal.EventCount, cal.LastSync.Format(time.RFC3339))
	}
	fmt.Fprintln(w)
	fmt.Fprintf(w, "Accounts:\t%d\n", len(result.Accounts))
	fmt.Fprintf(w, "Calendars:\t%d\n", len(result.Calendars))
	fmt.Fprintf(w, "Events:\t%d\n", result.Events)
	lastSync := "never"
	if result.LastSync != nil {
		lastSync = result.LastSync.Format(time.RFC3339)
	}
	fmt.Fprintf(w, "Last sync:\t%s\n", lastSync)
	if len(result.PendingCalls) > 0 {
		fmt.Fprintln(w)
		fmt.Fprintln(w, "PENDING CALLS")
		fmt.Fprintln(w, "EVENT REF\tENDED\tCRM REF\tTITLE\tNEXT")
		for _, call := range result.PendingCalls {
			fmt.Fprintf(w, "%s\t%s\t%s\t%s\tdcal done %s\n", call.EventRef, call.End.Format(time.RFC3339), call.CRMRef, call.Summary, call.EventRef)
		}
	}
	return w.Flush()
}
