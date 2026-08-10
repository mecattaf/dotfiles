package ipc

import (
	"context"

	"github.com/mecattaf/dcal/ent"
	"github.com/mecattaf/dcal/internal/calendar"
	"github.com/mecattaf/dcal/internal/oauth"
	"github.com/mecattaf/dcal/internal/reminders"
	"github.com/mecattaf/dcal/repo"
)

type SyncTrigger interface {
	SyncAccount(ctx context.Context, acc *ent.Account) error
	SyncAll(ctx context.Context) error
}

type RemindersEngine interface {
	Upcoming(ctx context.Context, limit int) ([]reminders.Upcoming, error)
	SendTest() error
}

type Deps struct {
	Repo      *repo.Repo
	Registry  *calendar.Registry
	Secrets   calendar.SecretStore
	Broker    *oauth.CallbackBroker
	Flows     *oauth.FlowRegistry
	HTTPAddr  string
	Sync      SyncTrigger
	Reminders RemindersEngine
	Bus       *EventBus
	Version   string
}
