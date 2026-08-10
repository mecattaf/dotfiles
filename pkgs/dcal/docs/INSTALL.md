# Install and activate `dcal`

`dcal` is graduated as source, package, service, producer, and agent skill.
Runtime calendar data and credentials remain outside this repository.

## Verify the package

From the dotfiles repository root:

```console
nix build .#dcal
./result/bin/dcal --version
```

The derivation builds the `cmd/dcal` binary with `CGO_ENABLED=0`. Its install
check runs the standard `dcal --version` flag and requires the packaged version
exactly.

## Graduation and activation contract

Keep the tracked source tree together under `pkgs/dcal/`, including
`nix/package.nix`, and expose it from the overlay as `pkgs.dcal`. Graduation
contains four declarative pieces:

1. Put `pkgs.dcal` in `home.packages`.
2. Keep the complete skill directory at `home/dot_claude/skills/dcal/`.
   Home Manager exposes the canonical skill tree at both
   `~/.claude/skills/dcal/` and `~/.agents/skills/dcal/`.
3. Declare one user service whose executable is `dcal daemon`.
4. Declare one scheduled producer whose executable is a full `dcal sync`
   without an account id, so provider data and the Tally projection refresh
   together.

The user service and producer are declared state, not imperative setup steps.
Do not start either during a package build or automated review. Once the
graduation change is merged, the next normal dotfiles deploy makes both active;
the service then owns the long-running daemon and the producer owns periodic
sync. Avoid launching a duplicate daemon by hand.

Connecting a real calendar account is deliberately not part of activation.
Follow the manual post-merge procedure below.

## XDG runtime data

Defaults follow the XDG base-directory variables and fall back to the standard
home paths:

| Purpose | Default path |
|---|---|
| Optional JSON configuration | `${XDG_CONFIG_HOME:-~/.config}/dcal/config.json` |
| SQLite database and synced metadata | `${XDG_DATA_HOME:-~/.local/share}/dcal/dcal.db` |
| Local writable ICS collections | `${XDG_DATA_HOME:-~/.local/share}/dcal/collections/` |
| Managed read-only Tally projection | `${XDG_DATA_HOME:-~/.local/share}/dcal/tally/` |
| Encrypted file-keyring fallback | `${XDG_DATA_HOME:-~/.local/share}/dcal/keyring/` |
| One-time keyring migration marker | `${XDG_STATE_HOME:-~/.local/state}/dcal/keyring-login-migrated` |
| Per-process IPC socket | `${XDG_RUNTIME_DIR}/dcal-<pid>.sock` |

`DCAL_DB_PATH`, `DCAL_ICS_DIR`, and `DCAL_DEFAULT_CALENDAR` override the main
storage paths and write target. The config loader also accepts those values in
`config.json` as `database_path`, `ics_dir`, and `default_calendar`.

All populated paths above are local runtime state. Never add them, SQLite
`-wal`/`-shm` sidecars, or generated ICS data to git.

## Manually connect Google Calendar after merge

This is a post-merge human step. It must never run in CI, a package build,
Home Manager activation, or any other automated flow.

The default build carries the upstream public installed-app OAuth client, so
the normal connection command is:

```console
dcal account add google
```

The command opens a browser, prints the authorization URL on stderr as a
fallback, listens on a loopback callback, identifies the authorized Google
account, stores it, and starts its initial sync.

To use an owner-controlled OAuth client instead, run
`dcal account setup google` for the same implemented checklist, then:

1. In Google Cloud Console, create or select a project.
2. Enable Google Calendar API and, when Google Tasks should sync, Google Tasks
   API.
3. Configure the Google Auth Platform for an external desktop app and add the
   real account as a test user while the app remains unpublished.
4. Create an OAuth client of type **Desktop app** and download Google's
   `client_secret_….json` file to a private path outside this checkout.
5. Connect with the downloaded pair:

```console
dcal account add google --credentials /absolute/private/path/client_secret.json
```

The same complete pair can be supplied with `--client-id` and
`--client-secret`, or through `DCAL_GOOGLE_CLIENT_ID` and
`DCAL_GOOGLE_CLIENT_SECRET`. Do not split a client id and secret across
different sources.

`dcal` writes both the selected app credential pair and the resulting OAuth
token to its keyring-backed secret store. On the normal desktop this is the
Secret Service default collection (for example KWallet or KeePassXC). If the
desktop Secret Service is unavailable, the implemented fallback is the local
encrypted keyring directory listed above. Account metadata and synced calendar
state live in `dcal.db`; authorization tokens do not belong in this repository.

**No credential or token is ever committed to this repository.** Never commit
the downloaded client JSON, a custom client id or secret, authorization codes,
access or refresh tokens, keyring exports, or a populated dcal database.

Verify the human connection after the browser flow completes:

```console
dcal account list --format json
dcal sync
dcal status --format json
```

If status later reports `needsReauth`, repeat the browser flow for the stored
account with `dcal account reauth <account-id>`.
