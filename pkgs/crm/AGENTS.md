# Agent orientation — crm

Buildout repo for `crm`, a personal single-user CRM as one static Go binary
(`modernc.org/sqlite`, `CGO_ENABLED=0`, cobra). The finished tool graduates
into the owner's dotfiles; this repo exists to build it.

Read before writing any code, in this order:

1. `.specify/memory/constitution.md` — engineering non-negotiables. These are
   hard constraints; a PR that violates one is wrong even if tests pass.
2. `specs/001-crm/spec.md` — the complete product specification.
3. `specs/001-crm/data-model.sql` — the initial migration DDL (source of
   truth for the schema; embedded via `go:embed` as
   `internal/db/migrations/001_initial.sql`).
4. `specs/001-crm/style-transfer-map.md` — for the capability you are
   implementing, the reference source files to read first. The references are
   corpora to transfer implementation style from, not code to copy:
   - `/home/tom/Downloads/crm-cli` — Go + cobra + modernc (our exact stack)
   - `/home/tom/Downloads/crm.cli` — Bun/TS (product design + skill genre)
   - `/home/tom/mecattaf/sodimo-crm` — deals/pipelines/stages shape

Your assigned GitHub issue defines the scope of one increment. Stay inside
it. Implement exactly its acceptance criteria; do not build ahead of the
issue sequence.

## Build and test

Go is not on PATH; every command goes through nix. nixpkgs' go defaults to
`CGO_ENABLED=1` with `CC=gcc`, so on this gcc-less host every compiling
command must pin `CGO_ENABLED=0` — except the race gate, which is cgo-backed
and brings its own gcc:

    nix shell nixpkgs#go -c env CGO_ENABLED=0 go build ./...
    nix shell nixpkgs#go -c env CGO_ENABLED=0 go vet ./...
    nix shell nixpkgs#go nixpkgs#gcc -c go test -race ./...
    nix shell nixpkgs#golangci-lint nixpkgs#go -c env CGO_ENABLED=0 golangci-lint run ./...

These four are also the merge gates, on every issue without exception — run
them yourself, exactly as written, before declaring done. `CGO_ENABLED=0`
also constrains the shipped binary: the module stays pure Go
(`modernc.org/sqlite`, never a cgo driver). Integration tests exec the real built binary (built with
`-ldflags "-X main.version=0.0.0-test"`) and assert stdout bytes, stderr, and
numeric exit codes.

## Repository conventions

- Module path: `github.com/mecattaf/crm`. Binary entry: `cmd/crm/main.go`.
  Layout: `internal/cli` (cobra commands), `internal/db` (open funnel,
  migrations, repos), `internal/model` (types, sentinel errors),
  `internal/format` (output), `internal/resolve` (ref resolution).
- One commit per logical change; imperative subject; no changelog ceremony.
- stdout is data, stderr is messages, everywhere, with no exceptions.
- Never create or commit a database file, `-wal`/`-shm` sidecar, or build
  artifact.

## Operating the CRM

Use the `crm` CLI as the only data interface. Never hand-edit `crm.db`.
Stdout is data; stderr is prompts, notices, hook diagnostics, and errors. Use
`--format json` for structured consumption and `--format ids` for piping refs
into another command.

Search before creating. Refs accept prefixed ids, bare ids, names, emails, and
LinkedIn handles where applicable. Exit 3 means the ref is ambiguous: show the
candidate refs to the user and never guess. Prefer `crm context <ref>` for a
complete pre-conversation briefing instead of assembling separate reads.

Keep three forms of knowledge distinct:

- A transcript is evidence of record. It must exist before logging and must be
  inside the directory containing the resolved database path. Store and pass
  the base-relative path, normally `transcripts/YYYY/<date>-<slug>.md`.
- An interaction summary describes that one event. Keep it concise; use
  `--body-file` or `--transcript` for long prose.
- Contact and organization `context` is the mutable current dossier. Append
  durable facts with `--context-append`; do not overwrite established context
  unless correcting it deliberately.

Run `crm <verb> --help` for exact flags. The shipped workflow guide is
`skills/crm/SKILL.md`, with exhaustive flags in `skills/crm/flags.md`.

### Annotated transcript 1 — post-call flow

```console
# Search first; c12 is a stable ref that can be reused directly.
$ crm find "Nick Dupont" --type contact --format ids
c12

# The transcript file already exists under the database directory.
$ crm log --kind call --with c12 --org kima \
    --summary "wants the deck before Friday" --date 2026-07-29 \
    --transcript transcripts/2026/2026-07-29-nick-dupont-call.md \
    --format ids
i43

# Preserve event history in i43; append the durable preference to the dossier.
$ crm contact edit c12 \
    --context-append "Prefers the deck before partner meetings." \
    --source transcripts/2026/2026-07-29-nick-dupont-call.md \
    --format ids
c12

# Verify the assembled contact and new event in one read.
$ crm context c12 --format json | jq '{contact: .contact.ref, timeline: [.timeline[].ref]}'
{"contact":"c12","timeline":["i43"]}
```

### Annotated transcript 2 — a genuinely new company

```console
# Empty ids output means no live organization matched; do not infer from names.
$ crm find "Acme Robotics" --type org --format ids

# Create the organization with provenance, then attach the mentioned person.
$ crm org add "Acme Robotics" --category customer --website acme.example \
    --source notes/2026-07-31.md --detail "Mentioned by Alice Martin" \
    --format ids
o7
$ crm contact add "Alice Martin" --org o7 --title Founder \
    --source notes/2026-07-31.md --format ids
c21

# Record why the new records exist and verify the organization briefing.
$ crm log --kind note --org o7 --with c21 \
    --summary "Introduced Acme Robotics during the July review" --format ids
i44
$ crm context o7 --format json | jq '{org: .org.ref, timeline: [.timeline[].ref]}'
{"org":"o7","timeline":["i44"]}
```
