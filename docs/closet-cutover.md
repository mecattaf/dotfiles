# Closet cutover: Strix, NAS and Zenbook

Prepared 2026-10-08. This is a staged migration, not evidence of activation.
Do not run `switch` on Strix while Tom's current Herdr session must survive.
The network move and headless transition take effect on a deliberate reboot.

## Result

- Strix keeps its SSH host key and 10.42.0.2, now on enp191s0
  (9c:bf:0d:00:f6:73). Public routing uses BE550 10.42.0.3 and public DNS;
  `internal` DNS uses NAS 10.42.0.1. Wi-Fi and Bluetooth are disabled on boot.
- NAS remains wired at 10.42.0.1. Its native tailscaled reuses the existing
  SaaS identity, 100.65.85.114, from `/var/lib/tailscale-personal/tailscaled.state`.
  The `nas-saas` container and Headscale services are retired; their data stays.
  NAS advertises 10.42.0.0/24 and exit-node capability. Strix has no tailnet daemon.
- Zenbook is the physical Sway seat, with Huion unchanged and Magic Trackpad
  configuration moved there. Mod+Enter targets Strix. A client-side inbound
  SSH probe creates a failure marker after 90 seconds of sustained failure
  on the managed LAN or a Tailscale route. Recovery clears that marker.
- Halogen Flash runs on Strix at boot; the 27B alternate remains manual.
  Immich ML wakes on port 3003 and stops after fifteen idle minutes.
- The Brother queue remains `ipp://10.42.0.4:631/ipp/print`; paper-daemon stays
  on Strix. Speech synthesis stays on Strix, with playback defaulting to client.
- Claude settings become writable shared state outside Git. Activation seeds
  once and preserves subsequent model/effort choices. Existing logins stay.

Compatibility is deliberate: `coordinator` remains a LAN/SSH alias. The NAS's
installed NetworkManager profile ID remains `coordinator-fast-lane`. The
Substrate puller holder remains `coordinator`, because its remote token is
bound to that identity; renaming the host must not invalidate authentication.
Historical journals, receipts and upstream test fixtures may retain old names.

## Before the window

1. Finish checks and build all three exact closures. Record their paths and the
   Git commit. Retain the current system generation on each host as a GC root.
   Do not update flake.lock or run partitioning tools.
2. Verify direct LAN SSH to client, NAS and Strix. Keep a client terminal open
   that is independent of Herdr; record `ssh tom@10.42.0.2` as the recovery
   route. Strix currently has .2 on Wi-Fi and .184 on Ethernet; both are live.
3. Inspect outstanding k3s workloads on NAS. Cordon/drain the old coordinator
   node only in the agreed window, respecting workload disruption and local
   data constraints. Do not use force/delete-local-data shortcuts blindly.
4. Preserve current Claude settings **before** fast-forwarding the raw checkout:
   its current settings links still lead into Git. Run the new
   `home/claude-settings.py --home "$HOME" --template <draft>/home/dot_claude/settings.json`
   as Tom on Strix and client while the old settings still exist. Verify each
   chosen model/effort. The earlier client edit is backed up at
   `~/.local/state/dotfiles-cleanup/20261008T160810Z/client-settings.json`;
   preserve any newer choice rather than overwriting it with that older copy.
5. Save the current Git ref and current closure path on every host. Keep the
   pre-migration checkout accessible for rollback, because raw Home Manager
   symlinks use `~/mecattaf/dotfiles` independently of the system generation.

## Order inside the window

1. Update the client's raw checkout and activate its built closure. Verify
   `getent hosts strix`, `ssh strix true`, and a fresh Mod+Enter attachment.
   Existing Herdr sessions must remain alive. Enroll the client in ordinary
   Tailscale interactively, explicitly selecting `https://login.tailscale.com`
   and `--accept-routes`; do not silently reuse its former Headscale login URL.
2. On NAS, keep LAN SSH open. Stop Headscale, native tailscaled, and
   `container@nas-saas` before taking a **cold**, root-only backup of
   `/var/lib/headscale`, `/var/lib/tailscale`, and `/var/lib/tailscale-personal`.
   Record the old closure. Never run two daemons using the SaaS state file.
3. Activate the NAS closure over its LAN address. Run `sudo nas-tailnet-cutover`:
   it verifies the expected SaaS tailnet, removes the retired Funnel/Serve
   configuration, and applies the route/exit-node preferences. Verify the
   native daemon is Running and retains 100.65.85.114. The old Headscale backup
   failure remains part of the incident history; retiring its service does not
   mean the old backup was repaired.
4. In Tailscale admin, approve the NAS's 10.42.0.0/24 route and intended exit-node
   role. Verify grants permit Tom's client to reach the subnet. Add split DNS
   for `internal` and `art.mecattaf.dev` using NAS 100.65.85.114 if remote private
   hostnames are wanted. An always-on NAS needs an explicit key-expiry policy:
   its current key expires 2027-03-09. Confirm remote access using a genuinely
   external connection (for example the Zenbook on a phone hotspot), then
   return to the home LAN before the Strix reboot.
5. Fast-forward Strix's raw checkout to the reviewed commit immediately before
   staging the already built closure with `nixos-rebuild boot --flake .#strix`.
   **Do not use switch.** This prepares the boot entry; it must not move the
   current Wi-Fi address, stop Herdr, or restart the user manager.
6. After Tom explicitly starts the reboot window, reboot Strix. Reconnect from
   the client. On NAS, remove the retired `worker` Kubernetes node; once the
   replacement `strix` agent is Ready and workloads are healthy, remove the
   stale `coordinator` node. Preserve persistent volumes and application data.

## Acceptance after reboot

- `hostname` is strix; `ip -br addr` shows .2 on enp191s0, no Wi-Fi address;
  `ip route` uses gateway .3. Private DNS resolves through NAS and public DNS
  works. Strix has no tailscaled, greetd or Bluetooth service.
- From a fresh client login, Mod+Enter attaches without manual repair. NAS and
  client SSH still work. The client reachability sensor reports a healthy
  sample; inspect `journalctl -u tripwire-strix-reachability`.
- Halogen `/health` and `/v1/models` succeed. Ask `utility-model` one bounded
  request, then verify its consumer paths. Both model bundles already existed
  locally before migration; boot must not download model weights.
- From NAS, request `http://strix:3003/ping`, confirm ML wakes, and then confirm
  it idles down. Immich server and ML package versions must match.
- Verify `paper-daemon.path`, CUPS queue and printer reachability. Submit one
  small Markdown page through the print skill's hidden-temp/rename intake
  protocol and inspect its receipt. A successful build is not physical print
  evidence; Tom should confirm the page arrived.
- Power-toggle the unplugged Magic Trackpad and pair/trust/connect it on the
  Zenbook (adapter A0:B3:39:06:75:AB). Verify input, then remove the old bond on
  Strix. Never delete or recreate the Huion bond. Pairing notes are in
  `hosts/client/trackpad.nix`.
- Change Claude model and effort in cc/cc2, reopen, and check persistence.
  `git status` must remain clean. Inspect failed units and new coredumps on
  each host; do not hide failures to achieve a clean status.
- After Ethernet is verified, remove the obsolete saved Strix Wi-Fi connection
  profiles by their exact names, preserving the new wired profile.

## Recovery

Use direct LAN SSH before touching any tailnet state. For a NAS cutover failure,
stop the new tailscaled, restore its cold state backup while stopped, and
activate the recorded old closure. The old container and native state must
remain separate. Do not delete Headscale data, snapshots or identities.

For Strix, select the retained old boot generation if the new network fails.
If SSH still works, stage that recorded old closure for boot and restore the
old raw checkout ref, preserving any new user settings. Reboot in a deliberate
window. The previous generation brings back the old coordinator/Wi-Fi layout;
client and NAS keep its compatibility alias. Never restart Herdr or the user
manager as an improvised network repair while sessions must survive.

## Separate follow-up decisions

The disk move in #503, retirement of `/drain` and its dependent `handoff` skill,
remaining issue/PR triage and archive branches are separate. This change removes
the worker host and transfers its services; it does not claim every item in
#505 or #514 is closed before the physical acceptance checks pass. Otto (#506,
#507) is explicitly rejected, with no compositor/streaming trial to perform.
