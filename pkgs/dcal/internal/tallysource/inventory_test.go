package tallysource

import (
	"context"
	"encoding/json"
	"net"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestDecodeInventoryAcceptsRawResultAndRPCEnvelope(t *testing.T) {
	raw := []byte(`{"schemaVersion":1,"protocolVersion":5,"items":[]}`)

	direct, err := decodeInventoryBytes(raw)
	require.NoError(t, err)
	assert.Empty(t, direct.Items)

	envelope, err := json.Marshal(map[string]any{
		"id":     "fixture",
		"result": json.RawMessage(raw),
	})
	require.NoError(t, err)
	wrapped, err := decodeInventoryBytes(envelope)
	require.NoError(t, err)
	assert.Equal(t, direct, wrapped)
}

func TestQuerySocketUsesQueryProducersRPC(t *testing.T) {
	socketPath := filepath.Join(t.TempDir(), "tally.sock")
	listener, err := net.Listen("unix", socketPath)
	require.NoError(t, err)
	defer listener.Close()

	requestSeen := make(chan map[string]any, 1)
	go func() {
		conn, acceptErr := listener.Accept()
		if acceptErr != nil {
			return
		}
		defer conn.Close()
		var request map[string]any
		if decodeErr := json.NewDecoder(conn).Decode(&request); decodeErr != nil {
			return
		}
		requestSeen <- request
		_ = json.NewEncoder(conn).Encode(map[string]any{
			"id": request["id"],
			"result": map[string]any{
				"schemaVersion":   1,
				"protocolVersion": 5,
				"items": []map[string]any{{
					"name":       "nightly-eval",
					"kind":       "calendar",
					"configured": true,
					"enabled":    true,
				}},
			},
		})
	}()

	inventory, err := querySocket(context.Background(), socketPath)
	require.NoError(t, err)
	require.Len(t, inventory.Items, 1)
	assert.Equal(t, "nightly-eval", inventory.Items[0].Name)

	request := <-requestSeen
	assert.Equal(t, "query.producers", request["method"])
	assert.Equal(t, map[string]any{}, request["params"])
}

func TestLoadMissingSocketIsCleanSkip(t *testing.T) {
	t.Setenv("TALLY_SOCKET", filepath.Join(t.TempDir(), "missing.sock"))

	_, source, skipped, err := Load(context.Background(), "")
	require.NoError(t, err)
	assert.True(t, skipped)
	assert.Equal(t, filepath.Clean(source), source)
}
