package main

import (
	"context"
	"fmt"
	"time"

	"github.com/spf13/cobra"

	"github.com/mecattaf/dcal/internal/calendar"
	"github.com/mecattaf/dcal/internal/providers/caldav"
	"github.com/mecattaf/dcal/internal/providers/evolution"
	"github.com/mecattaf/dcal/internal/providers/google"
	"github.com/mecattaf/dcal/internal/providers/ical"
	"github.com/mecattaf/dcal/internal/providers/local"
	"github.com/mecattaf/dcal/internal/providers/microsoft"
	"github.com/mecattaf/dcal/internal/support/log"
	"github.com/mecattaf/dcal/internal/sync"
	"github.com/mecattaf/dcal/internal/tallysource"
	"github.com/mecattaf/dcal/repo"
)

var tallyFixture string

var syncCmd = &cobra.Command{
	Use:   "sync [account-id]",
	Short: "Sync all configured accounts, or a single account",
	Args:  cobra.MaximumNArgs(1),
	RunE: func(_ *cobra.Command, args []string) error {
		accountID := ""
		if len(args) == 1 {
			accountID = args[0]
		}
		if accountID != "" && tallyFixture != "" {
			return fmt.Errorf("--tally-fixture cannot be combined with an account id")
		}

		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
		defer cancel()

		st, closer, err := openStores(ctx)
		if err != nil {
			return err
		}
		defer closer()

		if accountID == "" {
			inventory, source, skipped, err := tallysource.Load(ctx, tallyFixture)
			if err != nil {
				return err
			}
			if skipped {
				infof("tally source skipped: socket %s is unavailable", source)
			} else if _, err := tallysource.NewProjector(st.repo).Sync(ctx, inventory); err != nil {
				return fmt.Errorf("project tally calendar: %w", err)
			}
		}

		// Fixtures are a synchronous test seam even when a daemon happens to be
		// running. Live sync retains the existing asynchronous daemon behavior
		// after the tally projection has been committed locally.
		if tallyFixture == "" && notifyDaemon(accountID, true) {
			if jsonOutput {
				return printJSON(syncResult("started", true, accountID))
			}
			infof("sync started in the running dcal daemon")
			return nil
		}

		switch accountID {
		case "":
			if err := sync.NewEngine(st.repo, providerRegistry(), st.secrets, time.Hour).SyncAll(ctx); err != nil {
				return err
			}
		default:
			if err := syncOneAccount(ctx, st, accountID); err != nil {
				if repo.IsNotFound(err) {
					return fmt.Errorf("no account %q (see `dcal account list`)", accountID)
				}
				return err
			}
		}

		if jsonOutput {
			return printJSON(syncResult("complete", false, accountID))
		}
		log.Info("sync complete")
		return nil
	},
}

func init() {
	syncCmd.Flags().StringVar(&tallyFixture, "tally-fixture", "", "Read a recorded query.producers JSON response instead of the live tally socket")
}

func syncResult(status string, daemon bool, accountID string) map[string]any {
	out := map[string]any{"status": status, "daemon": daemon}
	if accountID != "" {
		out["accountId"] = accountID
	}
	return out
}

func providerRegistry() *calendar.Registry {
	registry := calendar.NewRegistry()
	registry.Register(local.Factory{})
	registry.Register(google.Factory{})
	registry.Register(caldav.Factory{})
	registry.Register(microsoft.Factory{})
	registry.Register(ical.Factory{})
	registry.Register(evolution.Factory{})
	return registry
}

func syncOneAccount(ctx context.Context, st *cliStores, accountID string) error {
	acc, err := st.repo.GetAccount(ctx, accountID)
	if err != nil {
		return err
	}
	engine := sync.NewEngine(st.repo, providerRegistry(), st.secrets, time.Hour)
	return engine.SyncAccount(ctx, acc)
}
