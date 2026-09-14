# Handwriting annotation

The private front door is **https://handwriting.internal**. NAS AdGuard resolves
it to coordinator `10.42.0.2`; coordinator Caddy issues the same internally
trusted TLS certificate type used by `browser.internal` and forwards to
`127.0.0.1:8766`. The application is CPU-only. It starts no inference server.

`pkgs/handwriting-annotation` packages the Python application, Pillow and its
HTML interface. Its build runs the backend unit tests. The coordinator-only
`modules/handwriting-annotation.nix` declares the service and proxy. Sources are
copied from the reviewed prototype into the package before a deployment; the
running application never executes code from the prototype directory.

## Durable state and updates

`/var/lib/handwriting-annotation` belongs to `tom:users`, mode0700. Preserve the
whole directory: `tasks.json`, `resolutions.sqlite3` (plus live WAL/SHM),
`queue.lock`, and content-addressed `evidence/` snapshots. Imports add or enrich
items without erasing review events. The service only serves existing state;
it never seeds or resets the queue on startup. If `tasks.json` does not exist,
systemd skips startup until an explicit initial import is completed.

Import another compatible photographed collection explicitly:

```sh
handwriting-annotation --state /var/lib/handwriting-annotation seed --collection /path/to/collection
```

The served queue refreshes after an import. Do not replace the persistent
directory with a fresh prototype state during a code update. Do not copy an
open SQLite database file alone; use the application's snapshot command.

NixOS updates use the canonical `~/mecattaf/dotfiles` checkout, as required by
the raw-dotfiles guard. A deployment updates the coordinator application/proxy
and, when names change, the NAS DNS configuration. No client-specific hosts
file entry or public DNS record is needed. Clients already trusting the Caddy
CA for `browser.internal` use the new HTTPS site without certificate bypasses.

## Trailing correction history and offline use

Every save appends an event; revising or reopening a decision does not replace
its earlier entries. The history retains the literal reading, intended term
separately, handwriting note, tags, crop selection and label, time, previous
revision and source/image hashes. Immutable task and source snapshots provide
the original model reading and surrounding line. The website's **Export
resolution log** link downloads the complete event sequence as JSONL.

The log records every decision, including ones not approved for example reuse.
The example compiler uses only the latest writer-resolved, explicitly reusable
revision with a labeled crop. Reopening a decision or withdrawing reuse removes
it from future packets while preserving the historical record. Notes describe
observed handwriting patterns, not unconditional text substitutions.

```sh
handwriting-annotation --state /var/lib/handwriting-annotation export
handwriting-annotation --state /var/lib/handwriting-annotation compile --query 'joined rn' --exclude-page '2026-09-14/page1'
```

Compilation runs locally without inference or network access. It retrieves at
most three approved examples and prepares image/text data for a future Qwen
request. An empty packet is expected until relevant examples are approved.
JSONL alone references evidence: retain the snapshot's `tasks.json`, database
and `evidence/` alongside it for a complete offline bundle.

The daily OCR consumer is not yet connected to these packets. Saving a writer
decision currently neither calls Halogen nor rewrites the notebook nor trains
weights. Commissioning that consumer follows adjudication of this collection;
`/home/tom/huion/DAILY-OCR.md` records the remaining work.

## Existing NAS protection tier

The coordinator previously had no automatic copy of this new application
state. The annotation-specific daily timer now calls the application's
consistent snapshot command into:

`/mnt/nas/documents/handwriting-annotation-backups/<UTC timestamp>/`

The job requires the NAS NFS mount and refuses an unmounted local lookalike.
It never prunes snapshots. A successful snapshot includes the SQLite backup,
queue, evidence, exported events and checksum manifest. The NAS's existing
btrbk configuration includes the `documents` subvolume; its timer was checked
active/enabled during deployment. The house LaCie cold-mirror mechanism is a
separate tier; a successful annotation snapshot does not prove a new LaCie copy
has already occurred.

```sh
sudo systemctl start handwriting-annotation-backup.service
systemctl status handwriting-annotation-backup.service
systemctl list-timers handwriting-annotation-backup.timer
```

Restore into a **new local directory**, verify its manifest and database, and
stop the application before deliberately selecting restored state. Never
restore over the live directory without first preserving the current state.
The append-only review history is the authoritative writer annotation record.

## Access and service checks

```sh
systemctl status handwriting-annotation.service
curl --fail https://handwriting.internal/api/tasks
ssh client 'getent ahostsv4 handwriting.internal'
ssh client 'curl --fail --silent --output /dev/null --write-out "%{http_code}\n" https://handwriting.internal/'
```

The application accepts the configured private Host/Origin and loopback
addresses; POST additionally requires its session token. Caddy preserves the
Host header. The site shares the existing private LAN/tailnet ingress policy.
Serving an annotation page or saving a writer decision makes no GPU request.

## Deployment evidence — 2026-09-14

NAS and coordinator configurations were built and activated from the canonical
checkout. The installed package ran all 14 backend tests successfully; its
three source files matched the final reviewed prototype byte-for-byte.

From `client`, ordinary HTTPS returned HTTP 200 with certificate verification
result 0 (no insecure flag). The API returned 133 tasks and 34 image assets;
an image request returned HTTP 200 and 3,749,028 bytes. There were zero writer
review events at initial deployment. Browser interaction tests used separate
temporary state, not the live writer record.

The first managed backup completed at:

`/mnt/nas/documents/handwriting-annotation-backups/20260914T095328.587489954Z`

All 82 manifest checksums matched, all image evidence paths existed, and a
local copy of the backed-up SQLite database passed `PRAGMA integrity_check`.
The snapshot contained 133 tasks, zero events and 149,920,161 bytes. The daily
timer was active, with its first scheduled run on September 15 shortly after
midnight CEST. These are initial deployment observations, not a continuing
backup-health assertion.
