# Agent orientation — dcal

`dcal` is the headless calendar CLI vendored into this dotfiles repository. It
is a single Go module and binary built with Cobra, Ent, and modernc SQLite. The
daemon owns IPC, provider sync, reminders, and invitations; the ergonomic
top-level verbs are the stable agent surface.

Read before changing source, in this order:

1. This file.
2. `NOTICE.md` and `LICENSE` for fork provenance and redistribution terms.
3. `cmd/dcal/commands.go`, the relevant command file, and its tests for the
   frozen CLI behavior.
4. The affected package under `internal/`, `repo/`, or `api/`.
5. `skills/dcal/SKILL.md` and `skills/dcal/flags.md` when behavior exposed to
   agents changes.

Stay inside the assigned issue. Do not broaden a CLI, storage, provider, or
deployment change merely because adjacent upstream code exists.

## Fork provenance

The calendar core is adapted from Avenge Media LLC's MIT-licensed
`dankcalendar` and pinned at upstream commit
`a57a879061cd482c416d5ece44cb529249c37b06`. Preserve `LICENSE`, `NOTICE.md`,
the pinned commit, and upstream copyright attribution in every redistribution.

This fork deliberately strips the UI and rebrands the executable while
retaining the headless calendar core, notification support, and credential
portal code needed by providers and reminders. Treat upstream as provenance,
not as permission to restore removed UI or silently replace fork-specific CLI,
XDG, CRM, or Tally behavior.

## Module layout

- `cmd/dcal/`: Cobra root, agent-facing verbs, daemon bootstrap, output and
  exit-code handling, CRM/call integration.
- `config/`: XDG configuration defaults, JSON loading, and `DCAL_*` overlays.
- `api/`: optional loopback HTTP server and authentication/calendar handlers.
- `internal/ipc/`: Unix-socket protocol, router, methods, and daemon client.
- `internal/calendar/`: provider-neutral domain types and provider registry.
- `internal/providers/`: local, Google, Microsoft, CalDAV, iCal, and Evolution
  implementations.
- `internal/accounts/`, `internal/oauth/`, `internal/keyring/`: account setup,
  browser OAuth, and keyring-backed secrets.
- `internal/sync/`, `internal/reminders/`, `internal/invitations/`: long-running
  daemon engines.
- `internal/tallysource/`: read-only projection of Tally producer inventory.
- `repo/`: persistence operations over the generated Ent client.
- `ent/schema/`: schema source; most other files under `ent/` are generated.
- `ent/migrate/migrations/`: embedded, versioned Goose migrations and checksum.
- `models/`: transport-facing calendar/account/event/task shapes retained from
  the core.
- `testdata/`: deterministic fixtures; never put live account data here.
- `nix/package.nix`: static package definition and installed-version check.

## Build and test

Go is not assumed to be on PATH. From `pkgs/dcal/`, keep compiling commands
pure-Go unless a specifically scoped test proves otherwise:

```console
nix shell nixpkgs#go -c env CGO_ENABLED=0 go test ./...
nix shell nixpkgs#go -c env CGO_ENABLED=0 go vet ./...
nix shell nixpkgs#golangci-lint nixpkgs#go -c env CGO_ENABLED=0 golangci-lint run ./...
```

From the dotfiles repository root, prove the distributed package with:

```console
nix build .#dcal
./result/bin/dcal --version
```

Use table-driven unit tests near the package they cover. CLI contract tests in
`cmd/dcal/commands_test.go` execute the command through a helper subprocess so
stdout bytes, stderr, and numeric exit codes are observable. Give tests fresh
HOME and XDG directories, fake external binaries, local IPC sockets, and
recorded fixtures. Unit and integration tests must not contact live providers,
the desktop keyring, the real CRM, or the real Tally daemon.

Edit schema definitions under `ent/schema/`, then regenerate Ent output with
`go generate ./ent` and add a forward migration when persisted shape changes.
Do not hand-edit generated Ent files or rewrite an applied migration. Keep
`ent/migrate/migrations/atlas.sum` consistent with the migration set.

## Frozen CLI contract

The Cobra definitions under `cmd/dcal/` and their tests are the source of
truth. Do not rename or remove existing verbs, arguments, aliases, flags, JSON
fields, or exit meanings unless the assigned issue explicitly changes the
contract. Update help, tests, the dcal skill, and install docs together when an
authorized contract change lands.

- `--format` accepts only `text` and `json`. Prefer it over the deprecated
  hidden `--json` compatibility flag.
- Stdout is data. Stderr is progress, browser prompts, notices, dependency
  diagnostics, and errors. Never mix them.
- Exit codes are 0 success, 1 validation/usage/generic failure, 2 not found,
  3 ambiguous ref, and 4 conflict/constraint/read-only state.
- Event `add`, `show`, `edit`, `rm`, `ls`, and `agenda` are daemon-backed.
  `status`, account management, and fallback sync also open the same XDG store
  directly.
- Event start/end flags require RFC3339. Agenda bounds accept RFC3339 or local
  `YYYY-MM-DD`, with the date-form `--to` inclusive.
- `dcal add --crm` must resolve exactly one CRM contact, persist its canonical
  ref, and use kind `call`. Preserve CRM exit 2/3 and stderr without wrapping.
- `dcal done` is the sole composed post-call transition: resolve one finished
  CRM call, diarize, publish transcript evidence safely, and log the CRM
  interaction.
- A full `dcal sync` also refreshes the managed read-only Tally projection;
  an account-specific sync does not.

Never commit databases, SQLite sidecars, generated calendar collections,
recordings, transcripts, OAuth credential files, tokens, or build results.
