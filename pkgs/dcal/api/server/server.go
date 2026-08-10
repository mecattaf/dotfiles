package server

import (
	"github.com/mecattaf/dcal/config"
	"github.com/mecattaf/dcal/internal/calendar"
	"github.com/mecattaf/dcal/repo"
)

type EmptyInput struct{}

type DeletedResponse struct {
	ID      string `json:"id"`
	Deleted bool   `json:"deleted"`
}

type Server struct {
	Cfg      *config.Config
	Repo     *repo.Repo
	Registry *calendar.Registry
	Secrets  calendar.SecretStore
}
