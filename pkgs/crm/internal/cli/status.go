package cli

import (
	"strconv"

	"github.com/mecattaf/crm/internal/db"
	"github.com/mecattaf/crm/internal/db/repo"
	crmformat "github.com/mecattaf/crm/internal/format"
	"github.com/mecattaf/crm/internal/model"
	"github.com/spf13/cobra"
)

var statusColumns = []crmformat.ColumnDef{
	{Header: "ORGS", Field: "orgs"},
	{Header: "CONTACTS", Field: "contacts"},
	{Header: "INTERACTIONS", Field: "interactions"},
	{Header: "OPEN DEALS", Field: "open_deals"},
	{Header: "LAST LOGGED", Field: "last_logged"},
	{Header: "DAYS AGO", Field: "last_logged_days_ago"},
	{Header: "NEVER CONTACTED", Field: "never_contacted"},
	{Header: "STALE (90D)", Field: "stale_90d"},
	{Header: "ROTTING DEALS", Field: "rotting_deals"},
	{Header: "DB PATH", Field: "db_path"},
}

type statusOptions struct {
	format string
}

func newStatusCmd(root *rootOptions) *cobra.Command {
	options := &statusOptions{}
	command := &cobra.Command{
		Use:   "status",
		Short: "Show the CRM dashboard",
		Args: func(command *cobra.Command, arguments []string) error {
			if err := cobra.NoArgs(command, arguments); err != nil {
				return err
			}

			_, _, err := resolveStatusFormat(command, options.format)
			return err
		},
		Example: `  crm status
  crm status --format json`,
		RunE: func(command *cobra.Command, _ []string) error {
			selected, terminal, err := resolveStatusFormat(command, options.format)
			if err != nil {
				return err
			}
			paths, err := root.resolvePaths()
			if err != nil {
				return err
			}
			database, err := db.Open(paths.database)
			if err != nil {
				return err
			}
			defer func() {
				_ = database.Close()
			}()

			status, err := repo.NewReportRepo(database).Status(command.Context())
			if err != nil {
				return err
			}
			status.DBPath = paths.database

			return writeStatus(command, *status, selected, terminal)
		},
	}
	command.Flags().StringVar(
		&options.format,
		"format",
		"",
		"output format ("+crmformat.AcceptedList(statusFormats())+")",
	)

	return command
}

func statusFormats() []crmformat.Format {
	return []crmformat.Format{crmformat.FormatTable, crmformat.FormatJSON}
}

func resolveStatusFormat(
	command *cobra.Command,
	requested string,
) (crmformat.Format, bool, error) {
	terminal := crmformat.IsTerminal(command.OutOrStdout())
	selected, err := crmformat.Resolve(requested, terminal, statusFormats())
	return selected, terminal, err
}

func writeStatus(
	command *cobra.Command,
	status model.StatusReport,
	selected crmformat.Format,
	terminal bool,
) error {
	lastLogged := "never"
	if status.LastLogged != nil {
		lastLogged = *status.LastLogged
	}
	row := crmformat.Row{
		JSON: status,
		Cells: map[string]string{
			"orgs":                 strconv.Itoa(status.Orgs),
			"contacts":             strconv.Itoa(status.Contacts),
			"interactions":         strconv.Itoa(status.Interactions),
			"open_deals":           strconv.Itoa(status.OpenDeals),
			"last_logged":          lastLogged,
			"last_logged_days_ago": strconv.Itoa(status.LastLoggedDaysAgo),
			"never_contacted":      strconv.Itoa(status.NeverContacted),
			"stale_90d":            strconv.Itoa(status.Stale90Days),
			"rotting_deals":        strconv.Itoa(status.RottingDeals),
			"db_path":              status.DBPath,
		},
	}

	return crmformat.WriteRecords(
		command.OutOrStdout(),
		[]crmformat.Row{row},
		crmformat.Options{Format: selected, Terminal: terminal, Columns: statusColumns},
	)
}
