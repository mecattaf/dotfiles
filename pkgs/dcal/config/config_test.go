package config_test

import (
	"os"
	"testing"

	"github.com/stretchr/testify/assert"

	"github.com/mecattaf/dcal/config"
)

var configEnvVars = []string{
	"DCAL_API_ADDR",
	"DCAL_OAUTH_ADDR",
	"DCAL_DB_PATH",
	"DCAL_GOOGLE_CLIENT_ID",
	"DCAL_GOOGLE_CLIENT_SECRET",
	"DCAL_MICROSOFT_CLIENT_ID",
	"DCAL_DISABLE_HTTP",
	"DCAL_DISABLE_IPC",
}

func clearConfigEnv(t *testing.T) {
	t.Helper()
	for _, key := range configEnvVars {
		t.Setenv(key, "")
		os.Unsetenv(key)
	}
}

func TestConfigDefaults(t *testing.T) {
	clearConfigEnv(t)

	cfg := config.New()

	assert.Equal(t, "127.0.0.1:0", cfg.APIAddr)
	assert.Equal(t, "127.0.0.1:0", cfg.OAuthBindAddr)
	assert.Empty(t, cfg.DatabasePath)
	assert.False(t, cfg.DisableHTTP)
	assert.False(t, cfg.DisableIPC)
}

func TestConfigReadsEnvironment(t *testing.T) {
	clearConfigEnv(t)
	t.Setenv("DCAL_API_ADDR", "127.0.0.1:8765")
	t.Setenv("DCAL_DB_PATH", "/tmp/dcal.db")
	t.Setenv("DCAL_GOOGLE_CLIENT_ID", "client-id")
	t.Setenv("DCAL_DISABLE_HTTP", "true")

	cfg := config.New()

	assert.Equal(t, "127.0.0.1:8765", cfg.APIAddr)
	assert.Equal(t, "/tmp/dcal.db", cfg.DatabasePath)
	assert.Equal(t, "client-id", cfg.GoogleClientID)
	assert.True(t, cfg.DisableHTTP)
	assert.False(t, cfg.DisableIPC)
}
