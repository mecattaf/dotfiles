{
  config,
  lib,
  pkgs,
  ...
}:
# Coordinator: NAS-managed LAN routing/DNS, direct BE550 bypass, then Freebox.
# Static 10.42.0.2 keeps NAS services reachable while bypassing a failed NAS
# routing or DNS service. Freebox remains the independent emergency uplink.
{
  imports = [
    ./hardware.nix
    ./disko.nix
    # ./fleet-deploy.nix DELETED 2026-08-21 (Tom: "fleet-deploy is DEAD…the
    # nas-centricity supersedes that fully"). The nightly coordinator-builds-
    # and-pushes transaction — including its push-activation of the NAS and
    # its own ⚠ failure-marker fish hook — is replaced by the update-center
    # model: the NAS builds nightly and publishes to attic; every device,
    # including this one, pulls and activates on its own schedule. Manual
    # deploys still work via the flake's deploy-rs nodes (`deploy .#nas`).
    ./uplink-nas.nix
    # The fleet's LAST official tailscale.com node, kept always-connected-but-idle
    # as the escape hatch for a NAS-is-down day (Tom's ruling 2026-09-01). Pairs
    # with ./uplink-nas.nix's freebox-uplink fallback profile ON PURPOSE — the
    # rail must share neither control plane nor uplink with the thing it backs
    # up. Never "tidy this away" because hosts/nas/headscale.nix exists.
    ./tailscale.nix
    ./journal-upload.nix # fleet journald substrate sender — refs #135
    ./nas-client.nix
    # backups.nix (ws2b borg client) DELETED 2026-08-21 unbuilt, with the
    # NAS-side repo server — Tom ruled the borg layer redundant against the
    # physical-redundancy stack (RAID 1 + LaCie + snapshots).
    ./services.nix
    # ./immich-ml.nix MOVED to hosts/worker 2026-08-21 (#229, Tom's ruling: he
    # uses Immich's ML rarely, so its batches belong on the box he is not typing
    # on). The module moved wholesale — socket-activated :3003, 15-minute idle
    # retirement, standalone from services.immich (which is on the NAS since the
    # 2026-08-02 cutover) — with only the admitting interface and the box's name
    # changed. The NAS now dials http://worker:3003 (hosts/nas/media.nix), which
    # resolves via the 10.42.0.5 pin in hosts/nas/network.nix; this box answers
    # the same address from modules/fleet-hosts.nix. Deploy
    # order matters and is recorded here because getting it wrong is a visible
    # outage: worker first (so the endpoint exists), then the NAS (so it starts
    # dialling the new one), then this box (which stops answering :3003).
    ./atuin.nix
    # ./audio.nix MOVED to hosts/client 2026-09-11 with the iContact webcam it
    # pinned: the USB peripherals live on the thin client's Thunderbolt dock
    # now (R-7). This box keeps Ryzen HD Audio + Radeon HDMI and no real mic.
    # AdGuard is NAS-only. The primary profile uses NAS DNS; the two emergency
    # tiers use independent DNS and intentionally bypass NAS filtering.
    # ./attic.nix is NOT a server any more and has not been since 2026-08-21 —
    # atticd moved to the NAS with ws5 and what is left here is the cache-health
    # tripwire pointed at it (read that file's header; it says "NOTHING
    # server-shaped"). This line said "atticd over the tailscale mesh", which was
    # doubly stale by 2026-09-01: the daemon is on the other box, and the pull
    # path is http://nas:8080/fleet over the house LAN — the tailnet has never
    # carried fleet cache traffic, and now that the two boxes sit on DIFFERENT
    # control planes it could not. Refs #42.
    ./attic.nix
    # Artifact serving plane: Caddy drop-dir + TTL reaper (publish-artifact
    # skill's tailnet rung). Live origins stay local on 127.0.0.1.
    ../../modules/caddy-artifacts.nix
    # Durable microVM host. Guest ports used as live-artifact origins are
    # forwarded to coordinator loopback and consumed locally by Caddy.
    ../../modules/microvm-host.nix
    ../../modules/cli-anything.nix
    ../../modules/browser-desktop.nix
    ../../modules/keyring-autounlock.nix # TPM-sealed keyring unlock at boot, no typing
    ../../modules/handwriting-annotation.nix
    ../../modules/fara-browser-model.nix
    ../../modules/strix.nix
    # TWINS ONLY: kills the stock 127.0.0.2 self-mapping and points both twins'
    # names at their static LAN addresses (#273). Without it gethostname()
    # resolves to loopback, which every distributed library happily binds — the
    # rank-0-dies-in-6s / rank-1-hangs-forever failure. The NAS must NOT import
    # this: it carries its own pins in hosts/nas/network.nix and keeps the
    # stock loopback mapping.
    ../../modules/fleet-hosts.nix
    # The REWRITE kernel (github.com/mecattaf/tally, U-B1…U-B13) as one system
    # service against ~/.local/state/tally-rewrite/, coexisting with the live
    # user-bus tally-daemon.service (U-D13). Declared here, installed by U-D19's
    # switch — never hand-started (DEFERRED.md DF-U-D13-1).
    ../../modules/tally-b.nix
  ];

  networking.hostName = "coordinator";

  # No physical Niri/greetd session. Browser-only work gets a separate headless
  # Sway/WayVNC desktop, shared through stock noVNC at browser.internal on BE550.
  # Terminal work continues through SSH/Herdr. FARA inference starts on demand
  # on this host; the worker remains the resident Halogen server.
  myDisplay.enable = false;
  services.browser-desktop.enable = true;
  services.handwriting-annotation.enable = true;
  services.fara-browser-model.enable = true;

  # Both stay on their proven pre-migration side until the real HDD and service
  # state have passed the associated issue's cutover checklist.
  # The 2026-08-02 atomic cutover (#131): media core and its PostgreSQL now
  # live on the NAS; the coordinator keeps only the tailnet identity, the
  # socket relays (2283/4533/32400), the on-demand ML backend, and the NFS
  # client mount at the immutable /mnt/nas path. That "tailnet identity" became
  # the fleet's LAST tailscale.com one on 2026-09-01 and is now load-bearing for
  # a second reason — it is the emergency rail (./tailscale.nix), not merely
  # what is left over after the media core moved.
  myCoordinatorMedia.enable = false;
  myNasClient.useRemoteStorage = true;
  myNasClient.relayMedia = true;
  # #136: the tailnet front door (paperless.internal) for the NAS Paperless
  # backend; flips with the NAS's myNas.paperless.enable (2026-09-13).
  myNasClient.relayPaperless = true;

  # The rewrite's served kernel: ONE kernel, on the coordinator (spec §2.4 Q2 —
  # the worker twin is a ROW this kernel serves, not a second kernel), on the
  # system bus, against the rewrite's own state root. The live daemon on tom's
  # user bus is untouched and keeps running (modules/tally-b.nix).
  services.tally-kernel.enable = true;

  # ── Fleet candidate adoption (#354, 2026-09-13) ─────────────────────────
  # This box runs Tom's live agents, so its gates are the strict set: defer
  # while any Herdr agent is not idle/done (`herdr agent list`), while FARA's
  # model or the shared browser desktop is up, while a tally-kernel row has a
  # holder (rows.read) or the live tally daemon holds a pool lease, and — in
  # the module — while any nixos-rebuild/switch is running. Herdr itself is
  # never restarted by a switch (home/herdr.nix X-SwitchMethod=keep-old).
  # A switch that leaves herdr, tally-kernel or caddy down (having been up)
  # is rolled back.
  #
  # POLICY stage-only UNTIL THE LIVE DOWNGRADE REFUSAL HOLDS (#354 challenger
  # correction 6, re-applied by the lane verifier 2026-09-13). Tom's decision
  # text wants rolling here, and every gate below is wired for it, but this is
  # the box that runs the live agents and nobody can reach it overnight. The
  # hermetic downgrade cases are not the bar; the bar is the worker's LIVE
  # refusal of an older published candidate after deploy (DEFERRED
  # DF-354-1). Stage-only realises the candidate and reports it, and creates no
  # activate timer. Flip this one word to "rolling" once that refusal is seen.
  myUpdateAdopt = {
    enable = true;
    policy = "stage-only";
    userManagers = [ "tom" ];
    gates = [
      {
        name = "herdr-agents";
        argv = [
          config.myUpdateAdopt.gatesBin
          "herdr-agents-idle"
          "tom"
        ];
      }
      {
        name = "browser-sessions";
        argv = [
          config.myUpdateAdopt.gatesBin
          "units-inactive"
          "user:tom"
          "fara-browser-model.service"
          "browser-desktop.service"
        ];
      }
      {
        name = "tally-kernel-leases";
        argv = [
          config.myUpdateAdopt.gatesBin
          "tally-kernel-idle"
          (lib.getExe' config.services.tally-kernel.package "tally-kernel")
          config.services.tally-kernel.socketPath
        ]
        ++ map (row: row.row) config.services.tally-kernel.rows;
      }
      {
        name = "tally-daemon-leases";
        argv = [
          config.myUpdateAdopt.gatesBin
          "tally-daemon-idle"
          "tom"
          "/run/user/1000/tally/tally.sock"
        ];
      }
    ];
    criticalUnits = [
      {
        unit = "herdr.service";
        user = "tom";
      }
      { unit = "tally-kernel.service"; }
      { unit = "caddy.service"; }
    ];
  };

  # This box serves no model. The `utility-model` wrapper that /drain and
  # /print shell out to forwards one request to the worker's Halogen server
  # (modules/halogen.nix); the small GGUF artifacts loaned here are served by
  # hand with llama-server when wanted.
  services.halogen.client.enable = true;
  # Flipped post-flash after the zero-TOFU host-key check (2026-07-05): the
  # delivered /etc/ssh/ssh_host_ed25519_key matched mesh-registry.nix, so
  # agenix may now decrypt against it.
  mySecrets.enable = true;

  # ── power profile: balanced, declared, no daemon (2026-09-13) ──────────────
  # power-profiles-daemon (modules/common.nix) had been holding "performance"
  # since 2026-08-28 — persisted daemon state from the usb4-stream / dual-node
  # days, in no config anywhere. That pinned all 32 threads to the performance
  # governor and pushed the EC's platform profile to performance, whose fan
  # curve keeps the Framework Desktop's fan on a floor it cannot hold: measured
  # ~735 rpm against a 926 rpm target, stalling to 0 and restarting every ~20 s
  # at 50 °C idle. That stall cycle is the "static buzz" Tom heard through the
  # Thunderbolt era and after it. The worker, with no daemon, sits at
  # balanced / powersave / balance_performance — the kernel and EC defaults —
  # and that is what this box declares too. The daemon goes; the three values
  # are written once at boot and at every switch, and nothing persists a
  # profile behind the config's back any more.
  services.power-profiles-daemon.enable = lib.mkForce false;
  systemd.services.power-profile-balanced = {
    description = "Pin the platform profile and CPU energy preference to balanced";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    # amd_pmf is a udev-loaded module; give /sys/firmware/acpi/platform_profile
    # a moment to appear at boot rather than racing it.
    script = ''
      for _ in $(seq 1 40); do
        [ -w /sys/firmware/acpi/platform_profile ] && break
        sleep 0.5
      done
      echo balanced > /sys/firmware/acpi/platform_profile
      for p in /sys/devices/system/cpu/cpufreq/policy*; do
        echo powersave > "$p/scaling_governor"
        echo balance_performance > "$p/energy_performance_preference"
      done
    '';
  };

  # ── /home is on the secondary, and a missing one must be LOUD (#261) ────────
  # ./disko.nix mounts /home from the 500GB with `nofail`, because a required
  # mount that never appears drops this box into an emergency console it cannot
  # be logged into. The price of nofail is silence: the machine would boot
  # perfectly, /home would be an empty directory on the anchor, and services
  # would start writing into it — the same shadowed-/home shape the SSD
  # transition had to reclaim 161G from, except nothing would announce it.
  #
  # This is the announcement. It asserts the STRONG property, not merely that
  # something is mounted: that /home is a mountpoint AND that its source
  # carries the declared PARTUUID, so a wrong disk answering to the name fails
  # too. modules/failure-surfacing.nix installs OnFailure=failure-notify@%N on
  # every service through a top-level drop-in, so failing here writes a marker
  # and surfaces on the next interactive fish login with no wiring of its own.
  #
  # After local-fs.target: by then systemd has either mounted /home or given up
  # on it, and either way it has stopped waiting.
  systemd.services.home-on-secondary = {
    description = "Assert /home is the 500GB secondary, not an empty dir on the anchor";
    after = [ "local-fs.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "check-home-on-secondary" ''
        set -u
        want=7a1c9d2e-0b64-4f8a-9c31-5e2d8f4a6b70

        src="$(${pkgs.util-linux}/bin/findmnt --noheadings --output SOURCE \
          --mountpoint /home || true)"
        if [ -z "$src" ]; then
          echo "/home is NOT a mountpoint — the 500GB secondary did not mount," >&2
          echo "and nofail let the boot continue. Anything written to /home is" >&2
          echo "landing on the anchor and shadowing the real one. Check the disk" >&2
          echo "before starting work: lsblk, journalctl -b -u home.mount" >&2
          exit 1
        fi

        got="$(${pkgs.util-linux}/bin/lsblk --noheadings --output PARTUUID "$src" \
          | ${pkgs.coreutils}/bin/head -1 | ${pkgs.coreutils}/bin/tr -d ' ')"
        if [ "$got" != "$want" ]; then
          echo "/home is mounted from $src (PARTUUID $got), which is not the" >&2
          echo "declared secondary $want. Some other filesystem is answering to" >&2
          echo "/home; do not write to it until that is explained." >&2
          exit 1
        fi
      '';
    };
  };

}
