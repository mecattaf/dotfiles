package main

import (
	"errors"
	"fmt"
	"os"
	"sort"
	"strings"
	"text/tabwriter"
	"time"

	"github.com/spf13/cobra"

	"github.com/mecattaf/dcal/config"
)

type addOptions struct {
	calendar    string
	crm         string
	kind        string
	start       string
	end         string
	description string
	location    string
	status      string
	allDay      bool
}

var addFlags addOptions

var addCmd = &cobra.Command{
	Use:   "add [title]",
	Short: "Create an event",
	Args:  cobra.MaximumNArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		start, err := parseRFC3339("start", addFlags.start)
		if err != nil {
			return err
		}
		end, err := parseRFC3339("end", addFlags.end)
		if err != nil {
			return err
		}
		if !end.After(start) {
			return errors.New("end must be after start")
		}
		if addFlags.status != "" {
			if err := validateStatus(addFlags.status); err != nil {
				return err
			}
		}
		title := ""
		if len(args) == 1 {
			title = strings.TrimSpace(args[0])
		}
		crmRef := strings.TrimSpace(addFlags.crm)
		kind := strings.TrimSpace(addFlags.kind)
		if cmd.Flags().Changed("crm") && crmRef == "" {
			return errors.New("--crm must not be empty")
		}
		if cmd.Flags().Changed("kind") && kind == "" {
			return errors.New("--kind must be call")
		}
		if kind != "" && kind != "call" {
			return fmt.Errorf("kind must be call")
		}
		if crmRef != "" {
			contact, err := resolveCRMContact(cmd.Context(), crmRef)
			if err != nil {
				return err
			}
			crmRef = contact.Ref
			if kind == "" {
				kind = "call"
			}
			if title == "" {
				title = "call with " + contact.Name
			}
		}
		if title == "" {
			return errors.New("title is required unless --crm supplies a contact")
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

		cal, err := calendarForWrite(client, cfg, addFlags.calendar)
		if err != nil {
			return err
		}
		params := map[string]any{
			"calendarId": cal.ID,
			"summary":    title,
			"start":      start.Format(time.RFC3339),
			"end":        end.Format(time.RFC3339),
		}
		if crmRef != "" {
			params["crmRef"] = crmRef
		}
		if kind != "" {
			params["crmKind"] = kind
		}
		setOptionalEventParams(params, addFlags.description, addFlags.location, addFlags.status, addFlags.allDay)

		var event eventRecord
		if err := client.call("events.create", params, &event); err != nil {
			return err
		}
		event.CalendarName = cal.Name
		if jsonOutput {
			return printJSON(event)
		}
		fmt.Fprintln(os.Stdout, event.ID)
		return nil
	},
}

type listOptions struct {
	calendar string
}

var listFlags listOptions

var listCmd = &cobra.Command{
	Use:   "ls",
	Short: "List events in a calendar",
	Args:  cobra.NoArgs,
	RunE: func(_ *cobra.Command, _ []string) error {
		client, err := dialDaemon()
		if err != nil {
			return err
		}
		defer client.Close()
		calendars, err := listCalendars(client)
		if err != nil {
			return err
		}
		cal, err := resolveCalendar(calendars, listFlags.calendar, false)
		if err != nil {
			return err
		}
		result, err := listEvents(client, map[string]any{"calendarId": cal.ID})
		if err != nil {
			return err
		}
		for i := range result.Events {
			result.Events[i].CalendarName = cal.Name
		}
		if jsonOutput {
			return printJSON(result.Events)
		}
		return printEventTable(result.Events, false)
	},
}

type agendaOptions struct {
	from string
	to   string
}

var agendaFlags agendaOptions

var agendaCmd = &cobra.Command{
	Use:   "agenda",
	Short: "Show a chronological agenda across calendars",
	Args:  cobra.NoArgs,
	RunE: func(_ *cobra.Command, _ []string) error {
		from, err := parseAgendaBound("from", agendaFlags.from, false)
		if err != nil {
			return err
		}
		to, err := parseAgendaBound("to", agendaFlags.to, true)
		if err != nil {
			return err
		}
		if to.Before(from) {
			return errors.New("to must not be before from")
		}

		client, err := dialDaemon()
		if err != nil {
			return err
		}
		defer client.Close()
		calendars, err := listCalendars(client)
		if err != nil {
			return err
		}
		result, err := listEvents(client, map[string]any{
			"from": from.Format(time.RFC3339Nano),
			"to":   to.Format(time.RFC3339Nano),
		})
		if err != nil {
			return err
		}
		calendarNames := make(map[string]string, len(calendars))
		for _, cal := range calendars {
			calendarNames[cal.ID] = cal.Name
		}
		for i := range result.Events {
			result.Events[i].CalendarName = calendarNames[result.Events[i].CalendarID]
		}
		sort.SliceStable(result.Events, func(i, j int) bool {
			return result.Events[i].Start.Before(result.Events[j].Start)
		})
		if jsonOutput {
			return printJSON(result.Events)
		}
		return printEventTable(result.Events, true)
	},
}

var showCmd = &cobra.Command{
	Use:   "show <event-ref>",
	Short: "Show one event",
	Args:  cobra.ExactArgs(1),
	RunE: func(_ *cobra.Command, args []string) error {
		client, err := dialDaemon()
		if err != nil {
			return err
		}
		defer client.Close()
		event, err := getEvent(client, args[0])
		if err != nil {
			return err
		}
		if jsonOutput {
			return printJSON(event)
		}
		return printEvent(event)
	},
}

type editOptions struct {
	title       string
	start       string
	end         string
	description string
	location    string
	status      string
	allDay      bool
}

var editFlags editOptions

var editCmd = &cobra.Command{
	Use:   "edit <event-ref>",
	Short: "Edit an event",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		changed := []string{"title", "start", "end", "description", "location", "status", "all-day"}
		anyChanged := false
		for _, name := range changed {
			anyChanged = anyChanged || cmd.Flags().Changed(name)
		}
		if !anyChanged {
			return errors.New("edit requires at least one changed field")
		}

		client, err := dialDaemon()
		if err != nil {
			return err
		}
		defer client.Close()
		current, err := getEvent(client, args[0])
		if err != nil {
			return err
		}

		params := map[string]any{"id": current.ID}
		start, end := current.Start, current.End
		if cmd.Flags().Changed("title") {
			if strings.TrimSpace(editFlags.title) == "" {
				return errors.New("title cannot be empty")
			}
			params["summary"] = strings.TrimSpace(editFlags.title)
		}
		if cmd.Flags().Changed("start") {
			start, err = parseRFC3339("start", editFlags.start)
			if err != nil {
				return err
			}
			params["start"] = start.Format(time.RFC3339)
		}
		if cmd.Flags().Changed("end") {
			end, err = parseRFC3339("end", editFlags.end)
			if err != nil {
				return err
			}
			params["end"] = end.Format(time.RFC3339)
		}
		if !end.After(start) {
			return errors.New("end must be after start")
		}
		if cmd.Flags().Changed("description") {
			params["description"] = editFlags.description
		}
		if cmd.Flags().Changed("location") {
			params["location"] = editFlags.location
		}
		if cmd.Flags().Changed("status") {
			if err := validateStatus(editFlags.status); err != nil {
				return err
			}
			params["status"] = editFlags.status
		}
		if cmd.Flags().Changed("all-day") {
			params["allDay"] = editFlags.allDay
		}

		var updated eventRecord
		if err := client.call("events.update", params, &updated); err != nil {
			return err
		}
		updated.CalendarName = current.CalendarName
		if jsonOutput {
			return printJSON(updated)
		}
		fmt.Fprintln(os.Stdout, updated.ID)
		return nil
	},
}

var removeCmd = &cobra.Command{
	Use:     "rm <event-ref>",
	Aliases: []string{"remove"},
	Short:   "Remove an event",
	Args:    cobra.ExactArgs(1),
	RunE: func(_ *cobra.Command, args []string) error {
		client, err := dialDaemon()
		if err != nil {
			return err
		}
		defer client.Close()
		event, err := getEvent(client, args[0])
		if err != nil {
			return err
		}
		var result map[string]any
		if err := client.call("events.delete", map[string]any{"id": event.ID}, &result); err != nil {
			return err
		}
		if jsonOutput {
			result["ref"] = event.ID
			return printJSON(result)
		}
		fmt.Fprintln(os.Stdout, event.ID)
		return nil
	},
}

func init() {
	addCmd.Flags().StringVar(&addFlags.calendar, "calendar", "", "Calendar name or id (defaults from config)")
	addCmd.Flags().StringVar(&addFlags.crm, "crm", "", "CRM contact ref")
	addCmd.Flags().StringVar(&addFlags.kind, "kind", "", "Event kind (call)")
	addCmd.Flags().StringVar(&addFlags.start, "start", "", "Start time (RFC3339)")
	addCmd.Flags().StringVar(&addFlags.end, "end", "", "End time (RFC3339)")
	addCmd.Flags().StringVar(&addFlags.description, "description", "", "Description")
	addCmd.Flags().StringVar(&addFlags.location, "location", "", "Location")
	addCmd.Flags().StringVar(&addFlags.status, "status", "", "confirmed, tentative, or cancelled")
	addCmd.Flags().BoolVar(&addFlags.allDay, "all-day", false, "Create an all-day event")
	_ = addCmd.MarkFlagRequired("start")
	_ = addCmd.MarkFlagRequired("end")

	listCmd.Flags().StringVar(&listFlags.calendar, "calendar", "", "Calendar name or id")
	_ = listCmd.MarkFlagRequired("calendar")

	agendaCmd.Flags().StringVar(&agendaFlags.from, "from", "", "Start date (YYYY-MM-DD or RFC3339)")
	agendaCmd.Flags().StringVar(&agendaFlags.to, "to", "", "End date, inclusive (YYYY-MM-DD or RFC3339)")
	_ = agendaCmd.MarkFlagRequired("from")
	_ = agendaCmd.MarkFlagRequired("to")

	editCmd.Flags().StringVar(&editFlags.title, "title", "", "New title")
	editCmd.Flags().StringVar(&editFlags.start, "start", "", "New start time (RFC3339)")
	editCmd.Flags().StringVar(&editFlags.end, "end", "", "New end time (RFC3339)")
	editCmd.Flags().StringVar(&editFlags.description, "description", "", "New description")
	editCmd.Flags().StringVar(&editFlags.location, "location", "", "New location")
	editCmd.Flags().StringVar(&editFlags.status, "status", "", "confirmed, tentative, or cancelled")
	editCmd.Flags().BoolVar(&editFlags.allDay, "all-day", false, "Set all-day status")
}

func parseRFC3339(name, value string) (time.Time, error) {
	t, err := time.Parse(time.RFC3339, strings.TrimSpace(value))
	if err != nil {
		return time.Time{}, fmt.Errorf("%s must be RFC3339: %w", name, err)
	}
	return t, nil
}

func parseAgendaBound(name, value string, inclusiveEnd bool) (time.Time, error) {
	value = strings.TrimSpace(value)
	if date, err := time.ParseInLocation(time.DateOnly, value, time.Local); err == nil {
		if inclusiveEnd {
			return date.AddDate(0, 0, 1).Add(-time.Nanosecond), nil
		}
		return date, nil
	}
	return parseRFC3339(name, value)
}

func validateStatus(status string) error {
	switch status {
	case "confirmed", "tentative", "cancelled":
		return nil
	default:
		return fmt.Errorf("status must be confirmed, tentative, or cancelled")
	}
}

func setOptionalEventParams(params map[string]any, description, location, status string, allDay bool) {
	if description != "" {
		params["description"] = description
	}
	if location != "" {
		params["location"] = location
	}
	if status != "" {
		params["status"] = status
	}
	if allDay {
		params["allDay"] = true
	}
}

func listEvents(client *daemonClient, params map[string]any) (eventListResponse, error) {
	var result eventListResponse
	if err := client.call("events.list", params, &result); err != nil {
		return eventListResponse{}, err
	}
	if result.Events == nil {
		result.Events = []eventRecord{}
	}
	return result, nil
}

func getEvent(client *daemonClient, ref string) (eventRecord, error) {
	ref = strings.TrimSpace(ref)
	if ref == "" {
		return eventRecord{}, errors.New("event ref is required")
	}
	var event eventRecord
	if err := client.call("events.get", map[string]any{"id": ref}, &event); err != nil {
		return eventRecord{}, err
	}
	calendars, err := listCalendars(client)
	if err != nil {
		return eventRecord{}, err
	}
	for _, cal := range calendars {
		if cal.ID == event.CalendarID {
			event.CalendarName = cal.Name
			break
		}
	}
	return event, nil
}

func printEventTable(events []eventRecord, includeCalendar bool) error {
	w := tabwriter.NewWriter(os.Stdout, 0, 4, 2, ' ', 0)
	if includeCalendar {
		fmt.Fprintln(w, "REF\tSTART\tEND\tCALENDAR\tTITLE")
	} else {
		fmt.Fprintln(w, "REF\tSTART\tEND\tTITLE")
	}
	for _, event := range events {
		if includeCalendar {
			fmt.Fprintf(w, "%s\t%s\t%s\t%s\t%s\n", event.ID, event.Start.Format(time.RFC3339), event.End.Format(time.RFC3339), event.CalendarName, event.Summary)
		} else {
			fmt.Fprintf(w, "%s\t%s\t%s\t%s\n", event.ID, event.Start.Format(time.RFC3339), event.End.Format(time.RFC3339), event.Summary)
		}
	}
	return w.Flush()
}

func printEvent(event eventRecord) error {
	w := tabwriter.NewWriter(os.Stdout, 0, 4, 2, ' ', 0)
	fmt.Fprintf(w, "Ref:\t%s\n", event.ID)
	fmt.Fprintf(w, "UID:\t%s\n", event.UID)
	fmt.Fprintf(w, "Title:\t%s\n", event.Summary)
	fmt.Fprintf(w, "Calendar:\t%s\n", event.CalendarName)
	fmt.Fprintf(w, "Start:\t%s\n", event.Start.Format(time.RFC3339))
	fmt.Fprintf(w, "End:\t%s\n", event.End.Format(time.RFC3339))
	if event.Location != "" {
		fmt.Fprintf(w, "Location:\t%s\n", event.Location)
	}
	if event.Description != "" {
		fmt.Fprintf(w, "Description:\t%s\n", event.Description)
	}
	if event.Status != "" {
		fmt.Fprintf(w, "Status:\t%s\n", event.Status)
	}
	if event.CRMRef != "" {
		fmt.Fprintf(w, "CRM Ref:\t%s\n", event.CRMRef)
	}
	if event.CRMKind != "" {
		fmt.Fprintf(w, "CRM Kind:\t%s\n", event.CRMKind)
	}
	return w.Flush()
}
