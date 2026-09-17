# DECISIONS

2026-09-17 the served kernel derives verdicts.

**The evaluator lock is BUILT, not pinned by hand (default, unruled).** No
ruling says where the served `--evaluator-lock` comes from, and there were two
ways to serve one: transcribe a generated `EVALUATOR.sha256` into this
repository as data (the way tally carries its own `ORACLE.sha256` locks), or
generate it in a derivation from the two inputs this repo already pins. Taken:
the derivation. `modules/tally-b.nix` runs the KERNEL's own
`${inputs.tally-b}/tools/make-evaluator-lock.sh` with `--root
${inputs.tally-lake}` at build time, so not one digest is typed here and the
lock cannot disagree with either pin without the derivation changing. The cost
is that reading the lock means building it (guard G3 now builds one small
derivation, offline); the gain is that a transcribed lock can rot silently
against a bumped input and a generated one cannot. The consequence to know: a
`tally-lake` bump CHANGES the lock, which changes the `evaluator.lock` cell of
every verdict derived after it — that is the point, a verdict names the bytes
that judged it, and it is why the lake is not in `rollingInputOverrides`.

**The locked argv is ONE store word.** `pkgs/tally-evaluator` wraps
`tools/e2e-evaluator.sh` so the argv the kernel hashes is
`<store path>/bin/tally-evaluator` rather than the two words the audit's probe C
ran (`/bin/sh <checkout>/tools/e2e-evaluator.sh`). A checkout path in a locked
argv is a lock over a file `git pull` can move; a store path is not. Everything
per-evaluation still travels on stdin — T7-3, and the only reason an argv can
be pinned at all. `node` is deliberately absent from the wrapper's
`runtimeInputs`: the stdin item names the interpreter by absolute path, because
the node the lake's `scripts/node-env.sh` records is the one its packages were
resolved against.

**Serving the lock changes nothing for the campaign.** The kit's `eval(...)`
entries stay `/bin/sh -c true` no-ops. `DEFERRED.md` `DF-U-D13-4` carries why:
what a mechanical verdict for CUBS IS is Tom's line (integration G7), and the
per-item stdin an `eval(...)` entry would need is the uplink render tool's
second step, not this module's constant `stdin` cell.

2026-09-13 flake checkouts no longer ride into host closures, chrome-stream
is installed, and a switch refuses a stale raw-dotfiles checkout.

Source coupling. flows/tally-flows.nix passed `./X.js` into tally's
types.path `script`/`catalog` options, which rendered as a path inside the
whole flake source, so every commit changed tally's checked config and
restarted tally-daemon at the next coordinator switch. Each script is now its
own `builtins.path` copy. Proved with a throwaway local-only DECISIONS.md
commit: coordinator, worker, client and nas toplevel drvPaths were identical
before and after it. Keep it that way: nothing that varies per commit
(`self`, `self.rev`, a bare `./dir` into a types.path option) goes into a host
closure.
(Integration note, 2026-09-14: #354's modules/update-adopt.nix, merged the
same night, deliberately puts the rev into every toplevel as
`system.configurationRevision` and `$out/fleet-revision.json`, because the
downgrade guard reads it. That is the one sanctioned exception: it reaches only
the toplevel file and nixos-version, no unit's inputs and no Home Manager
config, so a switch makes a new generation but restarts nothing. The rule
above still holds for everything a unit reads.)

chrome-stream (pkgs/chrome-stream) is in the overlay, `nix build
.#chrome-stream`, and installed by modules/browser-desktop.nix, so it exists
only where the shared browser desktop does, the coordinator. `home-profiles`
asserts it is absent from client, worker and nas (R-16).

#313, option 1. The raw-dotfiles anchor stays at ~/mecattaf/dotfiles, so
hot-reload keeps following that checkout; option 2 (anchor at the switched
flake) was a preference change and not taken. home/raw-dotfiles-guard.nix
runs before checkLinkTargets and writeBoundary and fails the activation when
a user unit's ExecStart/Pre/Post starts with `%h/.local/bin/<program>` and the
checkout lacks it; no checkout only warns. It is a presence guard, not a rev
equality: the worker and client checkouts lag main legitimately. The proposed
"store rev vs checkout HEAD" note was dropped because putting `self.rev` into
the generation would reintroduce the per-commit coupling above. The
`raw-dotfiles-guard` check pins each host's program list; adding a raw-program
unit means updating that list on purpose.

2026-09-13 two overnight hygiene calls, made without Tom and reversible.
(1) The SessionStart hook in home/dot_claude/settings.json is REMOVED, not
restored. It ran `~/.claude/hooks/herdr-agent-state.sh session`, a script
that exists in no repository and on no host, so it failed on every session
start and did nothing; DF-MEM-2-2 offered either answer, and removing a call
to nothing changes no behaviour. The ai-memory-harvest-hook check now asserts
there is no SessionStart block, so a hook naming an unshipped script cannot
return by accident. Restoring herdr's hook later is a new, reviewed addition
that ships the script beside ai-memory-harvest.sh.
(2) cliamp's resume.json carried a live Navidrome Subsonic token
(u=mecattaf, t/s pair; /rest/ping answered `ok` with it on 2026-09-13) and
has been tracked in this PUBLIC repo since 1600e2eb (2026-08-21). It is now
untracked and ignored, and ~/.config/cliamp is a real directory so it is not
written into the tree again. NOT done: rotating the Navidrome password
(re-encrypting navidrome-credentials) or rewriting history. The only
listener is tailscale0:4533, so exposure is limited to the tailnet. Rotation
stays Tom's call.
(3) 2026-09-14: docs/runbook-conventions.md does NOT carry #263's proposed
one-boot form `systemctl mask --runtime`. Measured on the coordinator, it
exits 0 and masks nothing on NixOS, because /etc/systemd/system (where the
store puts the unit) outranks /run/systemd/system. The one-boot form is a
runtime drop-in with a false Condition, which is merged from /run and does
take effect.

2026-09-13 UTIL-01 counts tokens from Halogen's journal, not from /metrics
(#312). llama-server and llama-swap are gone (2026-09-11 mono-model) and
Halogen's GET /metrics is a 404, but Halogen 0.7.0 logs one line per completed
request: `serve_api: mtp N tok in Ys … | prompt P (K cached), prefill Xs …`.
The worker's util-sampler (util-sample/3) reads that line from
`podman-halogen*.service`'s journal once a minute, chained by journal cursor
read back from its own log, and util-row (util-row/2) sums the windows per
arm. Calibrated the same evening on one request sent twice: P ==
`timings.prompt_n` and INCLUDES the cache, K == `cache_n`, N ==
`usage.completion_tokens` (reasoning included), prefill and decode seconds ==
`prompt_ms` and `predicted_ms`. So `tokens_in` is P − K (tokens actually
prefilled, what `llamacpp:prompt_tokens_total` meant), `tokens_in_cached` is
K, and `prefill_tokens_per_s` is (P − K) / prefill_s. Halogen's own
`prompt_per_second` does not discount `cache_n`
(peonist-ai/halogen-flash-server#48), so it is not used. A window that could
not be read is UNKNOWN, never zero; a day with holes grades PARTIAL, a new
grade. Not taken: a token-counting proxy in front of :8731, which would
put a new hop in every utility-model call just to count it.

Also decided: a token window is not an evidence event (DEFERRED
DF-UTIL-TOK-1; the card's own rule, only Tom widens it). The coordinator's
fara-browser-model llama-server (:8732) and the hand-run llama-server rows in
lib/local-models.nix are outside UTIL-01's SERVE_PROBES, so they get no
counter. `/home/tom/research-methods` stays read-only from here and drifted:
cards/UTIL-01.md still names /metrics and llama-swap in `tokens_source` and
locks older `instrument_sha256` values, and kits/util's fixtures pin
util-sample/2 and util-row/1. The digests locked in flake.nix's
`util-sampler-topology` and copied into `tools/u-d17-util-01-oracle.sh` are
this repository's; the card must be re-armed to them. The same re-lock
carries #329: a re-run of a closed night that reproduces its slice and row
byte-for-byte exits 0 and rewrites nothing, and a differing one exits 2.

2026-09-13 the coordinator switch of U-D19 (#322) was taken outside its PR.
It ran in the FIX-E order, through PRs #370-#378 and then a1329f8a (the
tally-b pin to b3a040e). PR #333 was closed, not ported: its
DECISIONS/DEFERRED text predated FIX-E06..E12 and #377. What the switch
delivered, measured 2026-09-13 on coordinator generation 215:
- tally-kernel.service active from /nix/store (…h006pvwl…-unit-tally-kernel),
  with ledger.jsonl on disk;
- tally-uplink.timer waking the oneshot uplink every five minutes (FIX-E12,
  #351), with Result=success and "0 messages still owed to the lake" since the
  tally-b pin. The 0600 lake-token was written by Tom;
- the seat-feeder, filler, pump and util-sampler/util-row timers, all with
  fragments in the store. TALLY_CLAUDE_SEATS=cc,cc2,cc3 is live, and
  cc/cc2/cc3.json are written every 30 s;
- claude-transcript-mirror units as Home Manager store links (the hand-written
  pair and their .hm-bak copies are gone);
- the ai-memory-harvest hook on disk and a SessionEnd block in the live
  settings.json;
- hk from /nix/store/wjbbi7n…-herdr-kitten-0.1.0-dev on both boxes.
Tom switched the worker; util-sampler.timer is active there.
l8-flash-probe reads 28/0 on the coordinator and 10/0 (10 SKIP) on the worker.
The llama-swap clauses of the U-D19 oracle are void since the 2026-09-11
mono-model entry. Twelve DEFERRED rows keyed on this switch were deleted
(#380), and DF-U-D14-3 now keeps only the `plan` half. The repository-half
oracles those rows name (tests/tally-b, tests/tally-uplink, tests/herdr,
tools/u-d18-filler-timer-oracle.sh, tools/seat-rows-oracle.sh,
tools/u-d17-util-01-oracle.sh) each run a full `nix flake check`, and three
also run `nix flake lock --update-input`. They are run once by the integrator
after the merge, not per lane. tools/u-d17-util-01-oracle.sh's SHA constants
now track the dotfiles re-lock rather than the card's instrument_sha256.

2026-09-13 fleet updates are adopted per host from signed NAS candidates
(#354). The NAS update-center, after each host's `attic push`, publishes
`http://nas:8734/candidates/<host>/manifest.json` + `.sig` (schema 1: host,
rev, last_modified, store_path, built_at), signed by the NAS SSH host key in
namespace `fleet-update`, swapped atomically; a failed host keeps its old
pointer. `update-center-publish HOST PATH FLAKEREF` publishes a closure built
elsewhere. Each device runs modules/update-adopt.nix: hourly stage (verify
against mesh-registry's NAS key, realise the exact store path from Attic, no
flake eval), activation every 30 min behind local gates, `switch` or — when
kernel/initrd/params differ from the booted system — `boot` with a
pending-reboot marker after 72 h (rebootPolicy notify, never an unattended
reboot), 10-minute probes, and a local rollback to the previous generation
that rejects the candidate and fails the unit. Busy, newer-local, manual and
unreachable-NAS outcomes exit 0 with receipts; `update-adopt status --json`
is the freshness surface.

Policies: worker rolling (gates: Halogen /health in_flight/queued and live
:8731 sessions, any active alternate); coordinator rolling (gates: any Herdr
agent not idle/done, fara-browser-model or browser-desktop active, a
tally-kernel row holder via rows.read, a live tally pool lease via `tally
query pools`) — shipped STAGE-ONLY until the worker's live downgrade refusal
is observed after deploy (DEFERRED DF-354-1), then one word flips it; client manual (R-18: discover and report only); NAS NOT
enrolled (2026-08-21 ruling stands: not built nightly, manual pinned bump).
Common gates: another rebuild running, free space, memory PSI.

Three safety rules came with it. (1) Every closure records its revision —
`system.configurationRevision` and `$out/fleet-revision.json` {rev, dirty,
lastModified} — and adoption refuses unless the running generation is clean,
recorded, and strictly older by commit lastModified than the candidate's own
file; hosts switched from a local checkout ahead of main, or from a dirty
tree, are never rolled back by a nightly (`update-adopt adopt --force` is the
override, which never skips gates). A consequence accepted: every commit now
changes every host's toplevel. (2) Herdr is never restarted by a switch:
home/herdr.nix sets `X-SwitchMethod=keep-old`, verified against the pinned
sd-switch 0.6.4 and home-manager 079a3b5 sources and asserted by the
herdr-oom-isolation check; a herdr bump now needs a deliberate `systemctl
--user restart herdr` (DF-CLIENT-7's stance). tally-kernel's restart policy is
unchanged; the lease gate covers it instead. (3) gc-retention never prunes the
generation at gcroots/update-adopt/last-known-good. (4) An activation never
undoes someone else's switch: if the system profile moves during the probe
window the verdict is `superseded` (rc 0, no rollback), and a switch that
outlives its wait is `switch-hung` (rc 1, no rollback racing it). Not taken:
Kubernetes, Proxmox, a fourth node, a second package-signing system, Tally as
the update scheduler.

2026-09-13 the NAS update-center gets private inputs by seeding, not by a
token. From 2026-09-10 every nightly build failed on `Failed to fetch git
repository 'https://github.com/mecattaf/tally'`: flake.lock pins tally-b
(mecattaf/tally) and tally-lake (mecattaf/tally-ts-sdk), both private, and the
appliance holds no repo credential. The coordinator's home-manager user timer
`update-center-seed` (home/update-center-seed.nix, 00:45 and 01:20) resolves
main with --refresh, selects every mecattaf-owned locked node, `nix copy`s the
narHash-addressed source trees to ssh-ng://root@nas as tom, and GC-roots them
at /var/lib/update-center/seeds/<node>, dropping roots the lock no longer names.
It skips while update-center runs. update-center's preflight logs
`seed-missing <node>` for any gap before building. MEASURED 2026-09-13 22:50:
with the trees seeded, a fresh-HOME root `nix eval` of pushed main's worker
drvPath on the NAS exits 0 — Nix uses a valid locked store path without
fetching — and the seed run as a transient unit exits 0, rooting herdr-kitten,
tally, tally-b and tally-lake. Not taken: a read-only GitHub token on the NAS
(breaks the no-repo-key doctrine) and pushing the trees into Attic (its
one-month retention would expire a pin that rarely moves).

2026-09-13 fleet status is a snapshot, not a monitoring stack (#356).
`fleet-status [--json]` on the coordinator answers "what is alive, busy,
stale, broken, waiting or unsafe to disturb right now" by running
`fleet-status-collect --json` on all four hosts over the existing root SSH
mesh. The collectors run in parallel with an 8 s deadline per node, and
partial results are allowed. There is no daemon, no timer, no exporter and no
database. Every fact carries its source, its observation time and a grade:
measured, unknown or missing-by-design. Each host's
/etc/fleet-status/profile.json (modules/fleet-status.nix) is what separates
"missing by design" (the NAS has no user manager) from "unknown" (a twin's
user manager did not answer). A node that is silent, dead or returns garbage
shows as TIMEOUT, UNREACHABLE or ERROR with no facts, and never as zero load.
The client is a laptop, so an UNREACHABLE client is an expected reading, not
a failure of the tool. pkgs/fleet-status/SCHEMA.md is the contract.

The planes keep their own authorities. Failures come from systemd,
bounded journald field matches and /var/lib/failure-markers. Update facts
come from #354's `update-adopt status --json` and stay unknown until that
verb is enrolled. Inference comes from the worker's Halogen `/health` and
podman-halogen units, plus the coordinator's FARA unit; llama-swap and
flashnext-lane no longer exist. Tally contributes unit states and IDs only,
for both planes: tally-kernel's ledger lease IDs and tally-daemon's running
job IDs. Herdr contributes agent states and per-pane age plus process-tree
RSS, and it reports the server's own RSS apart from herdr.service's cgroup,
because the cgroup holds every pane's descendants (#357).

Not installed for v1: Prometheus, Grafana, Loki, Cockpit or any always-on
store. Retention is revisited only when a real question needs history that
the journal and the failure markers cannot answer. When that happens, export
selected fields from this schema; do not rebuild it.

2026-09-13 Paperless v3 is live-gated on the NAS (#136): 3.1.3, no LLM index, no NAS AI.
`myNas.paperless.enable` and the coordinator's `myNasClient.relayPaperless`
flip together, and flake.nix nas-topology now asserts them ON. The first act
was a bump of the nixpkgs-paperless pin from 3.0.4 to 3.1.3 (nixpkgs-unstable
da39501c), made while the database is empty. Bumping after admission would be
the migration #136 forbids. The 3.0 to 3.1 module diff is harmless, but the
package changed its original checksum from MD5 to SHA-256. The bridge would
have died on every document, and now compares by digest length.

The rest of the #136 text is superseded by later rulings, and is read that
way:
- The NAS is not "8 GB, no Tailscale identity". It is 24 GB (MemTotal
  24027800 kB), a headscale node and the house router (hosts/nas/default.nix,
  2026-08-21 and 2026-09-01). Network acceptance is therefore:
  - 28981 is admitted only from 10.42.0.2 (the coordinator);
  - tailscale0 admits only DNS in the NixOS table;
  - no serve or funnel mapping and no Cloudflare path names Paperless;
  - `http://paperless.internal` via the coordinator relay is the one front
    door.
  It is not "the NAS has no tailnet node".
- There is no llama-swap and no 10.77.0.1; the /30 cable is retired (#264).

Router safety is part of the deployment. The NAS runs dnsmasq DHCP and DNS
for the house, so paperless-task-queue, paperless-consumer and the bulk unit
run at CPUWeight=20, Nice=10, idle IO and MemoryMax=8G. Paperless runs 1 task
worker with 2 threads. `paperless-bridge-bulk` has no wantedBy: an operator
starts it, or the separate `myNas.paperless.bulk.enable` timer does, which is
off. Before every round it stops, with exit 75 and a receipt, when:
- /mnt/nas has less than 150 GiB free (the disk was 94% full at the flip);
- the 1-minute loadavg is above 6;
- dnsmasq is inactive.
Every step is ledger-driven, so a stop or a reboot loses at most the
in-flight document.

AI is tag candidates only. `paperless-bridge suggest` runs on the
coordinator, because its utility-model wrapper is the fleet's accounted seam
to the worker's resident Halogen Flash. The NAS never dials worker:8731 and
never holds weights. Each suggestion writes:
- `ai-candidate/<slug>` tags, only for kind/topic/course slugs, with
  matching disabled;
- one note recording the served model id, taxonomy version and confidence.
A human accepts by retagging, and sync-tags exports that. Concurrency is 1,
so no model or process is left behind: the request lands on a server that
was already resident.

Paperless's own LLM/vector index stays off (`PAPERLESS_AI_ENABLED=false`).
Halogen has no /v1/embeddings (a POST returns 404), and AGENTS.md makes any
embedder an operator loan. The one-time index build is therefore not part of
closing #136. It happens after bulk convergence as an operator act:
1. `local-models-borrow` the Qwen3 text embedder;
2. run `llama-server --embeddings` by hand on the coordinator;
3. point Paperless at it, build the index, stop the server.
That act is carried as DEFERRED DF-136-1.

Enrichment follows the corpus as it actually is. The catalog key is
`local_pdf_path` in paper_archive plus historical_archive (3677 rows, 3627
files present). paper.md is resolved through ocr_derivatives or
ocr-june/papers-canonical/<db_id>/canonical/. A paper syncs only when every
recorded OCR source hash equals the ledger sha256. Measured against the real
catalog: 129 of the 184 OCR papers are syncable. The other 55 were OCR'd from
a different payload than the facsimile on disk and stay at baseline, each
with a receipt.

LaCie cold dump: the sync of documents/ excludes .paperless-view and
.paperless-consume. rclone does not keep hardlinks, so the projection would
otherwise land a second copy of the corpus. services/paperless/{backups,bridge}
(without the API token) is the one services/ tree that gets mirrored.

Permissions, found by independent verification before the deploy:
- /mnt/nas/documents is 0750 tom:users, and the paperless user is neither the
  owner nor in the group. It runs with the module's PrivateUsers=true.
- Two named-user ACLs fix reachability without group membership:
  `u:paperless:--x` on documents/ (so the consumer reaches its spool) and
  `u:tom:r-x` on .paperless-view (so the bridge, running as tom, can verify).
- Readability is a separate problem. Of the 8945 canonical PDFs, 3573 are mode
  0600, so Paperless cannot read their inode through any hardlink. The bridge
  parks them as `unreadable` rather than stalling bulk admission, and requeues
  them by itself once they become readable.
- Whether to widen those files (chmod o+r, or a per-file ACL) is Tom's call
  about private documents, not a Paperless decision: DEFERRED DF-136-3.
- Consumptions that time out park as `consume-timeout`, keeping their spool
  link, and are adopted when the document appears. Either way the queue head
  cannot jam.
- `suggest` pages through the corpus by id, so successive runs advance. On the
  coordinator it uses the default 127.0.0.1:28981, which is the relay socket;
  paperless.internal does not resolve on the coordinator itself.

2026-09-13 /print is one file write into `~/Paper/intake/`, and paper-daemon
owns everything after it (dotfiles#384). Tom's ruling of 2026-09-12: "you were
just supposed to be just placing a md file in a ~/Paper folder ... and the
printing daemon takes it from there". The agent writes `.<slug>.md.tmp` and
renames it to `<slug>.md`; optional front matter is `target_pages`, `sides`,
`profile`, `force`. The skill says that and where the outcomes land, nothing
else. The drop folder is `intake/`, not the issue's `inbox/`: the entry below
gave `inbox/` to the Huion and `intake/` to the print loop.

The daemon (pkgs/paper-daemon, units in home/paper.nix, coordinator only) is
the one submitter. It renders through print-auto.py, the utility-model
classifier plus print-paper.py's renderer, which is now render-only with
`--profile`/`--sides` overrides and no `--print`. It rejects a `target_pages`
mismatch into `rejected/`, holds 00:00–06:00 drops in `outbox/` for a
Persistent 06:05 flush, and requires the queue to be the pinned driverless
one before every submit. That means the DeviceURI is `ipp://10.42.0.4:631/ipp/print`,
driver options and the urf PPD filter are present, and the printer answers
and is not stopped. It repairs once by restarting ensure-printers and
records the repair.

A receipt (`printed/<id>/receipt.json`) is written only when the PRINTER's
own Get-Jobs says `completed` with `job-impressions-completed` equal to the
rendered pages. cupsd's "completed" is never trusted: job 303 was "completed"
and nothing came out. Anything else goes to `failed/` with IPP and cupsd
evidence, a failed unit and a notify-send on the client. MEASURED against the
HL-L2445DW: it rejects `which-jobs=all` and does not support
`job-media-sheets-completed`, so the receipt carries impressions, not sheets.

Taken with it: ensure-printers' postStart asserts the pinned URI and the urf
filter and deletes any leftover cups-browsed `implicitclass://` queue (the
worker still had one), and the retired flusher (pkgs/paper-intake, which
trusted `lp`'s exit code) is gone. Not taken: a readiness age gate. rename(2)
keeps the temp file's fresh mtime and the path unit fires once, so an age gate
would strand correct drops until the five-minute sweep.

The nine `2026-09-09-house-computer*.md` files that sat in `intake/` were
moved, not deleted, to `intake/.adopted-2026-09-09/`, which the daemon ignores.
They were NOT unprinted work: they are the sources of the 2026-09-09 print
run, with 27 job directories under `~/Paper/jobs/` (three with `"printed": true`,
the rest render iterations or `--submit-only` prints that never set the flag).
A watcher left facing them would have reprinted about 270 KB of Markdown.

2026-09-15 paper-daemon's queue guard no longer asks `lpoptions`, a sleeping
printer is waited for rather than repaired, and the client notify-send is
gone. The index-of-work drop failed at 15:05 as "raw queue, no PPD". The PPD
with the urf filter was on disk, cupsd served it, and the Brother answered IPP
at 10.42.0.4. MEASURED: `lpoptions -l` resolves the queue through Avahi before
it fetches the PPD, and the Brother's mDNS responder had gone mute. Both
avahi-browse resolution and a unicast query to 10.42.0.4:5353 timed out, the
Deep Sleep behaviour modules/printing.nix already records. The one repair
restarted ensure-printers and cupsd, which cannot reach the printer's mDNS.
After Tom power-cycled the printer, mDNS answered and CUPS job 314 printed with
a receipt.

So the raw-queue check is now the PPD file alone, and an unreadable PPD counts
as a problem instead of evidence. The printer probe retries for up to 90 s,
because an IPP connect wakes the Brother. Printer-side problems skip the
ensure-printers restart and fail as "printer unhealthy". The ssh notify-send
never showed anything: the client has no org.freedesktop.Notifications
service. A failed job leaves paper-daemon.service failed, which is what the
user-unit failure watcher (modules/failure-surfacing.nix) exists to surface.

2026-09-13 dictation on the client, transcribed on the coordinator (#376, route b').
Mod+Space on the client spawns `dictate-hold` (home/dictate-hold.py, installed
by home/client-apps.nix). It pipes the client's PipeWire DEFAULT source, so
whatever the Shift+F9 Audio Route picker selected, over ONE ssh session into
the coordinator's `voxtype-relay`. The relay arms the voxtype daemon with
`voxtype record start --file=PATH`, plays the audio into the `client-mic`
loopback, stops on EOF and prints the transcript back down the same session.
dictate-hold holds until evdev reports the release of Space or Mod (Esc or
Mod+Shift+Space cancels; a hold under 0.3 s is a cancel), then types the text
into THE projector it started in with `kitten @ send-text` (literal text,
never a bracketed paste). The kitty title reads REC while held and
"transcribing" after, which is the issue's spinner.

The model runs only on the coordinator. home/voxtype.nix is gated on the
hostName alone (no myDisplay coupling), the evdev hotkey and OSD are off, and
the unit is WantedBy default.target under linger with PartOf cleared.
PIPEWIRE_NODE=client-mic-source pins the capture. The client carries no voxtype
package, config, unit or model, and flake.nix home-profiles asserts it.

Batch TDT v3, not streaming. Measured with voxtype 0.7.5:
- streaming never honours `--file` (daemon.rs:915);
- batch mode on the old parakeet-unified model loads but returns "" for any
  input;
- parakeet-tdt-0.6b-v3 returns the fixture sentence verbatim, with about 0.2 s
  of warm inference.
Text is delivered on release anyway, so streaming bought nothing here.
post_process works again.

Why these shapes:
- A per-press user process, not a daemon. The 2026-09-13 thin-client entry
  keeps the Huion sync as the client's one standing runner. dictate-hold lives
  for a key hold, and python3-evdev sits only inside its writePython3Bin
  closure.
- ssh rather than a PipeWire tunnel. The same path works on the LAN and on
  headscale, needs no new firewall door, and keeps home/ssh.nix option (B): no
  ControlMaster, one connection per press.
- kitty remote control rather than `herdr pane send-text`. herdr's focus is
  server-global (`herdr pane list` reports one focused pane), so resolving
  "this projector's pane" from the coordinator is guesswork. The projector
  window itself always types into its own focused pane.

The `client-mic` loopback is a pipewire.conf.d drop-in, so it goes live on the
coordinator's next pipewire restart or reboot, not on the Home Manager
switch. The model download runs inside the unit's ExecStart, not ExecStartPre, so
the switch that first starts the unit does not wait on 2.5 GB (sd-switch's
120 s job timeout). It becomes the coordinator's default source, since nothing else there
is available; that is harmless on a headless box. DF-CLIENT-3 is removed.

2026-09-13 full herdr on the client; herdr-kitten leaves the fleet (#385).
The client's terminal is a herdr PROJECTOR: a kitty with app-id
`herdr-projector` running `home/dot_local/bin/herdr-projector`, which is
`herdr --remote coordinator --remote-keybindings server` in a loop. Every
herdr chord goes through `home/dot_local/bin/herdr-chord`, which types herdr's
own prefix chord into ONE projector window through kitty remote control:
Mod+Return is prefix+shift+n (a new workspace in the focused projector; with
no projector focused, the old workspace hop, a new projector, and a fresh
workspace in it); Mod+Ctrl+Shift+Return is prefix+b, herdr's sidebar with the
agents panel ("instrumentalizing herdr's own sidebar is VERY desirable"); and
Mod+Shift+N is prefix+shift+w, rename. Mod+Shift+Return stays plain kitty.
The chords live in the RAW binds.kdl; home.nix's client slot no longer
overrides them, and flake.nix `home-profiles` asserts both facts.

Why a projector again, reversing 186b36d2's `ssh -t coordinator
hk-new-inplace`. That spelling ran the herdr client ON the coordinator, and
herdr's clipboard-image bridge only exists in a `--remote` client
(src/client/clipboard_images.rs:66-73). A screenshot pasted from the laptop
therefore never reached Claude Code or Codex, and Tom ruled image paste and
image-file drop "important". 186b36d2's own requirement, "Mod+Return must give
me a NEW terminal", is kept by the chord, not by leaving the projector.
Keystrokes rather than the API because herdr's CLI focus is global: `herdr
workspace create --focus` moves every attached window
(server/headless/client_views.rs:857-863), and the sidebar, picker and rename
are client-local overlays with no API verb.

Reconnect is option (a), the wrapper. A plain `herdr --remote` exits 1 on a
lost link (client/errors.rs:62-71). The wrapper retries any non-zero exit with
1/2/5/10/30 s backoff while the window lives, stops on exit 0 (prefix+q or the
window's hangup), and on every child exit and on HUP runs `ssh -O exit` on the
child's `/tmp/herdr-ssh-<pid>-<n>/ctl` master and removes its
`/tmp/herdr-remote-<pid>-*` socket, which herdr's own Drop never cleans after
SIGHUP (remote/attach.rs:548-571). At start it also sweeps the leftovers of
dead projectors. Option (b), saved-machine federation with herdr's native
backoff UI, was not taken: `auto_detect_launch` spawns a LOCAL server when
none is listening (server/autodetect.rs:295-320), which breaks ruling B5 and
the thin-client rule. After a reattach the window lands on the server's
default target, not necessarily the workspace it showed.
Before every attach, first included, the wrapper asks the target over ssh
whether `herdr.service` is active and waits with the same backoff if not:
with no server listening, the remote `remote-client-bridge` spawns an
UNMANAGED server daemon (herdr src/remote/host_unix.rs:72), so an unguarded
retry loop would race a coordinator reboot and leave a second server
fighting the unit over herdr.sock.

herdr-kitten is removed fleet-wide, by Tom's ruling "herdr-kitten cannot cross
ssh boundary, then we will have to live without it entirely". Gone: the input
and its lock node, the package on all three hosts, the generated
`kitty-herdr-nix.conf`, the three `hk` kitty maps (ctrl+b now reaches herdr;
ctrl+g's fork gesture has no replacement; herdr's scrollback editor is
prefix+e), `hk-new-inplace`, `hk-resume-agents`, `checks.herdr-kitten-input`,
`tests/herdr/test-herdr-kitten-input.sh`, and voxtype's `hk voice` route and
spinner (#376, the entry above, then rebuilt dictation without them). `hk-prune-shells`
never used `hk` and survives as `herdr-prune-shells`. The zenbook plan's R-16
("the client carries no hk") is thereby implemented, by removal.
docs/herdr/herdr-kitten-input.md is kept as history under a superseded header.
The coordinator's herdr user unit is byte-identical before and after, so the
switch restarts no pane. DEFERRED rows DF-U-D15-1 and DF-CLIENT-4, -5 and -10
are deleted as moot. The sshd `ClientAlive*` question is DF-CLIENT-11.

2026-09-13 herdr topology (#309): ruling B5 stands — ONE herdr server, on the
coordinator; no second server on the worker or anywhere else. #309 set B5
against `~/research-methods/PROMPTS.md` §6 ("the herdr runtime and the
herdr-kitten home-manager module installed as units on both boxes"). §6 was
written against a measured ABSENCE — on 2026-09-05 `which herdr` was empty and
no herdr user unit existed — so that P09's batch would run on a herdr rail
rather than the systemd fallback. That motive is spent: herdr 0.9.0 is on PATH
on every interactive host and the server unit is active on the coordinator.
The worker needs no local rail: hosts/worker/default.nix says it is "not a
Tally executor or pool — all jobs still execute locally on the coordinator";
it is the Halogen node, and `systemctl --user is-active herdr` there reads
inactive. The client projects the coordinator's one server (#385), and #385
rejected saved-machine federation precisely because it would spawn a local
server on the laptop (herdr src/server/autodetect.rs:295-320 — contradicting
B5). The shape stays asserted, not deferred: flake.nix `home-profiles` and
`herdr-oom-isolation` require a `herdr` unit on the coordinator and none on
the worker or client. DEFERRED DF-U-D15-2 is therefore deleted.
~/research-methods/PROMPTS.md is a frozen prompt register in another repo and
is left as written. A second server needs a new ruling that also states
which sessions live where.

2026-09-13 the Huion Note X10 is the paper inbox; the client runs one sync.
Tom writes on the notepad anywhere, presses its button for each new page, and
opens the cover near the client; the pages land on the coordinator as
`~/Paper/inbox/<YYYY-MM-DD_HHMMSS>/page{N}-DD-MM.{svg,png,json}`. "the huion
IS the inbox" — `inbox/` holds nothing but these folders; printable markdown
stays in `intake/`, the print loop's. OCR is a later coordinator-side
consumer of `inbox/` and is not declared.

This is a deliberate, narrow exception to the client being a thin client
that runs nothing: the Bluetooth radio is on the client, so the client pulls
and pushes, and nothing else. hosts/client/huion.nix is the whole of it —
a patched bluetoothd (the extractor repo's att.c fix for the X10's duplicate
MTU request, still needed on 5.86), a udev rule that unbinds the notepad's
uhid device from hid-generic on every connect and wants huion-sync.service,
that oneshot (as tom) dumping into /var/lib/huion-sync/spool and rsyncing
to the coordinator, and huion-push.timer retrying the push alone. The
extractor is pkgs/huion-notes.nix, Reginleif88/huion-note-x10-ble pinned to
6f3f5e7, strokes thinned to 1.2 on its 900 px canvas (Tom's sample b).

The device is CLEARED as soon as a page is on the client's disk, not after
the push: the extractor cannot wait, so the spool is the durability buffer
and a down coordinator costs nothing but a delay. Tom asked for the
clearing ("this is indeed desirable"). Pairing is a one-time manual act and
already done; no permanent agent is declared (re-pair steps: the file's
header). Not taken: disabling BlueZ's input plugin, which would also take
the Duo's own Bluetooth keyboard.

Verified on the metal the same evening, closure deployed from the
coordinator with `--target-host root@10.42.0.16`: patched daemon running,
bond intact; 3 disposable test pages pulled, cleared and pushed; an empty
opening made no folder; page A, button, page B arrived as page1+page2 of
one folder; with `inbox/` made read-only the page stayed in the spool, the
device was still cleared, and huion-push.timer delivered it once writable.
Two quirks recorded, not solved: the first dump after the daemon restart
timed out (~37 s) and only the in-script retry succeeded — every later one
succeeded first try in 3–8 s; and a reopen can raise two HID instances a
second apart, which merge into one run. Two fixes came out of the
testing: huion-sync fails only when the dump fails (a failed push is
huion-push's state, which clears itself once the batch lands), and both
units are restartIfChanged = false after a switch killed one dump and
started another. Not run: a reboot followed by an opening. `nixos-rebuild switch`
does NOT restart bluetooth.service — a first deploy of a bluez change needs
`systemctl restart bluetooth` or a reboot.

2026-09-13 the client's dock carries no display; the PA27JCV never moved.
The 2026-09-11 entry below says "the PA27JCV moves to the client's
Thunderbolt dock". It did not, and the kanshi profiles written for it
(`DuoDock`, `DuoDockDocked`, matching the monitor by description string)
could never have applied. Tom's uncommitted note on that file (2026-09-12:
"there is a misnaming, it's NOT the asus pa27 it's a 14 inch display") is
what caught it, and the metal agrees: on the client DP-1, DP-2 and HDMI-A-1
all read `disconnected`, the Thunderbolt domain lists hubs, a NIC and
peripherals, and the only displays are the Duo's own two 14-inch panels,
eDP-1 and eDP-2. The two profiles are deleted, the note is folded into the
file's header, and where the PA27JCV physically is now is not recorded here.

Same day, thermald is off on the client, measured on the metal. The client
idles at 56–58 °C, inside the EC's fan hysteresis band — fan on at 58, off at
56, about 100 s on and 25 s off — and the band cannot be moved: the UX8406MA
exposes no fan-curve interface (asusctl's fan-curve verb aborts with a core
dump on it, which is what the coredump episodes of 2026-09-13 17:57 and 18:21
were — probes, not faults). thermald had nothing to act on below 103 °C, the
EC owns the fan, and it burnt 1 h 50 min of CPU in 46 h polling dead EC
sensors. Both 14-inch panels stay lit: a proposal to disable eDP-2 by default
for the heat was made and REJECTED by Tom the same evening — the bottom panel
is part of the seat, not a cost. Chrome was checked and left alone: its GPU
process already carries iHD_drv_video, so video decode is hardware.

2026-09-11 the coordinator is headless; no VNC in the fleet. This is the
"next one" the entry below promises — it reads "the coordinator goes fully
headless EVENTUALLY, not today, and not in this PR — the next one flips
niri/greetd off there in the worker's shape", and the consolidation plan
(docs/zenbook-duo-return-2026-09-11.md §8.3, sequence §10 steps 9-11) moved
"eventually" to "right after the seat is proven". NB: the ruling numbers in
the entry below are that entry's own, and they do NOT line up with the plan
document's — cite the two by content, never by number.

`myDisplay.enable = false` in hosts/coordinator/default.nix is the whole
flip. modules/display.nix's option (default true, because the fleet-wide
greetd→niri session in modules/common.nix is derived from it and the
exceptions opt out) drives the compositor, the greeter, and the
display-bound user services; so voxtype and piri leave the coordinator BY
DERIVATION, with no per-file gate to remember. Deleted outright, not
commented out: home/remote.nix — the whole module, wayvnc unit and config,
the Remmina package and the generated .remmina profile — and the :5900 door
in hosts/coordinator/tailscale.nix. Nothing serves VNC and nothing views it:
there is no VNC in this fleet. The flake's home-profiles check asserts every
one of those as an equality against the option, so the flip and the
deletions cannot be separated in a later commit.

What KEEPS its coordinator gate: the dcal daemon and the coordinator-only
package extras in home/home.nix (around :93 and :562). Those are CLI tools
that happen to be installed on one box, not display things, and the plan
says so (§8.3). What does NOT come back: the dual-5K desktop is retired in
full — the PA27JCV moves to the client's Thunderbolt dock and the second 5K
panel is retired, which is what made the flip cheap in the first place.

The casualty, recorded not solved: DICTATION. voxtype typed into the focused
window of the session that just went away, and the client has no dictation
row yet. It is deferred, not deleted.

Why tonight and not "eventually": the 2026-09-11 21:00 boot. The coordinator
was powered on with no monitor after a move; greetd autologged tom into niri
at 21:00:37 and pam logged "gkr-pam: couldn't unlock the login keyring" (an
autologin has no password to unlock it with), polkitd came up for that
session a second later, and when a display was plugged in the session was
sitting on a password dialog that nothing on the client could answer. Tom
typed the password; it changed nothing (the network hole of that same boot
was the uplink's, fixed separately in PR #371). That prompt is display-bound
by construction: with greetd and niri off nothing autologs in, nothing tries
to unlock a keyring, and nothing prompts. The seat was proven from the client
the same evening (Mod+Return projecting herdr through ssh), so the gate the
prepared commit waited on is green.

Operator acts a switch cannot perform, in order:
(1) drive `sudo nixos-rebuild switch --flake .#coordinator` from the client
    — it was driven from inside Tom's herdr session over ssh, by the agent
    running there. After the flip the coordinator's only inputs are ssh and
    a blind VT getty, so the seat has to already be working;
(2) herdr is deliberately NOT restarted at the flip: the running server
    still carries the WAYLAND_DISPLAY of a session that is gone, which is
    harmless until the next boot clears it, and restarting it would kill
    the very session the switch was driven from. `systemctl --user
    unset-environment WAYLAND_DISPLAY DISPLAY` then `systemctl --user
    restart herdr` remains the recipe if a pane needs the clean environment
    before a reboot (plan §6.1; the restart kills live panes and herdr's
    `resume_agents_on_restore` brings the agent conversations back);
(3) unplug DP-1 from the coordinator and plug it into the client's dock;
(4) `ss -ltn | grep 5900` on the coordinator — expect nothing.

Keep a keyboard and a monitor within physical reach of the coordinator until
all four are green: the VT getty is still there, and it is blind.

2026-09-11 the Zenbook Duo comes back as the thin client. The ASUS Zenbook
Duo UX8406MA is reclaimed from Marwan the same afternoon its Omarchy install
was ready ("i want to see my omarchy-less asus zenbook ready for action asap
now") and re-enters this tree as `client` — flake node, networking.hostName,
mesh-registry row, agenix recipient, deploy node, ssh nickname, one name, no
`zenbook` alias. The rulings, numbered so the host module and the flake's
checks can cite them:
(R-1) the coordinator stops being the main input device; the Duo is it.
(R-2) it leaves omarchy-fleet/omarchy-nix (Hyprland + Quickshell) for niri,
kitty and the ~/.local/bin scripts of this tree; Tom is not using Omarchy.
(R-3) the coordinator goes fully headless EVENTUALLY, not today, and not in
this PR — the next one flips niri/greetd off there in the worker's shape.
(R-4) the dual-5K desktop is retired; only DP-1 stays connected until then.
(R-5) the Duo is a THIN CLIENT: compositor, kitty, the clipboard bridge
(cliphist, wl-clipboard), Chrome, the Duo hardware layer, PipeWire and bolt
for the dock. NOT on it: the herdr server, tally, the halogen client, the
microVM host, caddy artifacts, the printing queue, the atuin server, voxtype,
a wayvnc server, the dcal daemon, journal upload, immich, any model tooling.
Every one of those is now host-gated or forced off, and asserted.
(R-6) the two crucial seams are clipboard control across ssh and effortless
kitty ssh into coordinator sessions: Mod+Return on the client is
`kitty -e hk ssh --in-place coordinator` (tier 1, herdr --remote); `desk`
is the fish spelling. Clipboard beyond what herdr --remote carries (OSC 52,
focus-gated) is a follow-up.
(R-7) the coordinator's USB peripherals move to the Thunderbolt dock; the
iContact webcam mic's WirePlumber pin moves with it (hosts/client/audio.nix,
the coordinator copy deleted). The MediaTek dongle is the coordinator's
Bluetooth controller and stays. Untested until the dock is plugged.
(R-8) Chrome is the one real local app on the client AND stays on the
coordinator (fleet-wide package).
(R-9) VNC: nothing beyond today — the coordinator serves, the client views
(`coordinator (VNC)` Remmina profile, registry-driven).
(R-10) stock niri's one-output touch mapping is an ACCEPTED defect: global
`touch { map-to-output "eDP-1" }` in the client's niri-local.kdl; no PR #1856
fork, no ntm, no rotation today.
(R-11) binds.kdl carries over in full; per-host differences go ONLY through
niri-local.kdl and kanshi profiles (`Duo` exists, nothing added). F10 on the
client is brightness-to-zero (brightnessctl -s … set 0 / -r), the daemon
syncing eDP-2; the sleep-monitors popup stays on the coordinator.
(R-12) hostname `client`, everywhere.
(R-13) the ssh host key omarchy-fleet minted on 2026-09-07 is REUSED, never
rotated: that is what makes the return an in-place switch.
(R-14) install path is an IN-PLACE SWITCH from the coordinator
(`nixos-rebuild switch --flake .#client --target-host root@10.42.0.16
--build-host localhost`, or the closure copied and switched detached from
the ssh session when wifi re-association would kill the switch mid-way),
then a reboot; disk, host key, /var/lib/tailscale* and the NM profiles are
kept, and the Omarchy generation stays in the boot menu as the rollback.
(R-15) the seat is the fleet-wide greetd autologin → niri as tom; no SDDM.
(R-16) rail: on the LAN nothing but the LAN. services.tailscale is declared
with the NAS headscale control URL and NO auth key, no autoconnect, no `up`;
the node state on disk is kept and re-login is a later manual act. Headscale
node 4 (`zenbook-duo-fleet`) is not deleted.
(R-17) hardware carried from omarchy-fleet: initrd vmd/thunderbolt/mei+i915,
kvm-intel, microcode, the nixos-hardware Intel laptop trio, i915.enable_psr=0,
the no-RTC e2fsck + emergency-shell + timesyncd trio, intel-media-driver +
iHD, the dock daemon (modules/zenbook-duo-daemon.nix), asusd + /etc/asusd +
thermald, the asus_screenpad backlight unit masked, upower PowerOff at 5%,
iio, disko matching the live layout. DROPPED: the 7.2.4 kernel pin + vmd
MTL016 patch (kernel build not today; the intermittent VMD boot stall is an
accepted wait — follow-up), the Intel NPU firmware (AGENTS.md decommission),
the Hyprland-only rotate module, every omarchy.* option, docker.
(R-18) update path: the client is in the NAS nightly BUILD list only; it is
never pushed to or activated by anything but Tom's own
`sudo nixos-rebuild switch --flake github:mecattaf/dotfiles/main#client`,
docked on the LAN, coordinator first whenever herdr is bumped.

Two things this ruling set found on the way and decided: (a) the NAS
resolver serves no DHCP client names, so "client by name only" needed an
address after all — the lease the NAS already hands the laptop's MAC
(10.42.0.16) is pinned in hosts/nas/router.nix, carried as a registry alias,
and written into the twins' /etc/hosts by modules/fleet-hosts.nix; (b) the
worker leaves wifi-lan.age's recipients in the same rekey that admits the
client, discharging this morning's operator act (4).

This supersedes the same-day "ONLY the coordinator has a display output"
line above and in hosts/worker/default.nix: two hosts have a compositor now
(coordinator and client), the worker still has none, and one host serves
VNC (the coordinator).

Operator acts this leaves open, none performed by a switch: (1) on the
client, once the declarative thomas-6ghz profile has associated, delete the
hand-delivered keyfile omarchy-fleet left —
`rm /etc/NetworkManager/system-connections/thomas-6ghz.nmconnection` and the
`Freebox-64238A` one — and the `docker0` bridge profile; (2) plug the dock
and run the R-7 checks (`boltctl list`, `wpctl status`, `amixer -c Pro sset
Mic 36% cap` once); (3) `/home/marwan` (817M) is left in place on the
laptop, not deleted; Tom decides; (4) the NAS switch that makes the dnsmasq
lease pin, the nightly client build and the xps-only publisher live — until
then `omarchy-update-publish` must be given `--devices xps`; (5) the manual
`tailscale up --login-server=https://nas-saas.tail8dd1.ts.net:8443` on the
client if it should ever leave the LAN; (6) dictation: the coordinator has
no mic once the webcam moves, voxtype there is deaf — route undecided;
(7) the omarchy-fleet `retire-zenbook-duo` branch (no remote) is merged by
hand; (8) a `DuoDocked` kanshi profile, because with the keyboard docked
only eDP-1 remains and kanshi falls through to `Laptop` (scale 1.5, written
for the Dell XPS).
2026-09-11, later the same day: the Thunderbolt residue goes too. The earlier
entry below kept "the stock `thunderbolt` driver and bolt ... for ordinary USB4
peripherals"; that clause is SUPERSEDED. Tom's ruling is that no Thunderbolt
reference survives on either twin, so `services.hardware.bolt.enable` is gone
from modules/common.nix and its now-dead `mkForce false` from
modules/headless.nix. boltd no longer runs anywhere in the fleet. CONSEQUENCE,
recorded so it is not a surprise: a USB4/Thunderbolt dock or enclosure plugged
into the coordinator is no longer auto-authorized by a daemon. The stock
in-tree `thunderbolt` kernel module still loads in stage 2 — it is nixpkgs's
default and not ours to strip — so a device can still be authorized by hand
through sysfs. Reinstating the daemon is a one-line revert if a dock ever
needs it. The initrd module lists are untouched in substance; only the
comments naming the bus are removed.

Same act closes open act (3) of the entry below: hosts/nas/router.nix now pins
`worker` by its WIRED 5GbE MAC 9c:bf:0d:01:cc:65 (enp191s0) instead of the
idle wifi MAC 44:f7:9f:da:bd:1d, which could never have matched. The pin is
belt-and-braces — the worker sets 10.42.0.5 statically and .5 sits below the
DHCP pool — but it reserves the address and keeps the name stable.

Three docs that still read as live Thunderbolt runbooks, and cite config files
this branch deleted, are stamped historical rather than erased:
docs/usb4-pd-wedge-2026-08-21.md, docs/local-ai/ds4-vllm-recon-2026-08-21.md
and docs/local-ai/wanted-packages/rail0-has-no-hostname.md. The dated incident
record and the measurements are worth keeping; presenting them as instructions
is not. The standing "not to be reintroduced" guards in AGENTS.md and
docs/nas/router-rewire.md deliberately KEEP the word Thunderbolt — naming the
thing is how they stop it coming back — and this log is append-only, so its
own Thunderbolt mentions stay as history. Unremovable residue: flake.lock
carries a `thunderbolt-ibverbs` input and a westeri/thunderbolt.git kernel
source, both TRANSITIVE inputs of the third-party hellas-ai/nix-strix-halo
flake. Nothing in our flake.nix references them; they leave only when upstream
drops them or we drop nix-strix-halo.

2026-09-11 mono-model on Halogen. llama-swap is removed from every host, and
with it the deployment layer: no proxy, no roster, no per-model command
renderers, no backend kinds, no `services.local-models.allow`, no port 9292.
The fleet's one inference server is Halogen Flash — Qwen3.8-Flash-Next in
Peonist's .hgn format, served by the closed-source
ghcr.io/peonist-ai/halogen-flash-server image (pinned by digest, release
0.5.6) as a podman container on the WORKER (modules/halogen.nix), OpenAI-
compatible on http://worker:8731, vision included so OCR lives there too. The
launch shape is lifted from kyuz0/ai-toolbox-cockpit's halogen backend rather
than waiting for hellas-ai/nix-strix-halo to package it. The coordinator
serves nothing; its `utility-model` wrapper (what /drain and /print call)
forwards to the worker's Halogen. The catalogue is cut to fifteen artifacts:
the Halogen bundle, qwen3.6-35b-a3b, gemma 4 12b (+ MTP head), fara 1.5 9b
(+ projector), the two embedding models, the three VibeVoice speech rows and
the three Mage rows. OUT, and not to return: every dual-node model
(flashnext-fp8, deepseek-v4-flash, the GLM 5.3 ciru shards, the ciru IU4
reference), every dense big model (qwen3.8-27b, qwen3.6-27b, gemma4-31b,
fara 27b), the qwen3-vl OCR pair, the uncensored candidates, ornith, muse
glimmer, the retired FLM rows; flashnext, flashnix and the vLLM fork are
defunct projects. Bulky providers leave the flake outputs too: ds4-rocm,
vllm-rocm, mlx-lm, mlx-rocm, tokenizers-cpp. Kept: llama.cpp ROCm/Vulkan
(an operator serves the small GGUFs by hand), stable-diffusion.cpp, amdtop.
The NAS Library, `local-models-borrow` and `local-models-prune` keep their
doctrine unchanged; per-host wanted sets shrink to the worker's one bundle
and the coordinator's five small files, and both boxes' working copies are to
be pruned to exactly that.

Same day, addendum: a second Halogen engine, halogen-server with Qwen3.8-27B
(35.9 GB, image ghcr.io/peonist-ai/halogen 0.1.3 by digest), is declared on
the worker as `services.halogen.alternates.qwen38-27b`. The two cannot be
resident together on 128 GB, so the units carry mutual Conflicts=, only Flash
starts at boot, both answer on :8731, and `halogen-switch <flash|qwen38-27b>`
is the operator's way between them. Flash is the everyday model.

Operator acts this leaves open, none performed by a switch: the NAS Library
must hold the Halogen bundle before the worker can borrow it (library-fetch
on a switched NAS, or the same download by hand into
/mnt/nas/models/weights/halogen-qwen38-flash-next/); on the worker, after its
switch, `local-models-prune --yes` then `local-models-borrow --yes`, then the
podman-halogen unit's first start pulls the image; on the coordinator,
`local-models-prune` down to the five small files, at a time of Tom's
choosing and after its own switch.

2026-09-11 the twins are LAN peers and nothing more. The worker moved to
another room and is wired into the BE550's Ethernet port 2 at its static
10.42.0.5; the coordinator stays on thomas-6ghz at .2. There is no Thunderbolt
cable, no direct 5GbE cable and no 10.99.x rail between them, and Tom has no
interest in the Thunderbolt work returning. Deleted outright, recoverable only
from git history (last carrier 681459f5): hosts/coordinator/tb-fleet.nix and
eth-fleet.nix, modules/fn-rdma.nix, usb4-stream.nix, lowlat-cluster.nix and
fleet-rail-names.nix, the worker's twin heal loop and rail profiles, and the
10.99.9.x fleet identities. Names resolve to LAN addresses on every host
(modules/fleet-hosts.nix on the twins, hosts/nas/network.nix on the NAS), the
deploy node and the ssh nickname dial `worker` by name, and the mesh registry
carries one alias per twin. The stock `thunderbolt` driver and bolt stay for
ordinary USB4 peripherals; only the fleet's use of the bus is gone.

Same day, same ruling set: ONLY the coordinator has a display output, so only
it runs a compositor. The worker's greetd→niri autologin is forced off, its
synthesized-EDID headless-display.nix is deleted, and home/remote.nix renders
no wayvnc on a host whose niri is off. Home Manager stays on the worker. And a
standing constraint for the whole procedure: NO reboot of the coordinator
until it is done; the worker may reboot as needed.

Operator acts this leaves open, none of them performed by the switch:
(1) on the worker, after its first switch onto this closure, delete the
NetworkManager profiles the flake stopped ensuring — `nmcli connection delete
thomas-6ghz tb-fleet tb-fleet2 eth-fleet` — or the stale wifi profile keeps
10.42.0.5 on wlp192s0 beside the wired one; (2) on the coordinator the same for
`tb-fleet tb-fleet2 eth-fleet`, plus `rm -rf /var/lib/flashnext-rdma
/var/lib/tb-link-heal /var/lib/usb4-stream` and the stale failure markers
`tb-fleet-reachability`, `tb-rail2-reachability`, `eth-fleet-reachability`
under /var/lib/failure-markers; (3) hosts/nas/router.nix still pins `worker` to
the box's WIFI MAC (44:f7:9f:da:bd:1d) in dnsmasq's dhcp-host list — harmless,
since .5 sits below the pool, but it should be re-pointed at the Ethernet MAC
once the box is reachable (`ip link show enp191s0` there; it answered nothing
at .5 and held no lease when this was written); (4) the worker's recipient on
secrets/wifi-lan.age is now unused and can be dropped at the next rekey.

2026-09-10 model-byte doctrine: a NixOS evaluation, build, switch, boot, or
service start must never download, copy, verify, prune, mount for, order after,
or wait for model weights. The NAS Library at `/mnt/nas/models/weights` is the
canonical collection. Internet acquisition terminates there via the independent
`library-fetch` timer or an explicit operator start. Worker and coordinator
working copies are optional loans made only by an operator invoking
`local-models-borrow --dry-run` and then `--yes`; the command preflights the
whole declared byte count against free space, verifies each file, and lands it
atomically. Existing working copies remain in place. Deletion remains a separate
guarded `local-models-prune --dry-run` / `--yes` transaction. A missing model may
make that model unavailable when requested; it may never make an OS update fail.

2026-09-06 orchestrator B: merged U-D5, U-D8 to main under the handoff's merge authority; gate ["bash", "/tmp/claude-1000/-home-tom/f9d7af0b-e4f1-476b-b2b2-5c58c365fdaa/scratchpad/gate.sh"] = nix flake check --offline --no-build + tests/local-models-sync/test-prune-guard.sh (LOCAL_MODELS_PRUNE_BIN) + claude-capacity case count vs docs/local-ai/claude-capacity.md; rc 0; receipts under /home/tom/research-methods/receipts/FACTORY-2026-09-06/.

2026-09-06 U-D16 (dotfiles#319): the manifest's DOMINANT oracle for the l8-flash
reconciliation is prose naming four clauses, so it is mechanized as ONE argv —
`bash tools/u-d16-l8-flash-oracle.sh` — and the two lines the prose left open
are decided here.

(1) **Ancestry is checked against `HEAD`, not against the local `main` ref, and
the branch head is pinned as a sha rather than resolved from the `l8-flash`
ref.** The oracle is re-run by the evaluator from a fresh worktree; a ref is
local to a clone and can be moved, and "after the PR merges" means the commit
the evaluator stands on. `e549ba911e8d8c9ff1c19b4fa9b0b6df45244f7f` is what the
reconciliation is about.

(2) **The oracle gates the repository half of "the hand-written
claude-transcript-mirror units are removed" and reports the shell half without
gating on it.** The removal is Tom's own act by `~/sept7/scopes/clean-dotfiles.md:171`
§6 and is step 4 of the P05 walkthrough, sequenced inside U-D19 (D-B15: the
coordinator switches under U-D19, the worker's switch stays a TOM LINE); until
that switch the hand-written pair is the only working mirror, so an oracle that
went red while the files existed would be demanding this unit break the mirror.
Gated: the declaration on `main`, no plain unit file tracked, and the
`l8-flash-probe` row asserted in the flake in four states. Reported as `NOTE`:
the files' state on this box. Carried as `DEFERRED.md` DF-U-D16-1.

Also decided: content closure (`tools/u-d16/`) is part of the oracle, because
ancestry alone stays green under `git revert` of any of the 30 commits, which is
one of the two readings of the unit's `mutation_hint`. Both readings measured
RED at `020b2ad1`.

2026-09-06 U-D12 (dotfiles#315): three implementation lines were open between
the issue's per-row wording and its DOMINANT/scope, and are fixed here.

(1) **The three declared timer+service pairs are the three named instruments,
not five independently clocked row files.** They are
`tally-seat-feeder-{claude,codex,pi-qwencloud}`. The Claude invocation writes
the `cc`, `cc2`, and `cc3` rows independently; separate JSON files and reset
clocks preserve D-B5's two-pool ruling. This follows the acceptance's exact
"three timers declared" and the scope's exact "three timer+service pairs";
`X-TallyRows` on each service makes the grouping evaluated data rather than a
comment.

(2) **The fixture's admit witness is `codex`, read by name through U-B10's real
`tally-admit`.** It is below the soft ceiling in the fixture, so removing its
timer makes the very next probe unambiguously SLOW `stale_observation`. An
UNKNOWN row is rejected by the meter decoder before a Decision carries age;
those rows' source timestamps are checked separately over the same 60 ticks.
The fixture refuses to substitute a second admission implementation.

(3) **D-B54 supersedes the original source-time line: the row observation is
stamped at publication, after the read.** A reader's timestamp remains source
metadata only. In particular, `stamp-receipt.py window` may return its bounded
cache during a 429; the feeder turns that into a current UNKNOWN read naming
the cached source time instead of re-labelling old numbers as fresh MEASURED. A
Codex `rate_limits` record missing any of `used_percent`, `window_minutes`, or
`resets_at` becomes a fresh UNKNOWN row. `pi-qwencloud` declares no `window`
cell at all: absent means UNKNOWN, while `kind: none` would falsely describe a
non-spendable device.

(4) **D-B54's duration term is an enforced envelope, not a nominal runtime.**
The three 12-second Claude reads run concurrently and publish independently;
the unit fails at 20 seconds. With the 30-second period and one-second timer
accuracy, the worst permitted age is `30 + 1 + 20 = 51 < 60` seconds. The
fixture advances services through that full duration and admits during runs.

2026-09-06 U-D17 (dotfiles#320): the manifest's DOMINANT oracle for the
`util-01-sampler` reconciliation is `PR #314 merged (gh pr view 314 --json state
== MERGED); nix flake check --offline --no-build → 0`. It is mechanized as ONE
argv — `bash tools/u-d17-util-01-oracle.sh` — following U-D16's entry above, and
the four lines the prose left open are decided here.

(1) **`main` is merged INTO `util-01-sampler`, not the other way round, and no
new branch is cut.** The issue's own completion condition is `gh pr view 314`
reading `MERGED`, and PR #314's head is `util-01-sampler`; a new branch off
`main` that merged the two commits would land the same content and leave #314
OPEN forever, failing the oracle it was written for. `~/sept7/scopes/clean-dotfiles.md:202`
says "a new branch off `l8-flash`" because it was written while `l8-flash` was
still unmerged; `l8-flash` reached `main` at `ecc6a228` under U-D16, so the base
it names and `main` are now the same tree. The motion is `ad8a9119`'s either
way: a branch merged into the one switch, its commit count and issues in the
message, history preserved — `981e8d01` is carried, not squashed. Merge
authority: `~/research-methods/DECISIONS.md` D-B12.

(2) **`gh pr view 314 --json state == MERGED` is literal and cannot be
substituted by tree ancestry.** The issue says the generation-4 DOMINANT is
byte-exact. Clause 1d therefore passes only on `MERGED`; `OPEN`, `CLOSED`, an
unavailable `gh`, and a failed lookup all fail. Clauses 1a–1c remain additional
topology checks in the form U-D16 decided (ancestry against `HEAD`, never the
local `main` ref; commits pinned as shas): `34a613dc` and `981e8d01` must be
ancestors, the range must still contain exactly those two commits, and main at
the reconciliation (`ecc6a228`) must also be an ancestor. They establish the
history-preserving merge but do not stand in for GitHub's state. Because this
unit is expressly barred from merging its own PR, the implementer's required
DOMINANT run is expected to be red on clause 1d; the complete oracle can first
turn green on the evaluator's post-merge run.

(3) **A conflict-marker grep (clause 5) is part of the oracle**, because the
flake check alone cannot see the whole mutation. MEASURED at `120812a7`: a
marker in `home/home.nix` turns clauses 4 and 5 red; the same marker in
`home/dot_local/bin/l8-flash-probe` leaves clause 4 **green** — nix never parses
that file — and turns 3b and 5 red. Two readings of the same
`mutation_hint`, both RED.

(4) **The two new `l8-flash-probe` rows check `FragmentPath` and nothing else,
and there are exactly two.** `is-active` is not checked: `OnBootSec=1min` and
`OnCalendar=*-*-* 00:05:00` make a box rebooted a minute ago indistinguishable
from a box that never switched, while `FragmentPath` separates them the instant
the unit exists. The count is the issue's own requirement — pre-switch the probe
must exit 1 with exactly these two additional FAIL rows and the same PASS rows
as before — so it is asserted in
`tests/l8-flash-probe/test-util-timer-rows.sh` rather than left to reading.
Both rows ship RED and are carried as `DEFERRED.md` DF-U-D17-1.

Also decided: the eval-time flake check `util-sampler-topology` is part of the
gate rather than beside it, because `nix flake check --offline --no-build` on
its own only proves the merged tree EVALUATES and would stay green through a
resolution that dropped `./util-sampler.nix` from `home/home.nix`'s imports. It
asserts the unit's non-goal as bytes — `builtins.hashFile` over both programs
against `cards/UTIL-01.md` `instrument_sha256` — plus the timers per box,
`Persistent` on each, `tally` on the coordinator sampler's PATH alone, and the
one tmpfiles rule.

2026-09-06 U-D15 (dotfiles#318): the `herdr-kitten` input moves BOTH its rev and
its URL form — `git+file:///home/tom/mecattaf/herdr-kitten?rev=41a6de5` becomes
`github:mecattaf/herdr-kitten/ccc16393cc35e2cce2b8cd9a55718b3c84849a8f` — and
three lines are decided here.

(1) **The `github:` form is taken, not deferred, because the Tom line that
barred it has been TAKEN and recorded.** The first attempt at this unit
(`receipt-parked-tomline9.json`, verdict STOPPED, branch head `25bf1dc9`)
moved only the rev and deferred the URL form behind the herdr-kitten survey's
**Q-7** — *"The repo is PRIVATE by standing wall. No executor flips
visibility"* — after measuring `HTTP 404` on the `github:` URL and
`{"isPrivate":true}` on the repo. That bar is now spent by
`~/research-methods/RULINGS.md` **R-2026-09-06-22** *(Tom's line, 2026-09-06
evening: "herdr kitten goes public is fine")*: `gh repo edit
mecattaf/herdr-kitten --visibility public` was performed by the planning
session at 20:31Z on that line, and the ruling names this unit — *"U-D15
(dotfiles PR #324, the `github:` input) resumes with no Tom line left on it."*
No executor of this unit ran any visibility command. RE-MEASURED 2026-09-06T22:05Z on
the coordinator: `gh repo view mecattaf/herdr-kitten --json isPrivate,visibility`
→ `{"isPrivate":false,"visibility":"PUBLIC"}`; `gh api repos/mecattaf/herdr-kitten`
→ `updated_at 2026-09-06T20:31:56Z`, i.e. the ruling's own timestamp; and
`nix flake metadata github:mecattaf/herdr-kitten/ccc16393…` resolves, unpacks,
and reports narHash `sha256-X5b1Fi6ObCI5xHPpEXTL8k1FbWO5JZeBnqMYAfG6jVU=` —
byte-identical to what `nix flake metadata --offline
'git+file:///home/tom/mecattaf/herdr-kitten?rev=ccc16393…'` reports for the
local checkout, so the fetcher changed and the object did not. Deferring a form
whose only blocker a Tom line has already cleared would have shipped a flake
that evaluates on exactly one box while reporting itself green, so the flip is
taken and the earlier deferral withdrawn.

(2) **The card's `mutation_hint` is honoured on flake.nix, because flake.lock
cannot carry the string it counts.** "reintroduce the file:// URL → the grep
count is 1" was executed literally: `flake.nix` back to `git+file://…`, then
`nix flake lock --update-input herdr-kitten`. MEASURED: `grep -c 'git+file'
flake.nix` = 1 (the card's "1"), `grep -c 'file:///home/tom' flake.lock` = 2,
and `grep -c 'git+file' flake.lock` = **0 on both sides of the fault** — Nix
writes a local git tree in the lock as `"type": "git"` + `"url":
"file:///home/tom/…"`, never as `git+file`. So the DOMINANT's byte-exact lock
grep is kept as clause B and cannot be the clause that goes red;
`tests/herdr/test-herdr-kitten-input.sh` adds B2/B3/B4 (the same grep over
flake.nix, `file:///home/tom` over both files, and the positive form — the URL
is `github:mecattaf/herdr-kitten/<40 hex>` and the lock node agrees). Oracle rc
0 green, rc 1 under the mutation with B2/B3/B4 red.

Those greps read the whole of `flake.nix`, COMMENTS INCLUDED, and that is not a
false positive to paper over: MEASURED 2026-09-06T22:10Z, a first draft of the
new URL comment spelled the retired local URL out for contrast and the oracle
went red on B2/B3 with the pin itself correct. So `flake.nix` never names the
form it removed, not even nostalgically; the prose that does name it lives in
`docs/herdr/herdr-kitten-input.md` and in this file, neither of which the oracle
greps.

(3) **The lock update the oracle names must be a NO-OP, and that is asserted.**
Clause A0 runs `nix flake lock --update-input herdr-kitten` (falling back to
`--offline`), then requires `flake.lock` byte-unchanged and restores it if not.
That is both "after nix flake lock --update-input herdr-kitten" and the card's
"re-applying the same card reports zero changes"; a pin that drifted on every
re-run would satisfy neither. The script restores the lock a SECOND time on
exit, because under the mutation Nix rewrites it again inside clause A
(`nix flake check` fixes up a lock that no longer matches `flake.nix`,
`--no-build` or not) — MEASURED: a mutated run otherwise leaves `flake.lock`
dirty, i.e. a change nobody authorized. Every clause reads the mutated lock
before that exit restore, so no red is masked: green run rc 0 with the tree
byte-clean, mutated run rc 1 with `flake.lock` restored on the way out.

(4) **The card's byte-exact DOMINANT does not discriminate this unit, and the
mechanized form does — both MEASURED on the parent.** The first attempt's
receipt recorded this as defect D-2 and it is still true of the card's three
clauses taken byte-exactly. CONTROL, in a detached worktree at `origin/main`
`cd917822` (removed after): `nix flake lock --update-input herdr-kitten` rc 0,
`nix flake check --offline --no-build` rc 0, `grep -c 'git+file' flake.lock`
**0**, `nix eval … home.packages` **`["herdr-kitten"]`** — every clause of the
card green on a commit that still pins `41a6de5` over a local URL. Nix spells a
local git tree `"type": "git"` + a bare `file://` URL in the lock, never
`git+file`, so the card's grep cannot see the fault it names; and `hk` was
already in the coordinator's packages before this unit.
The same control under `bash tests/herdr/test-herdr-kitten-input.sh
/tmp/ud15-control-…` exits **1** — B2 = 1, B3 = 2/1, B4 red twice, and the lock
node reading `git -/- 41a6de5…`. So the discriminating acceptance for this unit
is the script's B2/B3/B4 plus the no-op A0, not clause B alone; D-2 is answered
by mechanism rather than argued away, and the card's own argv is kept verbatim
as clause B inside it.

Not decided here and deliberately untouched: the herdr TOPOLOGY. One server, on
the coordinator (ruling B5); `#309` stays Tom's. The `home-profiles` check
asserts that shape in both directions so a pin move cannot become a topology
move. The switch that puts this pin on a box is `DEFERRED.md` DF-U-D15-1.

2026-09-06 U-D13 (dotfiles#316): the `tally-b` input and `modules/tally-b.nix`
— the rewrite kernel (github.com/mecattaf/tally, U-B1…U-B13) as one system
service on the coordinator, beside the live daemon. Five lines are decided
here; the mechanism and its measurements are in `docs/local-ai/tally-b-input.md`.

(1) **`git+https://` with `flake = false`, because the repo is private AND
carries no Nix.** `gh repo view mecattaf/tally --json isPrivate,visibility` →
`{"isPrivate":true,"visibility":"PRIVATE"}` (MEASURED 2026-09-06), and no
executor flips visibility — contrast U-D15, where R-2026-09-06-22 had already
taken the Tom line before the `github:` form was admitted. The native `github:`
fetcher was MEASURED against that wall: `nix flake lock --update-input tally-b`
over `github:mecattaf/tally/<rev>` answers `HTTP error 404`, because the
tarball fetcher spends nix's own `access-tokens` and this fleet configures none
(greps over /etc/nix/nix.conf, ~/.config/nix/nix.conf, NIX_ACCESS_TOKENS: all
empty; no ~/.netrc). The `git+https://` form fetches through git, and git here
authenticates through the machine's persistent credential path (the `gh auth
git-credential` helper in the global gitconfig — never read, never printed).
Consequence, stated rather than hidden: the ONE network act (the lock update /
a cold fetch) works only on a host whose git can authenticate to github.com;
after it, the git cache and the store path make every gate `--offline`-clean
anywhere. `flake = false` is the repo's own law — its CONTRIBUTING §1 rule 2
("This repository carries no Nix at all") and its DEFERRED.md, which names
`modules/tally-b.nix` in THIS repository as the unit's home.

(2) **The pin is `26d758049bf0e89126157b3ea743085bb1b918f0` = `origin/main` of
mecattaf/tally at U-B13's delivery** (PR #45 `k/socket` merged, plus the
evaluator-probe commit), and `nix flake lock --update-input tally-b` at that
pin is a NO-OP — MEASURED twice, and asserted as clause A0 of
`tests/tally-b/test-tally-b-input.sh`, which is both the card's "the lock
updated with nix flake lock --update-input tally-b" and its "re-applying the
same card reports zero changes". Bumping the kernel is an edit of the rev in
flake.nix, deliberate, the way nixpkgs-paperless is bumped — never a nightly
resolve (the input is NOT in `rollingInputOverrides`).

(3) **The socket path question the kernel's repo left open is answered at the
kernel's own default.** tally's DEFERRED.md carries "[OPERATOR] Where the
socket lives on the coordinator once U-D11 runs it under systemd … which path
the estate settles on is an operator's line". Settled: `<state>/kernel.sock` =
`~/.local/state/tally-rewrite/kernel.sock`, which is `default_socket_path()`'s
own answer (SOCKET_BASENAME beside the chain it fronts). It is a module option
(`services.tally-kernel.socketPath`), never an environment variable on the
unit, so a move is a reviewed eval-time change the topology check sees.

(4) **The rows file is the three `owner: kernel` rows of the rewrite's own
docs/rows.md and nothing else.** gpu-coordinator and gpu-worker (capacity 1,
context_window 32768, graces 30/10, cap 100000 per D-B3/TL-3, `running` =
llama-swap's `/running` — 127.0.0.1:9292 for this box, `http://worker:9292`
for the twin, because ONE kernel on the coordinator serves both devices, spec
§2.4 Q2) and mechanical (context_window null, `running` none — the evaluator's
row runs no model). The tom-owned seat rows are NOT served: U-D12's feeders
write them into the meters dir on the user bus and the kernel reads them
through it. A failed `/running` probe is written busy with grade UNKNOWN
(`RunningSource::observe`), so a down endpoint cannot fabricate headroom.

(5) **System bus, User=tom, no sandbox exemption dance — and coexistence is
asserted, not promised.** The live `tally-daemon.service` stays a USER unit
writing `~/.local/state/tally/`; `tally-kernel.service` is a SYSTEM unit
writing `~/.local/state/tally-rewrite/`, and the separation is enforced three
times over: the kernel's own `Ledger::open` refuses branch (a)'s paths by name
(ledger.rs:31-35), the module asserts `tally-rewrite` in the stateDir at eval
time, and the `tally-b-topology` flake check plus clause F of the test script
assert the live declaration still evaluates while no system-bus `tally-daemon`
twin exists. ProtectHome/ReadWritePaths hardening is deliberately absent: the
process's whole job is running admitted work as this user over this user's
tree, and its own writes are confined by the state root it refuses to leave
rather than by a sandbox that would have to exempt the executor's world anyway.

MEASURED for the mutation hint, both readings: with the `systemd.services`
block removed from the module, `nix eval
.#nixosConfigurations.coordinator.config.systemd.services.tally-kernel.enable`
fails non-zero ("does not provide attribute"); with `enable = false` in
hosts/coordinator/default.nix it prints `false`. The card's "the eval is false"
is red either way; the removal reading is the one the hint names and the one
run. NOT decided here and deliberately untouched: the switch (U-D19), the
uplink (U-D14/W-03), the evaluator lock (null until U-A17 exists to be locked),
and every line of `home/tally.nix`.

2026-09-07 U-D14 (dotfiles#317): the `tally-lake` input and
`home/tally-uplink.nix` — the LAKE's box-side loop (`apps/uplink`, card W-03) as
one user service on the coordinator, beside U-D13's served kernel. It replicates
the `tally.nix` input motion exactly (the card's exemplar): an input, then ONE
home module that imports what the input exports and sets it for this estate.
Seven lines are decided here; the mechanism and its measurements are in
`docs/local-ai/tally-uplink-input.md`.

(1) **Consumed AS A FLAKE — no `flake = false` — because unlike `mecattaf/tally`
this repo ships one.** W-03 added `flake.nix` to mecattaf/tally-ts-sdk (lake
commit `c29fdfb`) under an explicit supersession of that repository's own
CONTRIBUTING §2 rule 6, "No Nix in this deliverable", recorded there as D-B65:
U-D14's card assigns the package derivation and the home-manager module to the
lake, and no other unit was chartered to build them. So `home/tally-uplink.nix`
imports `inputs.tally-lake.homeManagerModules.tally-uplink` the way
`home/tally.nix` imports `inputs.tally.homeManagerModules.tally`, and this
repository writes none of the uplink's behaviour. No `inputs.nixpkgs.follows`
either, because there is nothing to follow: the lake's flake takes NO inputs at
all, on purpose, so our pin drags no second package universe along.

(2) **`git+https://` again, for U-D13's wall, re-MEASURED for THIS repo on
2026-09-07.** `gh repo view mecattaf/tally-ts-sdk --json isPrivate,visibility` →
`{"isPrivate":true,"visibility":"PRIVATE"}`, and no executor flips visibility.
`nix flake metadata github:mecattaf/tally-ts-sdk/a233c30…` answers `HTTP error
404` — the tarball fetcher spends nix's own `access-tokens` and this fleet
configures none. The `git+https://` form fetches through git and therefore
through the machine's persistent credential path (the `gh auth git-credential`
helper in the global gitconfig — never read, never printed). Same stated
consequence as `tally-b`: the ONE network act works only on a host whose git can
authenticate to github.com; after it, the git cache and the store path make
every gate `--offline`-clean anywhere.

(3) **The pin is `a233c303246efb6eceb8e84ac409f85d3d41879b` = `origin/main` of
mecattaf/tally-ts-sdk at W-03's delivery** (PR #99 `lake/uplink`, whose
`flake.nix` commit `c29fdfb` is an ancestor of it) plus U-A22's evaluator probe.
It is the FIRST `main` that exports `homeManagerModules.tally-uplink` at all;
anything before `c29fdfb` has no flake to import and this input cannot evaluate.
`nix flake lock --update-input tally-lake` at that pin is a NO-OP — MEASURED
2026-09-07, and asserted as clause A0 of
`tests/tally-uplink/test-tally-uplink-input.sh`, which is also the card's
"re-applying the same card reports zero changes". The input is NOT in
`rollingInputOverrides`: the lake proposes work onto this box's rows, so its
version moves when Tom says so, never on a nightly resolve — the same reason
herdr and herdr-kitten are out.

(4) **The rows file is `${inputs.tally-b}/docs/rows.md` — out of the store, from
the SAME pin the kernel comes from.** Upstream the option is required and has no
default, by the lake's own ruling that the rows file is a runtime argument
(D-B64) whose path that repository does not own; this estate answers it with the
pinned kernel's own table rather than the live checkout at
`/home/tom/mecattaf/tally`, which a `git checkout` could move under the unit
without a review anywhere. The rows the uplink probes and the kernel it probes
them against are then ONE pin and cannot drift apart in silence. MEASURED
2026-09-07 with the lake's own parser at the pin (`--parse-only` → rc 0): nine
rows — `cc`, `cc2`, `cc3`, `codex`, `pi-qwencloud`, `cerebras` (owner tom /
third-party, the seat rows U-D12's feeders write into the meters dir) and
`gpu-coordinator`, `gpu-worker`, `mechanical` (owner kernel, the three U-D13's
module serves). ALL NINE are probed, not just the kernel's three: the uplink
asks the door about every row it is given, and the door answers from its own
rows plus the meters dir. A probe that fails is written busy with grade UNKNOWN,
never as false idle.

(5) **The interpreter is `pkgs.nodejs-slim_24` from THIS flake, passed through
the seam the lake exported for it.** The lake's flake records a node store path
(`nodejs-slim-24.19.0`) and cannot do better from inside a pure flake with no
inputs — `builtins.storePath` is refused in pure mode, so its pin is a run-time
reference and not a build-time one. Its `mkUplink` takes `node` as an argument
"precisely so U-D14, which HAS a `pkgs`, can pass a real node derivation": the
interpreter is then a closure edge of the generation that installs the unit,
GC-protected, instead of a naked store path nothing owns. 24.18.0 at this
nixpkgs pin rather than the lake's 24.19.0, deliberately — the interpreter
belongs to whoever installs the unit, and both are node 24. MEASURED:
`require('tls').rootCertificates.length` is 120 on BOTH, so the unit needs no
`SSL_CERT_FILE` the way `home/seat-feeder.nix`'s python feeders do.

(6) **The token is a PATH and never a value, and nothing creates it.**
`tokenFile` = `~/.local/state/tally-rewrite/lake-token`; nothing in this
repository writes, reads, prints or stores its contents, and NO tmpfiles rule
names the file — creating it empty would be a stub standing in for a credential,
and an empty bearer is a 401 that reads like a lake outage. Until Tom writes it
the unit fails with `cannot read the lake token file <path>`, which names the
path (`DEFERRED.md` DF-U-D14-2). The lake ORIGIN on the unit is not a
credential: the Worker refuses every request, reads included, whose
Authorization is not the bearer (lake D-A22-1). Clause G asserts the path, the
absence of a rule and an empty `Service.Environment`, and never opens the file.

(7) **A home-manager module's eval-time guard lives in `flake.nix`'s
`tally-uplink-topology` check.** `modules/tally-b.nix` could put its invariants
in NixOS `assertions`; home-manager gives no option of that kind (MEASURED: no
`options.assertions` anywhere in the pinned home-manager's `modules/`), and a
top-level `assert` over `config` in a home module recurses. So the invariants
over literals sit in `home/tally-uplink.nix` and the invariants over the
RENDERED unit sit in the flake check — which runs under `nix flake check
--offline --no-build`, the card's own first clause, so the two halves of the
oracle are one gate. It asserts the service is declared on the coordinator and
NOT on the worker (one uplink per box that serves a kernel, spec §2.4 Q2 — the
worker twin is a row that kernel serves), every path under
`~/.local/state/tally-rewrite` and none under branch (a)'s live root, the rows
out of the store, `wakes = 1`, no `Install` section, no system-bus twin, and the
live `tally-daemon` declaration still evaluating.

MEASURED for the mutation hint: with `./tally-uplink.nix` removed from
`home/home.nix` — "the module import" — the card's own eval
(`…systemd.user.services ? tally-uplink`) prints exactly `false`, and
`nix flake check --offline --no-build` fails on the topology check's first
assert. The membership form is deliberate: it makes the hint's own word `false`
the printed value rather than an attribute-missing error. The other reading —
dropping the UPSTREAM import inside `home/tally-uplink.nix` — leaves
`services.tally-uplink` set but undeclared and dies non-zero; both are red and
only `true` is green.

NOT decided here and deliberately untouched: the switch (U-D19, DF-U-D14-1),
what wakes the uplink (U-D18's filler-lane timer, DF-U-D14-4), the kit and the
plan (both null, DF-U-D14-3), the evaluator lock (still U-D13's DF-U-D13-2,
waiting on U-A17), and every line of `home/tally.nix` and `modules/tally-b.nix`.

2026-09-07 U-D18 (dotfiles#321): the manifest's DOMINANT oracle for the filler
lane's timer is prose naming three clauses, so it is mechanized as ONE argv —
`bash tools/u-d18-filler-timer-oracle.sh` — and the lines the prose left open
are decided here.

(1) **"The uplink's filler verb" resolves to the REGISTER's
`tools/e1-loop.sh --all`, not to a verb of `apps/uplink`.** MEASURED 2026-09-07
at the rev this repository pins (`tally-lake` = tally-ts-sdk `a233c30`): the
lake's uplink CLI offers `--parse-only`, `--replay-only`, `--drain-only` and the
default wake, and the string `filler` occurs nowhere in that input at all. The
verb is named instead by a captured ruling — `~/research-methods/DECISIONS.md`
D-U-E1LOOP-7, "`--all` is the lane's verb over the whole eligible population and
is what U-D18's timer calls" — so `ExecStart` is
`bash %h/research-methods/tools/e1-loop.sh --all`. The alternative readings were
both worse: inventing a `--filler` flag on an input this unit does not own, or
re-implementing the lane's dispatch here, which is the one thing a clock must
never do. MEASURED: that verb's population today is 21 ready rungs (24 eligible,
15 not eligible), and `--all --dry-run` exits 0 having dispatched nothing.

(2) **The verb is an out-of-store `%h` path, and no `ConditionPathExists=`
guards it.** The register is LOCAL by ruling (D-B12), so it is not and must not
become a flake input of this repository; `%h/research-methods/...` is the same
seam `home/seat-feeder.nix` already uses for `stamp-receipt.py`. A condition
would turn an absent lane into a silent no-op; without one the unit exits
non-zero naming the path, which is this repository's own rule for a missing
directory (dotfiles#292).

(3) **D-B10's round-robin is carried as an EQUALITY against the drain's own
declared period, not as a literal.** `tally-drain.timer` — the other filler —
is declared `OnUnitActiveSec = "5min"` (MEASURED in the rendered coordinator
config and in the installed unit file). `home/tally-filler.nix` spells the same
string, byte for byte, and `flake.nix`'s `tally-filler-topology` check asserts
`filler.OnUnitActiveSec == drain.OnUnitActiveSec`. `"300s"` would be the same
duration and a different byte; the equality is what makes an upstream cadence
change RED here instead of a silent end to the alternation. What actually keeps
the GPU single-tenant is NOT the cadence but the lane's own `/running`-empty
gate, which this unit deliberately does not duplicate and could not enforce.

(4) **Recorded rather than smoothed over: which unit "the academic drain" is.**
Spec §2.4 names `tally-drain.timer` as the GPU row's unleased tenant, "every
5 min, `Python-urllib/3.14`, MEASURED". MEASURED here 2026-09-07: that timer's
cadence IS five minutes and its service runs `tally … daemon drain` (the
producer-event drain), while llama-swap's only `Python-urllib/3.14` callers in a
40-minute window were PER-MINUTE `GET /health` + `GET /running` probes — the
util-sampler's shape, not a five-minute tenant. This unit therefore alternates
against the drain BY NAME and BY DECLARED CADENCE (the unit D-B10 names), and
nothing here depends on resolving who authored §2.4's user-agent observation.

(5) **`TimeoutStartSec = "infinity"`, and no `Restart=`.** The one systemd
default this unit overrides. §4.4.2 bounds an ITEM by `runtime_cap_seconds`,
enforced by the lane per item; a manager-side deadline over the whole pass would
SIGTERM the unit mid-item and cost more than the one item a preemption is
allowed to cost (§4.4.1, "yields the lease within one item"). A cold-load crash
loop is stopped by the lane's `abort_on.consecutive_crash: 2` (§4.4.6), not by a
clock — and a `Restart=` on a GPU lane would BE that loop.

(6) **The run proof is a transient probe named `tally-filler-probe`, running a
`--dry-run`.** The card's post-switch clause — "after the switch `systemctl
--user list-timers` names `tally-filler.timer`" — is U-D19's post-condition by
the orchestrator's D-B66 note (U-D19 is the only unit whose oracle switches, and
it dependsOn U-D18, so the clause could not be true at this unit's own
evaluation). What clause E proves instead is spec §2.4/§5.2's own form for a
timer before TL-15: `systemd-run --user --on-calendar` from a shell, the
module's own rendered argv, `list-timers` naming it, `LastTriggerUSec` observed
to move, and the check recording `launcher: shell` and reporting without
failing. The probe's name is NOT `tally-filler` (that would shadow what U-D19's
switch installs, and Rule 9 bars a hand-installed stand-in) and its argv carries
`--dry-run` (a probe that made a real model request would spend GPU time to
prove a clock works, and would break the lane's "never two concurrent model
requests"). Both differences are asserted ABSENT from the installed unit.
MEASURED: the probe armed, was named by `list-timers`, fired, and the pass it
started exited 0 — `ActiveState=active Result=success ExecMainStatus=0`.

(7) **The module's own asserts are over LITERALS only.** A top-level `assert`
that forces `pkgs` — which the unit's `PATH` does — dies "infinite recursion
encountered" while the module system is still merging (MEASURED on this file's
first draft; the same class of failure U-D14 hit with `config`). So the
PATH-shaped non-goals ("never calls llama-swap", "never unloads") are asserted
in `flake.nix` over the RENDERED unit, where they are strictly stronger: there
they read `ExecStart` and `Environment` as one string, so a value cannot hide in
the environment block.

MEASURED for the mutation hint: with `./tally-filler.nix` removed from
`home/home.nix` — "remove the timer" — the card's own eval
(`…systemd.user.timers ? tally-filler`) prints exactly `false`, `nix flake check
--offline --no-build` fails on the topology check's first assert, and
`bash tools/u-d18-filler-timer-oracle.sh` reports FAIL rc 1. The membership form
is deliberate: it makes the hint's own word `false` the printed value rather
than an attribute-missing error.

NOT decided here and deliberately untouched: the switch (U-D19, DF-U-D18-1), the
anti-starvation number (TL-10, DF-U-D18-2), moving the drain onto a lease over
the socket (U-D11/TL-15, DF-U-D18-3), every option of
`home/tally-uplink.nix` (which still renders with no `Install` section — this
unit discharges DF-U-D14-4 with a timer of the filler's own, never by installing
the uplink), and every line of the register's own `tools/e1-loop.sh`.

2026-09-07 CAP-1 (dotfiles#337): the manifest's DOMINANT for SEAT-ROWS-UNTIL is
prose over five rows, so it is mechanized as ONE argv —
`bash tools/seat-rows-oracle.sh [meters-dir]` — and the lines the prose left
open are decided here.

(1) **With no argument the oracle runs one feeder pass itself, into a scratch
directory.** The manifest's own parenthetical allows either "the live directory
after one feeder pass" or "the feeder run by hand with TALLY_METERS_DIR at a
scratch dir". The evaluator re-runs from a FRESH worktree, where the live
directory's contents are whatever the last switched generation's timers left;
so the no-argument form is the self-contained one and is what the acceptance
records. The argument form asserts on a directory a caller already fed, which is
the live-directory reading of the same sentence. `TALLY_METERS_DIR` is honoured
when no argument is given, so the manifest's wording works verbatim. The oracle
writes nothing under `~/.local/state` in either form.

(2) **A cell a source is silent about is the string `UNKNOWN` with a reason
beside it, and never a null or a zero.** MEASURED against the merged
`tally-admit`: the kernel's reader treats that sentinel as ABSENT
(`window.rs is_absent`, `meter.rs is_unknown_value`), so the row stays readable
— "no field it refuses, no rename" holds. A null `utilization_pct` at the row
root, by contrast, refuses the row outright, which is what the pre-CAP-1 `cc`
row was doing.

(3) **The feeder never declares a window whose reset it does not know.** A
declared window missing its reset is a refusal, not an unknown: MEASURED
negative control, `tally-admit` answers STOP `observation_unusable` with
`refusal meter_cell_unknown`, "declared window has no reset instant". So when
`pi-hold.json` states no current reset, the row publishes `"window": "UNKNOWN"`
with `window_reason` — read as an unknown window — and the oracle goes RED
naming the row. An incomplete row is a fact to surface, not one to paper over,
and the alternative (declaring the shape anyway) would trade a legible RED for
an unreadable row.

(4) **`window_remaining_pct` is `100 −` the BINDING span, the most spent one.**
A seat at 3% of five hours and 96% of seven days has four percent left, not
ninety-seven. It is published as the row's own cell, which the contract says
wins over anything the reader derives, and it is UNKNOWN — with the reason —
whenever any span published no utilization, because a remainder over some of
the windows is invented headroom.

(5) **D-B92's cached reading is PUBLISHED, superseding U-D12's "freshness was
not invented".** U-D12 wrote a current UNKNOWN whenever the reader answered from
its cache, on the reasoning that re-stamping old values as fresh MEASURED
manufactures headroom. D-B92 settles the resolution question the other way: the
endpoint answers in whole percents, so a reading under 45 s old IS the
measurement. The row now carries the numbers plus `reading_age_seconds`,
`reading_observed_at` and `reading_source`, graded MEASURED under 45 s and
STALE-MEASURED over it. Headroom is not manufactured because the age is in the
row; MEASURED 2026-09-07 17:00–17:05Z, alternate passes of the live service were
publishing MEASURED and UNKNOWN for the same unchanged seat, which is worse
evidence than an old number that says how old it is.

(6) **A read that does not land falls back to the last MEASURED reading, from
two sources, newer first: the row this feeder last published, then the reader's
own `.window-cache-<seat>.json`.** The reader hard-codes that cache beside the
live rewrite rows, so `TALLY_WINDOW_CACHE_DIR` names the directory rather than
assuming it is the feeder's own output — a scratch-dir run still finds the
retained reading where the reader actually put it, and a fixture can redirect it
to stay hermetic. The file holds the usage response, percentages and reset
stamps; it is not a credential and no value from it is printed.

(7) **U-D12's replay assertion R9, "pi-qwencloud invented a window instead of
leaving it UNKNOWN", is superseded and inverted.** The reset and the utilization
are two questions; only the second is behind TL-17. R9 now requires the hold
record's rolling window with an UNKNOWN utilization and an UNKNOWN remainder,
both with reasons.

NOT decided here and deliberately untouched: the kernel and what it serves
(`--rows` stays gpu-coordinator,gpu-worker,mechanical), the switch that would
make the corrected `TALLY_CLAUDE_SEATS` live (U-D19's, DF-CAP-1-1), TL-17 itself
(DF-CAP-1-2), and every path under `~/.local/state/tally/`.

2026-09-07 MEM-3 (dotfiles#340): `harvest --enqueue` turns each unresolved unit
of a harvest into one enqueue row in the live daemon's shape. Six lines decided
here so the unit did not wait.

(1) **The required-keys list is the intersection of real rows, plus the two
hashes the mechanism names.** MEASURED 2026-09-07 over a 600-row random sample
of `~/.local/state/tally/events/*.enqueue.json` (10,144 rows, read only): every
row carries the 5 event keys and the 26 row keys of `REQUIRED_EVENT_KEYS` /
`REQUIRED_ROW_KEYS`, with **no type violation anywhere** — the whole 600 pass
apart from `row.briefHash` (missing in 144) and `row.payloadHash` (missing in
52), which MEM-3's mechanism names on a harvest row and which are therefore
required here. `jobTokenHash` was universal in the first 400-row sample and
missing in 2 of the next 600, so it is optional: a key that is *nearly* always
present is not an invariant. `ingressId`, `orchestration`, `workspace`,
`adapterOptions`, `ghOrigin` and `modelProvenance` are optional for the same
reason, and unknown keys are allowed, because the daemon's shape grows by
addition and a validator that refused growth would refuse tomorrow's rows.

(2) **The validator's test seam is an environment variable read at check time,
not a hand-forged file.** `ENQUEUE_ROW_CHECK_DROP_KEYS` drops the named keys
from the document the validator is handed. The refusal path is then driven by a
row the writer *built correctly*, which is the only way the test proves the
writer's own validate-before-write ordering rather than proving that a broken
file is broken. The seam works identically in-process and across the CLI's
process boundary, so one seam serves both halves of the oracle. It is unset in
every real run, and `apply_test_seam` copies before it drops, so no caller's
document is mutated.

(3) **`acknowledged` is `false` and `guardrailDepth` is `0` on a harvested row,
which is out of the live sample's distribution and is the honest value.** All
400 sampled live rows carry `acknowledged: true` because the daemon acks what it
has taken; `guardrailDepth` 0 occurs in 61 of 400. No daemon has seen a harvest
row — they sit in the harvest store — so saying otherwise would be a claim about
a delivery that has not happened. The validator checks the *type*, never the
value, which is why both readings pass.

(4) **A refused row does not cost the harvest its other rows, and does not cost
it the note.** The writer attempts every unit, logs one line per refusal, and
raises once at the end; the note has already been written by then. So the verb
exits 1 with the reason on stderr, `hook.log` carries exactly one line per
refused unit, and the distillation Tom paid ~40 GB of cold load for is still on
disk. The alternative — abort on the first bad row — would discard good rows to
punish a bad one.

(5) **`hook.log` is `<harvest store>/hook.log`, the same file MEM-2's SessionEnd
hook writes** (`~/research-methods/DECISIONS.md` D-E14 (3)): one override,
`AI_MEMORY_HARVEST_DIR`, moves the notes, the rows and the ledger together, so a
test never has to point them apart and no path in this verb can reach branch
(a)'s live state dir. MEM-3 does not depend on MEM-2 and does not require the
hook to exist; it writes the same ledger when it has something to record.

(6) **An `unchanged` harvest enqueues nothing.** The enqueue runs after the note
is written, inside the same session lock, and the `unchanged` short-circuit
returns before it. A SessionEnd hook that fires twice on one session therefore
does not write the same units twice — the rows have fresh uuid4 `eventId`s and
would not deduplicate themselves, so the idempotence has to live here. The
`dedupKey` is `harvest:<session_id>:<n>` and is what a future mover would fold
on.

NOT decided here and deliberately untouched: the drain (its bytes, its store and
its written prohibition are unchanged); the live daemon (never called); anything
under `~/.local/state/tally/`, which this unit only ever READ, to take the shape
from a real row; and the move of a validated row into the daemon's own events
directory, which is a separate act (D-E07) carried as `DEFERRED.md` DF-MEM-3-1.

2026-09-16 one TTS model, one diarization model, and a narrower model estate
(Tom). Qwen is the only TTS family: `qwen3-tts-1.7b-base-q8-0` with the
`qwen-k2so-midway-b` voice through `modules/qwen-tts.nix`. VibeVoice TTS
(`vibevoice-large-bf16`, the VibeVoice 1.5B and C++ conversions) is superseded
by it. The only diarization model is Microsoft's VibeVoice-ASR-Streaming-7B
(`vibevoice-asr-streaming-7b-bf16`, revision 60d858b, catalogued as a snapshot
with its own streaming tokenizer): `call-diarize` loads it on the coordinator,
replacing the January `vibevoice-asr-bf16` and its separate Qwen2.5 tokenizer
row, which both leave the catalogue. Tom chose the 7B over the 1.5B despite the
1.5B's cleaner speaker split on the single-file synthetic fixture of 2026-09-14:
call recordings already separate the two sides by track, and the 7B's long-form
word accuracy is markedly better. OUT, and not to return, added to the
2026-09-11 list: everything Gemma (the 12B and its MTP head, the E4B and 12B
speech-intake projectors), Qwen3.6-35B-A3B, anything GLM, DS4, flashnext and
flashnix (flashnext-fp8 included), Ornith, Muse Glimmer and IBM Granite. The
coordinator's wanted set becomes FARA 9B plus its projector, the streaming ASR,
the Qwen speech rows and the wake words. NAS Library bytes for the retired rows
leave by the retire runbook, with a separate yes for each deletion; this entry
changes the declared state only.

2026-09-16, addendum: both Halogen engines on both twins, and the model estate
cut to what is in use (Tom). Tom: "i want halogen for qwen AND qwen flash … both
models, on both devices." `modules/strix.nix` now declares the Halogen server
and its `qwen38-27b` alternate once for the worker and the coordinator, and
both wanted sets carry `halogen-qwen38-flash-next` and `halogen-qwen38-27b`.
Default design, Tom's to change: the worker keeps Flash resident from boot and
stays the fleet's `utility` endpoint (`http://worker:8731`); the coordinator
declares the same containers with `services.halogen.autoStart = false`, so an
operator starts either engine with `halogen-switch flash|qwen38-27b` and hands
the GPU back with the new `halogen-switch off`. The reason is memory: upstream
sizes Flash as leaving roughly 12 GB free on a 128 GB box, and the coordinator
is Tom's desktop that also runs Qwen TTS, Parakeet, the 17.6 GB streaming ASR
and live agent sessions. Its API is admitted on `wlp192s0`, its update-adopt
defers while a Halogen unit is active, and it carries `amdgpu.gttsize=126976`,
effective at its next reboot (it already measured 125 GiB of GTT from
`ttm.pages_limit`, so the engines do not wait on that reboot).

OUT, cumulative with the entry above, and deleted from the NAS Library and the
twins the same night: every FARA 1.5 model (4B, 9B, 27B and projectors) with its
consumers — `modules/fara-browser-model.nix`, `pkgs/fara-cli.nix` (and its
`browserbase` dependency), the `fara-browser` agent loop in
`pkgs/browser-desktop` and the house `fara-browser` skill; the noVNC browser
desktop, its Chrome menu and `chrome-stream` stay. Every Qwen3-VL row
(instruct, projectors, and the VL embedder). The GGUF Qwen3.6-35B-A3B,
Qwen3.6-27B and Qwen3.8-27B (`halogen-qwen38-27b` stays). DeepSeek/DS4, GLM,
flashnext (incl. `flashnext-fp8`, `qwen38-flash-next-fp8`), Flash-Next in other
formats (`qwen38-flash-next-ud-iq3-xxs`, the ciru IU4 reference), every Gemma
(supergemma included), Ornith, Muse Glimmer, `qwen3-coder-next`, the FLM NPU
models, the sherpa-onnx keyword-spotting research model (openWakeWord stays),
every VibeVoice except `vibevoice-asr-streaming-7b-bf16`, and every Qwen TTS
variant except production (`qwen3-tts-1.7b-base-q8-0`,
`qwen3-tts-tokenizer-f32`, `qwen-k2so-midway-b`): VoiceDesign, CustomVoice
BF16/Q8, the three K-2SO CustomVoice experiments, 1.7B BF16, 0.6B and khimaros
(`pkgs/qwen3-tts-khimaros.nix` leaves the flake with it). Their research
manifests leave `tools/`. The catalogue is now thirteen rows. Kept on the NAS:
both Halogen bundles, the streaming 7B ASR, the three production Qwen speech
rows, Parakeet, both openWakeWord rows, the three Mage rows and
`qwen3-embedding-8b-q8-0`. Left undecided and untouched:
`qwen38-flash-next-mtp-q8-0`, `qwen38-flash-next-mtp-shared-q8-0`,
`qwen38-27b-dflash2`, and the `models/research` and `models/acquisitions`
trees.

The K-2SO voice cannot be re-downloaded. Before any deletion it got a second
copy, sha256-verified against `lib/speech-intake-models.json`, at
`/mnt/nas/documents/voice-references/qwen-k2so-midway-b/` (with `SHA256SUMS`
and a README): the documents subvolume is btrbk-snapshotted and in the LaCie
loop. The `models` tree is in that loop too, but a mirror propagates deletions,
so it was not counted as a second copy. The deletions are receipted, one line
per artifact, in `/mnt/nas/models/weights/RETIRED-2026-09-16.tsv`;
`docs/nas/model-archive.md` now opens with the Library-era runbook. Refs #397.

2026-09-17 halogen-server 0.1.4 for the Qwen3.8-27B alternate on both twins,
with the coordinator's memory bounds. The alternate's image moves from 0.1.3
to `ghcr.io/peonist-ai/halogen@sha256:dc0a39a0016d6cfc58a197978febaafdf8d28403f724ded6111d98b5fb7ac0ea`
(0.1.4, re-resolved with skopeo; reference checkout `~/today/halogen-server`
at 5a0f952). It is serving-only over 0.1.3: chat_template_kwargs honoured,
developer role, 300 s keep-alive, reasoning_effort "none", response_format a
400, `/health.version`. The pin lives once in `modules/strix.nix`, shared by
both twins. Checked in the image rather than assumed: it ships no
`halogen-healthcheck` (so the alternate gets no podman health options) and no
default-budget env knob (`serve_api.py` hardcodes `max_tokens` 8192), so
Flash's `maxTokensDefault = 16384` has no 27B equivalent and clients must send
a budget. `HALOGEN_MAX_TOKENS_CAP`/`HALOGEN_QUEUE_TIMEOUT` stay the image's
coupled 65536/7200; `HALOGEN_KV_SLOTS` stays 1 (speculation on);
`HALOGEN_DOWNLOAD` stays unset. Upstream's `seccomp=unconfined` is not added:
0.1.4 loaded and served on the coordinator without it (/health
`version.match: true`, one chat completion). On the coordinator only, the 27B
gets `HALOGEN_CACHE_MB=8192` and Flash `HALOGEN_KV_POOL_POSITIONS=262144`, so
an operator-started engine does not size itself against the desktop's free
memory. Folded in: FDC-M4 (#407), `SuccessExitStatus=143` on every
podman-halogen unit so `halogen-switch` no longer writes failure markers, with
its check extended to both twins.
