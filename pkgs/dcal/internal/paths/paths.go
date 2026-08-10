package paths

import (
	"path/filepath"

	dcalpaths "github.com/mecattaf/dcal/internal/support/paths"
)

var app = dcalpaths.New("dcal")

func ConfigDir() (string, error) { return app.ConfigDir() }

func DataDir() (string, error) { return app.DataDir() }

func CacheDir() (string, error) { return app.CacheDir() }

func StateDir() (string, error) { return app.StateDir() }

func DatabasePath() (string, error) {
	dir, err := DataDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "dcal.db"), nil
}

func SocketDir() string { return app.SocketDir() }

func SocketPath() string { return app.SocketPath() }
