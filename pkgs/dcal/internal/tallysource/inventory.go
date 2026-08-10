// Package tallysource projects tally producer schedules into a managed local
// calendar.
package tallysource

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"strings"
	"time"
)

const maxFrameBytes = 16 * 1024 * 1024

// Inventory is the versioned result of tally's query.producers method.
type Inventory struct {
	SchemaVersion   int        `json:"schemaVersion"`
	ProtocolVersion int        `json:"protocolVersion"`
	Items           []Producer `json:"items"`
}

type Producer struct {
	Name       string   `json:"name"`
	Kind       string   `json:"kind"`
	Configured bool     `json:"configured"`
	Enabled    bool     `json:"enabled"`
	Unit       Unit     `json:"unit"`
	Schedule   Schedule `json:"schedule"`
	Runtime    Runtime  `json:"runtime"`
}

type Unit struct {
	Service string  `json:"service"`
	Timer   *string `json:"timer"`
}

type Schedule struct {
	CalendarExpression *string `json:"calendarExpression"`
	PollCadenceSec     *uint64 `json:"pollCadenceSec"`
	NextTrigger        *string `json:"nextTrigger"`
}

type Runtime struct {
	LastTrigger  *string `json:"lastTrigger"`
	LastEmission *string `json:"lastEmission"`
}

// Load reads a recorded query.producers result when fixturePath is set, or
// queries the live tally Unix socket otherwise. A missing live socket is a
// clean skip and returns its resolved path for the caller's stderr notice.
func Load(ctx context.Context, fixturePath string) (inventory Inventory, source string, skipped bool, err error) {
	if fixturePath = strings.TrimSpace(fixturePath); fixturePath != "" {
		f, openErr := os.Open(fixturePath)
		if openErr != nil {
			return Inventory{}, fixturePath, false, fmt.Errorf("open tally fixture %q: %w", fixturePath, openErr)
		}
		defer f.Close()

		inventory, err = decodeInventory(io.LimitReader(f, maxFrameBytes+1))
		if err != nil {
			return Inventory{}, fixturePath, false, fmt.Errorf("read tally fixture %q: %w", fixturePath, err)
		}
		return inventory, fixturePath, false, nil
	}

	socketPath := SocketPath()
	if _, statErr := os.Stat(socketPath); statErr != nil {
		if errors.Is(statErr, os.ErrNotExist) {
			return Inventory{}, socketPath, true, nil
		}
		return Inventory{}, socketPath, false, fmt.Errorf("stat tally socket %q: %w", socketPath, statErr)
	}

	inventory, err = querySocket(ctx, socketPath)
	if err != nil {
		return Inventory{}, socketPath, false, err
	}
	return inventory, socketPath, false, nil
}

// SocketPath follows tally-client's documented socket resolution order after
// its CLI-only --socket flag.
func SocketPath() string {
	if path := strings.TrimSpace(os.Getenv("TALLY_SOCKET")); path != "" {
		return path
	}
	if runtimeDir := strings.TrimSpace(os.Getenv("XDG_RUNTIME_DIR")); runtimeDir != "" {
		return filepath.Join(runtimeDir, "tally", "tally.sock")
	}
	return filepath.Join(os.TempDir(), "tally", "tally.sock")
}

type rpcResponse struct {
	Result json.RawMessage `json:"result"`
	Error  *rpcError       `json:"error"`
}

type rpcError struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

func querySocket(ctx context.Context, socketPath string) (Inventory, error) {
	conn, err := (&net.Dialer{}).DialContext(ctx, "unix", socketPath)
	if err != nil {
		return Inventory{}, fmt.Errorf("connect to tally socket %q: %w", socketPath, err)
	}
	defer conn.Close()

	deadline := time.Now().Add(15 * time.Second)
	if ctxDeadline, ok := ctx.Deadline(); ok && ctxDeadline.Before(deadline) {
		deadline = ctxDeadline
	}
	if err := conn.SetDeadline(deadline); err != nil {
		return Inventory{}, fmt.Errorf("set tally socket deadline: %w", err)
	}

	request := struct {
		ID     string         `json:"id"`
		Method string         `json:"method"`
		Params map[string]any `json:"params"`
	}{ID: "dcal-sync", Method: "query.producers", Params: map[string]any{}}
	if err := json.NewEncoder(conn).Encode(request); err != nil {
		return Inventory{}, fmt.Errorf("write query.producers request: %w", err)
	}

	limited := &io.LimitedReader{R: conn, N: maxFrameBytes + 1}
	decoder := json.NewDecoder(limited)
	var response rpcResponse
	if err := decoder.Decode(&response); err != nil {
		return Inventory{}, fmt.Errorf("read query.producers response: %w", err)
	}
	if decoder.InputOffset() > maxFrameBytes {
		return Inventory{}, fmt.Errorf("query.producers response exceeds %d bytes", maxFrameBytes)
	}
	if response.Error != nil {
		return Inventory{}, fmt.Errorf("query.producers: %s: %s", response.Error.Code, response.Error.Message)
	}
	if len(response.Result) == 0 {
		return Inventory{}, errors.New("query.producers response has no result")
	}
	return decodeInventoryBytes(response.Result)
}

// decodeInventory accepts both the raw result printed by `tally query
// producers` and a recorded NDJSON-RPC response containing that result.
func decodeInventory(r io.Reader) (Inventory, error) {
	data, err := io.ReadAll(r)
	if err != nil {
		return Inventory{}, err
	}
	if len(data) > maxFrameBytes {
		return Inventory{}, fmt.Errorf("query.producers payload exceeds %d bytes", maxFrameBytes)
	}
	return decodeInventoryBytes(data)
}

func decodeInventoryBytes(data []byte) (Inventory, error) {
	var envelope rpcResponse
	if err := json.Unmarshal(data, &envelope); err != nil {
		return Inventory{}, fmt.Errorf("decode query.producers JSON: %w", err)
	}
	if envelope.Error != nil {
		return Inventory{}, fmt.Errorf("query.producers: %s: %s", envelope.Error.Code, envelope.Error.Message)
	}
	if len(envelope.Result) > 0 {
		data = envelope.Result
	}

	var inventory Inventory
	if err := json.Unmarshal(data, &inventory); err != nil {
		return Inventory{}, fmt.Errorf("decode query.producers result: %w", err)
	}
	if inventory.SchemaVersion != 1 {
		return Inventory{}, fmt.Errorf("unsupported query.producers schemaVersion %d (expected 1)", inventory.SchemaVersion)
	}
	if inventory.Items == nil {
		inventory.Items = []Producer{}
	}
	return inventory, nil
}
