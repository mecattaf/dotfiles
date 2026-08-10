package ipc

import (
	"time"

	dcalipc "github.com/mecattaf/dcal/internal/support/ipc"
	"github.com/mecattaf/dcal/internal/support/ipc/params"
)

const (
	APIVersion                 = 1
	socketDiscoveryGracePeriod = 3 * time.Second
)

type (
	Request         = dcalipc.Request
	Response[T any] = dcalipc.Response[T]
	ConnWriter      = dcalipc.ConnWriter
	Subscriber      = dcalipc.Subscriber
	EventBus        = dcalipc.EventBus
	Client          = dcalipc.Client
)

var (
	NewEventBus   = dcalipc.NewEventBus
	NewConnWriter = dcalipc.NewConnWriter
	Dial          = dcalipc.Dial
)

func Respond[T any](w *ConnWriter, id int, result T) { dcalipc.Respond(w, id, result) }

func RespondError(w *ConnWriter, id int, msg string) { dcalipc.RespondError(w, id, msg) }

func FindRunningSocket() (string, error) { return dcalipc.FindRunningSocket("dcal") }

func WaitForRunningSocket() (string, error) {
	return dcalipc.WaitForRunningSocket("dcal", socketDiscoveryGracePeriod)
}

func ParamString(p map[string]any, key string) string { return params.StringOpt(p, key, "") }

func ParamInt(p map[string]any, key string) int { return params.IntOpt(p, key, 0) }

func ParamBool(p map[string]any, key string) bool { return params.BoolLoose(p, key) }

func ParamStringSlice(p map[string]any, key string) []string { return params.StringSlice(p, key) }
