# dcal flag reference

Use this reference for the current agent-facing command surface. Run
`dcal <verb> --help` for canonical help at execution time.

Every command inherits `--format text|json` and `--help`. Text is the default.
The root also accepts `--version`. Use JSON when consuming records; stdout is
data and stderr is progress, prompts, notices, and errors.

## Event workflow

### `dcal add [title]`

Require `--start` and `--end`, both RFC3339 instants. Title is required unless
`--crm` resolves a contact.

- `--calendar <name-or-id>`: select a writable event calendar; otherwise use
  `default_calendar`, the first writable Google calendar, or a local Personal
  calendar.
- `--crm <contact-ref>`: resolve and persist a CRM contact link.
- `--kind <call>`: set the only supported CRM event kind. `--crm` implies it.
- `--start <RFC3339>` and `--end <RFC3339>`: require end after start.
- `--description <text>`
- `--location <text>`
- `--status <confirmed|tentative|cancelled>`
- `--all-day`

Text output is the new event ref; JSON output is the event record.

### `dcal ls`

- `--calendar <name-or-id>`: required; list that calendar's events.

### `dcal agenda`

- `--from <YYYY-MM-DD|RFC3339>`: required lower bound.
- `--to <YYYY-MM-DD|RFC3339>`: required inclusive upper bound.

Return events across calendars in chronological order.

### `dcal show <event-ref>`

Accept no verb-specific flags. Return one event.

### `dcal edit <event-ref>`

Require at least one changed field:

- `--title <text>`: cannot be empty.
- `--start <RFC3339>`
- `--end <RFC3339>`
- `--description <text>`: an explicit empty value clears it.
- `--location <text>`: an explicit empty value clears it.
- `--status <confirmed|tentative|cancelled>`
- `--all-day`: set all-day true; use `--all-day=false` to clear it.

The resulting end must remain after start. Text output is the event ref.

### `dcal rm <event-ref>`

Alias: `dcal remove <event-ref>`. Accept no verb-specific flags and has no
confirmation prompt. Text output is the removed event ref.

### `dcal done <event-ref>`

- `--dry-run`: print the resolved diarization, transcript, and CRM-log plan
  without executing it.

Require a finished event carrying both CRM ref and CRM kind `call`.

## Agenda health and sync

### `dcal status`

Accept no verb-specific flags. Report accounts, authorization state,
calendars, event counts, last sync, and unlogged finished CRM calls.

### `dcal sync [account-id]`

With no id, sync every account and project live Tally producer schedules. With
an id, sync only that account.

- `--tally-fixture <path>`: test seam for recorded `query.producers` JSON;
  cannot be combined with an account id. Do not use it for live operation.

A running daemon makes live sync asynchronous; otherwise the command performs
the sync directly.

## Accounts

### Account reads and lifecycle

- `dcal account list`: list configured accounts. Alias: `dcal account ls`.
- `dcal account providers`: list supported provider types.
- `dcal account reauth <account-id>`: repeat OAuth for an existing Google or
  Microsoft account using its stored app credentials.
- `dcal account remove <account-id>`: remove the account and locally synced
  data. `--yes` skips its confirmation prompt. Alias: `dcal account delete`.
- `dcal account setup <google|microsoft>`: print the implemented OAuth-app
  setup instructions.

### `dcal account add google`

- `--credentials <path>`: read an installed or web OAuth client from Google's
  downloaded `client_secret_….json` file.
- `--client-id <id>` and `--client-secret <secret>`: supply a complete custom
  pair together.

Without explicit flags, credentials resolve from dcal configuration and
`DCAL_GOOGLE_CLIENT_ID` plus `DCAL_GOOGLE_CLIENT_SECRET`, then from the shipped
installed-app client. The browser OAuth flow stores the app pair and token in
the dcal keyring-backed secret store.

### Other account providers

- `dcal account add microsoft`: `--client-id <id>`, `--tenant <tenant>`.
- `dcal account add caldav`: `--url <url>`, `--username <name>`,
  `--password <password>`, `--name <display-name>`, `--insecure`.
- `dcal account add icloud`: `--username <apple-id>`,
  `--password <app-password>`, `--name <display-name>`.
- `dcal account add ical <url>`: `--username <name>`,
  `--password <password>`, `--name <display-name>`.
- `dcal account add evolution`: `--name <display-name>`.
- `dcal account add local`: `--name <display-name>`; use the configured
  `ics_dir`.

Omitted interactive passwords are prompted on stderr rather than printed.

## Other public verbs

- `dcal calendar add <name>`: create a calendar in the local account.
- `dcal events rsvp <event-id> <accept|decline|tentative>`: push a meeting
  response to the synced provider.
- `dcal reminders`: `--limit <N>` lists upcoming reminders from the daemon.
- `dcal reminders test`: send a desktop test notification through the daemon.
- `dcal daemon`: run the headless IPC and HTTP daemon.
- `dcal ipc <method> [key=value...]`: invoke a daemon IPC method.
- `dcal ipc list`: list available IPC methods and parameters.
- `dcal version`: print build version information.

Use the higher-level event verbs instead of raw IPC for normal agent work.

## Relevant environment overrides

- `DCAL_DB_PATH`, `DCAL_ICS_DIR`, `DCAL_DEFAULT_CALENDAR`: storage and default
  calendar overrides.
- `DCAL_SOCKET`: select a running daemon socket.
- `DCAL_GOOGLE_CLIENT_ID`, `DCAL_GOOGLE_CLIENT_SECRET`: custom Google OAuth
  client pair.
- `DCAL_CRM_BIN`: CRM executable used for linked calls.
- `DCAL_CALL_DIARIZE_BIN`: diarizer used by `dcal done`.
- `DCAL_RECORDINGS_ROOT` or `CALL_RECORDINGS_ROOT`: call recording root.
- `DCAL_CRM_BASE` or the directory containing `CRM_DB`: CRM transcript root.
- `TALLY_SOCKET`: live Tally socket used by full sync.
