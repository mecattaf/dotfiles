package main

import (
	"encoding/json"
	"fmt"
	"os"
	"slices"
	"time"

	"github.com/mecattaf/dcal/internal/calendar"
	"github.com/mecattaf/dcal/internal/ipc"
)

type daemonClient struct {
	client *ipc.Client
	nextID int
}

func dialDaemon() (*daemonClient, error) {
	socketPath := os.Getenv("DCAL_SOCKET")
	var err error
	if socketPath == "" {
		socketPath, err = ipc.FindRunningSocket()
		if err != nil {
			return nil, fmt.Errorf("dcal daemon is not running: %w", err)
		}
	}

	client, err := ipc.Dial(socketPath)
	if err != nil {
		return nil, fmt.Errorf("connect to dcal daemon: %w", err)
	}
	return &daemonClient{client: client, nextID: 1}, nil
}

func (c *daemonClient) Close() error { return c.client.Close() }

func (c *daemonClient) call(method string, params map[string]any, out any) error {
	resp, err := c.client.Call(ipc.Request{ID: c.nextID, Method: method, Params: params})
	c.nextID++
	if err != nil {
		return fmt.Errorf("%s: %w", method, err)
	}
	if resp.Error != "" {
		return remoteError(resp.Error)
	}
	if out == nil {
		return nil
	}
	data, err := json.Marshal(resp.Result)
	if err != nil {
		return fmt.Errorf("encode %s response: %w", method, err)
	}
	if err := json.Unmarshal(data, out); err != nil {
		return fmt.Errorf("decode %s response: %w", method, err)
	}
	return nil
}

type accountRecord struct {
	ID          string         `json:"id"`
	Kind        string         `json:"kind"`
	DisplayName string         `json:"displayName"`
	Settings    map[string]any `json:"settings,omitempty"`
	NeedsReauth bool           `json:"needsReauth"`
	Authorized  bool           `json:"authorized"`
	UpdatedAt   time.Time      `json:"updatedAt"`
}

type calendarRecord struct {
	ID                  string    `json:"id"`
	AccountID           string    `json:"accountId"`
	AccountKind         string    `json:"accountKind"`
	AccountName         string    `json:"accountName"`
	RemoteID            string    `json:"remoteId"`
	Name                string    `json:"name"`
	ReadOnly            bool      `json:"readOnly"`
	Hidden              bool      `json:"hidden"`
	SyncDisabled        bool      `json:"syncDisabled"`
	SupportedComponents []string  `json:"supportedComponents,omitempty"`
	UpdatedAt           time.Time `json:"updatedAt"`
}

func (c calendarRecord) holdsEvents() bool {
	return len(c.SupportedComponents) == 0 || slices.Contains(c.SupportedComponents, calendar.ComponentVEvent)
}

type eventRecord struct {
	ID           string           `json:"id"`
	UID          string           `json:"uid"`
	CalendarID   string           `json:"calendarId"`
	CalendarName string           `json:"calendarName,omitempty"`
	Summary      string           `json:"summary"`
	Description  string           `json:"description,omitempty"`
	Location     string           `json:"location,omitempty"`
	URL          string           `json:"url,omitempty"`
	MeetingURL   string           `json:"meetingUrl,omitempty"`
	Start        time.Time        `json:"start"`
	End          time.Time        `json:"end"`
	AllDay       bool             `json:"allDay"`
	Status       string           `json:"status"`
	RecurringID  string           `json:"recurringId,omitempty"`
	Recurrence   map[string]any   `json:"recurrence,omitempty"`
	Attendees    []map[string]any `json:"attendees,omitempty"`
	Organizer    map[string]any   `json:"organizer,omitempty"`
	Reminders    []map[string]any `json:"reminders,omitempty"`
}

type eventListResponse struct {
	Events []eventRecord `json:"events"`
	Total  int           `json:"total"`
}
