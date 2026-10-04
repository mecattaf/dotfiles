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
    ../client/audio.nix # same dock microphone/speakers on either physical seat
    ./trackpad.nix # Magic Trackpad bonded over Bluetooth, re-pair notes
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
    ../../modules/qwen-tts.nix
    ../../modules/strix.nix
    ../../modules/gvisor.nix # runsc on PATH; gate below (G1, 2026-09-23)
    # TWINS ONLY: kills the stock 127.0.0.2 self-mapping and points both twins'
    # names at their static LAN addresses (#273). Without it gethostname()
    # resolves to loopback, which every distributed library happily binds — the
    # rank-0-dies-in-6s / rank-1-hangs-forever failure. The NAS must NOT import
    # this: it carries its own pins in hosts/nas/network.nix and keeps the
    # stock loopback mapping.
    ../../modules/fleet-hosts.nix
    # ax on the fleet (2026-09-23): the HARNESS node, see myAxFleet below.
    ../../modules/ax-fleet
    # kubectl + the google/ax binaries, behind myAxClient.enable. Imported on
    # all three interactive hosts, OFF on all three; read that module's header
    # for the runbook and for what it deliberately does not declare.
    ../../modules/ax-client.nix
    # The Cloudflare Substrate's coordinator side (2026-09-23, E1/A2): the
    # gentle capacity pusher and the interpreter-host puller, both declared
    # ON below (2026-09-24). The NAS side is hosts/nas/substrate-link.nix.
    ../../modules/substrate.nix
    # The academic OCR drain's standing submit (services.academicDrain.standing, ON below): a nightly lane B run on
    # the floor this box's puller serves (2026-09-25).
    ../../modules/academic-drain.nix
  ];

  networking.hostName = "coordinator";

  # ── Substrate on this box: declared ON (2026-09-24) ────────────────────
  # modules/substrate.nix. Two user units on tom's manager, replacing the
  # hand-started nohup processes of
  # ~/today/wednesday-prep-2026-09-23/substrate (RUN.md) with the same
  # configuration (runtimes opus/halogen/codex/codex-rw, pusher peerCacheDir
  # "inherit"). Tokens: secrets/substrate-floor-token.age (FLOOR_TOKEN) and
  # secrets/substrate-link-token-coordinator.age (this holder's LINK_TOKENS
  # entry), delivered to tom 0400. No runtime-test wrapper: the puller runs
  # with the real /run/user so herdr and ssh stay reachable. Cutover, in this
  # order: (1) SIGTERM both nohup processes by their HOST pids and confirm
  # they exited (a unit pusher treats the namespace pid 2 in pusher.pid as
  # stale and would run beside a live nohup pusher); (2) rm -f
  # ~/.local/state/substrate/{puller.pid,pusher.pid,puller.host.pid,puller.supervisor.pid};
  # (3) only then switch. Rollback: both `false` and switch.
  services.substrate = {
    floorUrl = "https://substrate.mecattaf.dev";
    pusher = {
      enable = true;
      owners.codex = "tom"; # E6 (2026-09-23): the codex login is Tom's
    };
    puller = {
      enable = true;
      # 2026-09-24 16:00: two builds (crm, email) submitted at once, six nodes in flight across them
      # (codex-rw implementers plus opus verifiers). The proof ran at 1/2.
      maxRuns = 2;
      # 2026-09-30 (Tom's budget rulings: Qwen plan full utilization, OpenRouter paid and free, cc2 to the max): the
      # per-seat slots bound each provider (qwen 4, openrouter 4, openrouter-free 8, halogen 1); this is the total.
      cap = 12;
      # 2026-09-24 19:55: a codex-rw implement part of the crm build ran 45 min at full activity (82 tool calls) and was
      # cut; the parts are sized for Claude. Two hours for codex-rw, one for the opus gates and fixes.
      callTimeoutMs = {
        opus = 3600000;
        halogen = 1800000;
        codex = 3600000;
        codex-rw = 7200000;
        # 2026-09-30: pi on the cloud providers (substrate D-S14). An hour each, like opus.
        qwen = 3600000;
        openrouter = 3600000;
        openrouter-free = 3600000;
        # The halogen ceiling: ocr.substrate.workflow.js sizes a lane B node (DEADLINE_S 1620 plus the relay) to it.
        "ssh:worker" = 1800000;
      };
      # 2026-09-25, lane B of the academic OCR drain. Tom: "it would be better to have the changes made durable,
      # in dotfiles through PR's. that way the academic ocr task drain is "permamnently" registered on the
      # factory floor". The node's pi runs ON the worker through the ssh runner, which starts the remote job in
      # its own session, kills that process group over a second ssh on timeout or abort, and reaps leftover
      # groups after a runner crash (packages/runners/src/ssh.ts:28-38, 108-113, 171-193). That replaces the
      # 2026-09-25 relay (pi on the coordinator running `ssh worker lane_b_batch.py ...` through its bash tool),
      # where a coordinator-side abort killed only the local pi and ssh client and left the remote batch running
      # and holding <out>/.lane-b.lock, so a resumed node would stop on 'locked' (INFERRED: sshd sends a -T
      # session no SIGHUP). The worker needs no floor token and no new secret: pi and the halogen provider
      # (~/.pi/agent/models.json) are on its ssh PATH (MEASURED 2026-09-25). Both halogen and ssh:worker spend
      # seat halogen, so an agent() call that names only {seat: "halogen"} is refused as ambiguous
      # (config.ts:672); the ocr and backlog workflows name their runtime. The workflow side: academic-drain
      # da28725 makes ssh:worker its default and drops the `ssh ... worker` wrapper there (ON_WORKER), so the
      # batch runs under pi on the worker with no second hop; at a1ee049 (run 96b9568118826fac) it still
      # wrapped every command, a worker-to-worker hop whose inner session the pgid kill would not reach.
      sshRuntimes."ssh:worker" = {
        host = "worker";
        harness = "pi";
        seat = "halogen";
      };
    };
  };

  # ── The academic OCR drain, standing on the floor (2026-09-25) ─────────
  # modules/academic-drain.nix: a nightly user timer submits lane B
  # (~/mecattaf/academic-drain/ocr.substrate.workflow.js) under the per-night
  # run id acadlb<YYYYMMDD>, idempotent at the floor, and skips while a drain
  # run is in flight, the lane-b lock is held, the worker's sticky STOP or the
  # kill-switch file exists, lane B is exhausted, or the puller is down.
  # RELEASE WINDOW, Tom's ruling to make (01:30 is the planning pass's
  # proposal): substrate has no priority; the floor hands queued runs out
  # FIFO by seq (apps/floor/src/link/engine.ts:479), and a drain run holds one
  # of this puller's maxRuns = 2 slots for its whole night. 01:30 keeps the
  # evening build block ahead of it. maxRuns is deliberately unchanged.
  # Kill switch: touch ~/.local/state/academic-drain/STANDING-OFF.
  # OFF (Tom, 2026-09-30): no scheduled agent work is declared in dotfiles.
  # The PDF pass is a one-time activity finished by hand; a nightly lane B
  # submit comes back, if ever, as a substrate (factory) schedule.
  services.academicDrain.standing = {
    enable = false;
    onCalendar = "*-*-* 01:30:00";
  };

  # ── ax on the fleet: THE kill switch for this host ─────────────────────
  # The HARNESS node (modules/ax-fleet/harness.nix): a k3s agent tainted
  # ate.dev/sandboxClass=gvisor:NoSchedule, so only atelet and the gVisor
  # WorkerPool land here. "agent harnesses on coordinator" (Tom, 2026-09-23).
  # Switch order: the NAS, then this host, then the worker (a second agent
  # since 2026-09-25): this host accepts flannel VXLAN from every peer
  # (modules/ax-fleet/agent.nix), and until it accepts the worker's, pods on
  # the two agents cannot reach each other. `false`, switch, then
  # `sudo ax-fleet-teardown` (on PATH whatever the switch says) is the whole
  # rollback. This also turns myAxClient (kubectl, ax) on by mkDefault.
  myAxFleet = {
    enable = true;
    role = "harness";
    lan = {
      interface = "wlp192s0";
      address = "10.42.0.2";
      # The wired port: "Wired connection 1" autoconnects with DHCP (MEASURED
      # nmcli, 2026-09-23). The guard covers it and it never takes the LAN
      # routes from the wifi (fix round 3).
      extraInterfaces = [ "enp191s0" ];
    };
  };

  # gVisor runsc for direct rootless `runsc run` jobs (modules/gvisor.nix).
  # OFF until Tom flips it; the lane recommends the worker first.
  myGvisor.enable = false;

  # Primary physical seat again (2026-09-16); Zenbook remains a second seat.
  # Agent services stay independent of either compositor.
  myDisplay.enable = true;
  services.browser-desktop.enable = true;
  services.handwriting-annotation.enable = true;
  services.qwen-tts.enable = true;

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

  # drain.internal (2026-09-25): the academic-drain dashboard the worker
  # serves on its LAN address (mecattaf/academic-drain dashboard/serve.sh
  # --bind 10.42.0.5 --port 8740; port opened in hosts/worker/default.nix).
  # Every `.internal` name answers this host (modules/adguardhome.nix), so
  # Caddy fronts it here like the media relays in ./nas-client.nix.
  services.caddy.virtualHosts."http://drain.internal".extraConfig = ''
    reverse_proxy 10.42.0.5:8740
  '';

  # myAxClient (kubectl + ax) is ON here by mkDefault from myAxFleet's
  # harness role (modules/ax-fleet/default.nix); ax-client-topology in
  # flake.nix pins that.

  # Halogen Flash and the Qwen3.8-27B alternate are declared here as on the
  # worker (modules/strix.nix), but nothing is resident: an operator starts
  # one with `halogen-switch` and stops it with `halogen-switch off`. The
  # `utility-model` wrapper that /drain and /print shell out to still forwards
  # one request to the WORKER's Halogen server (modules/halogen.nix).
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

  # ── INTERIM (2026-10-04): /home is on the anchor, and must stay that way ─────
  # The 500GB secondary left with the worker; /home was copied onto the anchor
  # and is a plain directory on `/` until it moves onto the 1TB 26051Y809195
  # (see ./disko.nix). The two failure shapes worth announcing now are the
  # inverse of #261's: something mounting over /home (e.g. a stale generation
  # or a stray unit pulling in the old disk), and an empty /home (the staged
  # copy missing). modules/failure-surfacing.nix still surfaces a failure here
  # on the next interactive fish login. When /home moves to the 1TB, restore
  # the PARTUUID assertion from git history with the new disk's uuid.
  systemd.services.home-on-secondary = {
    description = "Interim: assert /home is the staged copy on the anchor";
    after = [ "local-fs.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "check-home-on-anchor" ''
        set -u
        if ${pkgs.util-linux}/bin/findmnt --noheadings --mountpoint /home >/dev/null; then
          echo "/home is a separate mount, but during the 2026-10-04 interim it" >&2
          echo "must be the plain directory on the anchor. Find out what mounted it" >&2
          echo "before writing anything: findmnt /home; journalctl -b -u home.mount" >&2
          exit 1
        fi
        if [ ! -d /home/tom/mecattaf/dotfiles/.git ]; then
          echo "/home/tom has no dotfiles checkout: the staged copy is missing or" >&2
          echo "incomplete. Do not start work until it is explained." >&2
          exit 1
        fi
      '';
    };
  };

}
