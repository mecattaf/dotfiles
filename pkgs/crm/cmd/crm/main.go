// Command crm provides the personal git-backed CRM CLI.
package main

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"github.com/mecattaf/crm/internal/cli"
	"github.com/mecattaf/crm/internal/model"
)

var version = "dev"

func main() {
	os.Exit(run())
}

func run() int {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	root := cli.NewRootCmd(version)
	if err := root.ExecuteContext(ctx); err != nil {
		_, _ = fmt.Fprintf(os.Stderr, "crm: error: %s\n", err)
		return model.ExitCode(err)
	}

	return 0
}
