package ipc

import (
	"context"

	dcalipc "github.com/mecattaf/dcal/internal/support/ipc"
)

type Server = dcalipc.Server

func NewServer(deps Deps) *Server {
	if deps.Bus == nil {
		deps.Bus = NewEventBus()
	}

	cfg := dcalipc.Config{
		AppName:                "dcal",
		APIVersion:             APIVersion,
		Capabilities:           []string{"accounts", "calendars", "events", "reminders", "subscribe"},
		DefaultSubscribeTopics: []string{"accounts", "calendars", "events", "tasks", "sync"},
		Bus:                    deps.Bus,
	}

	return dcalipc.NewServer(cfg, func(ctx context.Context, w *ConnWriter, req Request, _ *Subscriber) {
		Route(ctx, w, req, deps)
	})
}
