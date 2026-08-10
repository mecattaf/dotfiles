# calendar-cli — scoping

Scoping record for the calendar CLI chapter, written 2026-08-10 from three
subagent evaluations (the upstream calendar core, Baikal, Radicale — clones
live in `~/Downloads/`) plus Tom's rulings in the orchestrating session. This is the
document a future implementing session starts from. The web UI display of
this backend is explicitly a **separate later journey**; this chapter is the
CLI, the database, the sync engine, and the projections.

## Settled rulings (Tom, 2026-08-10)

1. **Shape**: sibling of the CRM — Go + cobra + `modernc.org/sqlite`
   (`CGO_ENABLED=0`), source vendored under `dotfiles/pkgs/`, nix package.
   Same graduation pattern as `pkgs/crm`, except data placement: XDG, not
   git (superseded by sealed ruling 1 below).
2. **Fork the upstream `core/` wholesale** rather than writing fresh or
   extracting pieces. MIT-licensed; keep upstream copyright notices.
3. **Native Google provider, not gws.** The upstream core's built-in Google
   Calendar provider (bidirectional, incremental sync tokens, OAuth loopback
   + keyring) is the Google leg. gws stays for everything else it does.
4. **Hourly background refresh** of inbound sources (Google, tally), not
   near-real-time polling. Local writes through the CLI are immediate.
5. **No quickshell / upstream-shell integration of any kind.**
6. **No DAV servers, period** (re-sealed 2026-08-10 evening). No Baikal, no
   Radicale, and the self-serve go-webdav endgame is dropped with them:
   there are no phones or secondary devices in this setup, so a DAV
   consumer does not exist. The server evaluations below are retained as
   historical record only. What survives from that research is the vdir
   principle (ruling 8).
7. **CRM stays the single source of truth for people.** Anything that puts
   CRM data on other surfaces is a one-way projection.
8. **Projections are one-way, local, and file-shaped** (re-sealed
   2026-08-10 evening). The desirable functionality from the DAV/vdir
   research is the vdir principle itself: any projection is emitted as a
   spec-conformant vdir on local disk, readable in place by the fork's
   local provider (and khal/khard if ever wanted) — no server, no sync
   daemon, no devices. The *purpose* of linkage stands: a calendar event
   that mentions a person carries the contact's stable `c<id>` ref, so
   events with a specific person are trackable across both systems.
   Name→email autocompletion resolves through the `crm` CLI directly, not
   through contact cards.

## The fork

Upstream: Avenge Media LLC's calendar project (MIT), pinned at commit
`a57a879061cd482c416d5ece44cb529249c37b06`, local clone
`~/Downloads/dcal-upstream`. The upstream repository name is deliberately
not written anywhere in this repo — see sealed naming ruling 6.
`core/` is a standalone Go module (Go 1.26, pure-Go SQLite) that builds and
runs headless today — the QML shell is behind a `withshell` build tag the
default build already excludes. Verified empirically: built, ran
`dcal daemon`, drove account/calendar/event creation and recurrence
expansion over its JSON-RPC unix socket with no Qt anywhere.

**Keep** (~98% of hand-written code): `ent/` + `repo/` (schema, migrations,
recurrence expansion), `internal/providers/` (google, caldav, ics, local,
microsoft, evolution — 8k lines), `internal/sync`, `internal/calendar`
(domain model + 8-method Provider interface), `internal/recurrence`
(rrule-go with the year-1604 bound fix), `internal/oauth` +
`internal/keyring`, `internal/reminders`, `internal/accounts`, `api/`
(HUMA/chi HTTP API with self-generating OpenAPI — the later web UI's seam).

**Delete**: `quickshell/` tree, the QML-common submodule,
`internal/shellembed`, `cmd/dcal/shellapp.go`, `cmd/dcal/window.go`,
`internal/ipc/ui.go`, `internal/colorscheme`; probably `internal/autostart`,
`internal/notify`, `internal/uriopen`.

**Replace**: `internal/settings` (reads QML-shaped JSON defaults) with our
own config.

**Write fresh** (~1–2k lines, the actual work): the ergonomic CLI. Upstream
`cmd/dcal` only exposes a generic RPC shim (`dcal ipc events.create k=v`).
We write real cobra verbs — `add`, `ls`, `agenda`, `show`, `edit`, `rm`,
`sync`, `status` — over the existing IPC/repo layer.

Storage properties inherited free: local calendars are **plain ICS files on
disk** (vdirsyncer-compatible; single file or dir-of-files) with SQLite as
the index, `raw_ics` retained per event so round-trips are lossless, events
carry `uid`/`remote_id`/`etag` and proper recurrence-exception rows.

Known quirk: unix socket path is subject to the 108-char limit — deep
`XDG_RUNTIME_DIR` nesting breaks the daemon bind.

## Sources feeding the calendar

### Google Calendar (bidirectional)
Native provider, incremental sync tokens, hourly pull via the refresh timer.
The only bidirectional edge. Topology doctrine from the evaluations, adopted:
**keep it a line, never a diamond** — while Google is in the loop, every
other surface (phone, DAV) is a read-only projection; when Google is
eventually offboarded, one edge flips to bidirectional deliberately.

### Tally scheduled runs (read-only, hourly)
Confirmed against the tally.nix source: **tally has no calendar projection
surface** and deliberately refuses to compute next-fire times
(`nextTriggerUnavailableReason:
"systemd-calendar-next-trigger-is-not-available-to-the-daemon"`). What it
offers is `tally query producers` — RPC `query.producers` over
`$XDG_RUNTIME_DIR/tally/tally.sock`, or the CLI verb which already prints
raw JSON — returning each producer's `schedule.calendarExpression` (raw
systemd `OnCalendar`), unit names, and `runtime.lastTrigger/lastEmission`.

So the calendar CLI owns the synthesis: a tally source adapter (either a
small implementation of the 8-method Provider interface or a plain import
job) that hourly:
1. reads `query.producers` (kind `calendar` for scheduled flows; poll-kind
   producers get their single next-tick estimate);
2. expands each `calendarExpression` to concrete future firings via
   `systemd-analyze calendar --iterations=N` (systemd owns that math);
3. upserts them as events in a dedicated read-only `tally` calendar, and
   marks retrospective runs from `lastTrigger`/`lastEmission`.

One-shot ad-hoc enqueues have no producer entry and are out of scope;
`tally query jobs --source calendar` exists if run *history* is ever wanted.

### Local events
Native — the CLI's own `add`, stored as ICS + indexed.

## Refresh mechanics

One hourly systemd user timer (or, fittingly, a tally calendar producer)
runs `dcal sync`: Google incremental pull, tally re-projection, reminder
recompute. Cheap by construction — sync tokens make the Google pass a delta,
and the tally pass is one RPC + N `systemd-analyze` calls. No polling loops
anywhere; the CLI reads an always-warm local db.

## CRM linkage (the point of building these together)

The contract for "I have a call with X at Y":

- Calendar events can carry a CRM reference: `X-CRM-REF:c42` (the CRM's
  stable prefixed ref — SQLite rowids are never reused, so `c42` is
  permanent) plus an event kind marker (`X-CRM-KIND:call`).
- CLI ergonomics: `dcal add "call with c42 at 15:00"` resolves the ref via
  `crm show c42` and titles the event from the contact's name; conversely
  a `--crm c42` flag on `add`.
- **Post-event flow**: when a `X-CRM-KIND:call` event passes its end time,
  the hourly pass (or an explicit `dcal done <event>`) expects a capture in
  `~/Recordings`, hands it to `call-diarize` (already in `dotfiles/pkgs/`),
  writes the transcript under `notes/crm/transcripts/`, and finishes with
  `crm log --kind call --transcript … --refs c42`. The event is the trigger
  and the metadata carrier; CRM remains the system of record for the
  interaction.
- Reverse direction: the CRM's existing `CRM_POST_WRITE_HOOK` (JSON on
  stdin, fires on mutations only) can notify the calendar side when
  follow-ups with dates are logged, creating tentative events.

## Device projections — REMOVED from scope (sealed 2026-08-10 evening)

**There is no phone in this setup, and there will not be one.** This is
dotfiles for a NixOS desktop; every device-projection provision below
(DAVx5, caller ID, phone contact cards, phone-facing CalDAV/CardDAV) is out
of scope entirely, not deferred. The section is retained unedited as the
evaluation record because the vdir findings in the appendix — the part that
survives — were produced by it.

## Historical record: phone projections and the DAV verdicts (out of scope)

**Baikal: rejected for everything.** nixpkgs ships 0.11.1, affected by a
High advisory patched only in 0.12.1 (GHSA-j44x-cj7p-vx2w — authenticated
calendar-rename XSS → admin takeover; no CVE ID, scanners miss it); the
NixOS module is nginx-only against our Caddy fleet; the install wizard
fights declarative upgrades; and sabre/dav's CardDAV backend has no
read-only addressbook concept at all — the owner always has write, so
projection-only semantics are structurally inexpressible.

**Calendar on the phone: no standalone server, ever.** While Google is in
the loop the phone already sees the calendar through the Google app. Later,
the CLI self-serves CalDAV: `emersion/go-webdav` (already in the fork's
go.mod) ships `caldav/server.go` with a Backend interface; the repo layer is
the backend. Caveat (verified): the server half lacks `sync-collection`, so
DAVx5 full-syncs each pass — fine at personal scale.

**CRM contacts on the phone — endgame: self-serve CardDAV from the Go
binary**, `carddav/server.go` Backend (9 methods) directly over `crm.db`.
No materialized projection, no second copy, no drift — and read-only is
enforced structurally (`PutAddressObject`/`DeleteAddressObject` return
errors), stronger than any ACL file.

**Interim option, if contacts should reach the phone before the CLI
matures: Radicale** (nixpkgs 3.7.7, first-class hardened NixOS module,
drops into the Caddy `reverse_proxy` pattern). Fully specified by the
evaluation; the essentials:

- Direct file writes into its storage are a *documented contract*
  ("It is safe to access and manipulate the data by hand or with scripts"),
  guarded by `flock` on `.Radicale.lock`; external writes are picked up per
  request, no restart; external deletions surface as proper sync-report
  removals (don't wipe `.Radicale.cache`).
- Projection-only via the rights file: collection gets `r` without `w`;
  principal gets `R` only (blocks client MKCOL); global
  `permit_delete_collection/overwrite_collection = false`. DAVx5 reads the
  advertised privilege set and marks the addressbook read-only. Gotcha:
  the nix `rights` attrset serializes alphabetically and Radicale takes the
  first match — encode precedence in section names (`00-root`, `20-crm`).
- Auth `htpasswd`+bcrypt (DAVx5 wants Basic); run the projector as the
  `radicale` user via its own timer unit.
- Etags are content-derived (`sha256(serialize)`), so full deterministic
  regeneration causes zero client churn — provided `REV` derives from
  `contacts.updated_at`, never `now()`. Regenerate wholesale from one
  `LEFT JOIN`; org renames must re-emit all member cards anyway.

### vCard mapping (grounded in the real `pkgs/crm` schema)

`UID` = `urn:crm:contact:c<id>`; filename `crm-c<id>.vcf`; `FN` = name;
`ORG`/part of `CATEGORIES` from the joined org; `TITLE` = job_title;
`EMAIL;TYPE=work` (single-valued in schema); `TEL` from phone; `URL` from
linkedin (+org website), re-prefixing `https://`; `NOTE` =
`relationship_hint`; `REV` from `updated_at`; `X-CRM-REF` = `c42`.
**Never project the `context` column** — it is the mutable dossier, the
highest-PII field in the schema, and would land readable by every Android
app with `READ_CONTACTS`. Also not projected: interactions, deals,
provenance, contact_links; archived contacts are removed (file deletion =
proper sync removal).

### CRM schema additions while the surface is still malleable

**Deferred entirely (sealed 2026-08-10 evening).** All four candidates were
device-driven — phone opt-in consent, Android structured-name sorting,
Android caller-ID E.164 matching — and the device is out of scope. The
event↔contact linking contract (`X-CRM-REF:c<id>` resolved via the `crm`
CLI) requires no schema change. Revisit `given_name`/`family_name` only if
a local contact-card (vdir) export is ever actually wanted. Original list:

1. `contacts.projected` flag — explicit per-contact opt-in to the phone
   (biggest win, cheapest now).
2. `given_name`/`family_name` nullable columns — correct `N:` beats
   whitespace-splitting; Android sorts/matches on structured name.
3. E.164 phone normalization (`phone_e164` or normalize-on-write) —
   Android caller-ID matches on normalized numbers;
   `TryNormalizePhone` is deliberately permissive today.
4. (Only if pain appears) `contact_channels` table for multi-valued
   email/tel — today `email` is single and UNIQUE-among-live.

## Appendix: the vdir ecosystem (vdirsyncer / pimsync / khal / khard)

Verified findings (vdir spec diffed against Radicale source; compatibility
tested in both directions).

**The deciding fact: Radicale's per-collection storage directory already IS
a spec-conformant vdir.** One item per file, `.vcf`/`.ics` extensions,
atomic temp-file-then-rename writes — the only divergence is metadata
(`.Radicale.props` JSON vs the vdir spec's extensionless `displayname`/
`color` files). So "write a vdir, then sync it into the server" collapses to
"write the vdir into the server's directory." Compatibility gotcha if a
foreign vdir writer is ever pointed at Radicale storage: extensionless vdir
metadata files get listed as items and fail to parse — covered by
`storage.skip_broken_item = true` (already in the config above).

- **vdirsyncer as transport: no, on the current topology.** It would
  reconcile two directories on one host, adding a status database, a
  conflict model, and an emptied-storage safety abort (vdirsyncer#1099 —
  a CRM query returning zero rows wedges the pipeline pending manual
  `--force-delete`) to defend an invariant that `r`-only rights plus
  wholesale regeneration already guarantee. Upstream is in caretaker mode:
  substantive fixes ended late 2025 and the maintainer recommends the Rust
  successor **pimsync** (not yet at full parity; nixpkgs carries both).
  **The decision boundary is co-location**: if the exporter and the CardDAV
  server ever stop sharing a host, some network transport becomes
  necessary, and vdirsyncer/pimsync with `read_only = true` beats
  hand-rolled PUT/If-Match/diff-deletion. Decide placement explicitly;
  revisit immediately if they split.
- **khard: skip — and mildly hazardous.** A strictly lossier view of data
  the CRM CLI queries better, and its *editing* writes to a derived
  artifact the next projection run silently overwrites (data-loss trap).
- **khal: only if `ikhal`'s TUI is wanted.** It supports per-calendar
  `readonly = true` (nice symmetry with the ACL), but the forked
  the forked core reads the same directory natively, making khal a
  redundant read surface otherwise.
- **Design principle adopted regardless: the exporter emits a
  spec-conformant vdir** even when writing straight into Radicale's
  storage — same bytes, zero cost, and the directory becomes
  simultaneously consumable by the fork's local provider (its source
  explicitly matches "vdirsyncer collection layouts" — it can read
  `collection-root/tom/calendar/` **in place**, no sync layer), khal,
  khard, and vdirsyncer/pimsync if the topology ever changes. That is the
  decoupling vdirsyncer was considered for, obtained by writing conformant
  files instead of running a daemon.
- Android/DAVx5 is unaffected by any of these choices — it only ever talks
  to the CardDAV server over HTTP and neither knows nor cares how the
  files got there.

## Sealed rulings (Tom, 2026-08-10 evening — spec frozen)

The five parked decisions were ruled on paper and are final. This closes
scoping; implementation runs as a tally campaign against this document.

1. **Data location: XDG only.** ICS collections and SQLite index both under
   `$XDG_DATA_HOME`. Rationale (Tom's, adopted): the calendar is a merged
   projection of Google Calendar (outward-facing events, whose
   authoritative home is Google) and tally (regenerable from
   `query.producers` at any moment); people-data is already git-backed in
   `notes/crm/crm.db`, so notes-repo backing would buy churn, not safety.
   Two guards are part of the ruling: **(a)** `dcal add` defaults into the
   Google-backed calendar so no durable event exists only on this machine;
   **(b)** the ICS directory is a single config value, so at Google
   offboarding — when the local store becomes the record — relocation into
   notes is a config change plus committing plain-text files.
2. **Name: `dcal`.** Kept as-is from the fork.
3. **Radicale: skipped, permanently.** It was an inspiration repo; the
   desirable finding underneath it is the vdir principle (spec-conformant
   one-item-per-file collections on disk), which is adopted — see ruling 8
   and the appendix. No server component of any kind.
4. **No phone, no devices — struck from the design.** There is no phone in
   this setup at all; this is a NixOS desktop. Every device-projection
   provision (DAVx5, caller ID, phone-facing DAV) is out of scope entirely,
   and with no device consumer the self-serve go-webdav CalDAV/CardDAV
   endgame is dropped too (ruling 6).
5. **CRM schema additions: all deferred.** Every candidate (projected flag,
   structured names, E.164, contact_channels) was device-driven. No CRM
   migration in this campaign; `X-CRM-REF:c<id>` linking needs none.
6. **Naming (added 2026-08-10, late).** `dcal` is the only name. The
   upstream project's name — and any token containing the word "dank" —
   never appears in this repo, its issues, or the vendored tree: the Go
   module path is rewritten to `github.com/mecattaf/dcal`, upstream-named
   package dirs/files are renamed, and the tree is swept until
   `git grep -i dank` over `pkgs/dcal` returns nothing. Upstream
   attribution is satisfied by the MIT license text and the Avenge Media
   LLC copyright notice plus the pinned commit hash, which contain no
   forbidden token.

## Reference material

- `~/Downloads/dcal-upstream` — fork source (fresh clone, unmodified;
  directory renamed locally per naming ruling 6).
- `~/Downloads/Radicale`, `~/Downloads/Baikal` — evaluation clones.
- tally read path: `tally query producers` (JSON), RPC `query.producers`,
  docs at `tally.nix/doc/src/reference/rpc-protocol.md`; expansion via
  `systemd-analyze calendar`.
- CRM precedent: `dotfiles/pkgs/crm`, db `~/mecattaf/notes/crm/crm.db`,
  hook `CRM_POST_WRITE_HOOK` (see `pkgs/crm/docs/INSTALL.md`).
