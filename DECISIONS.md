# DECISIONS

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
