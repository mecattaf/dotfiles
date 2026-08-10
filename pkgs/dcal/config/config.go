package config

import (
	"github.com/caarlos0/env/v11"
	"github.com/mecattaf/dcal/internal/support/log"
)

type Config struct {
	APIAddr           string `env:"DCAL_API_ADDR" envDefault:"127.0.0.1:0"`
	OAuthBindAddr     string `env:"DCAL_OAUTH_ADDR" envDefault:"127.0.0.1:0"`
	DatabasePath      string `env:"DCAL_DB_PATH"`
	GoogleClientID    string `env:"DCAL_GOOGLE_CLIENT_ID"`
	GoogleSecret      string `env:"DCAL_GOOGLE_CLIENT_SECRET"`
	MicrosoftClientID string `env:"DCAL_MICROSOFT_CLIENT_ID"`
	DisableHTTP       bool   `env:"DCAL_DISABLE_HTTP" envDefault:"false"`
	DisableIPC        bool   `env:"DCAL_DISABLE_IPC" envDefault:"false"`
}

func New() *Config {
	cfg := Config{}
	if err := env.Parse(&cfg); err != nil {
		log.Fatalf("error parsing config: %v", err)
	}
	return &cfg
}
