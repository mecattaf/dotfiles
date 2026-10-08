{
  config,
  lib,
  pkgs,
  ...
}:
# Strix: permanent headless compute host, wired through BE550 to Freebox.
# Private DNS and storage use NAS; public routing is independent of NAS.
{
  imports = [
    ./hardware.nix
    ./disko.nix
    # ./fleet-deploy.nix DELETED 2026-08-21 (Tom: "fleet-deploy is DEAD…the
    # nas-centricity supersedes that fully"). The nightly strix-builds-
    # and-pushes transaction — including its push-activation of the NAS and
    # its own ⚠ failure-marker fish hook — is replaced by the update-center
    # model: the NAS builds nightly and publishes to attic; every device,
    # including this one, pulls and activates on its own schedule. Manual
    # deploys still work via the flake's deploy-rs nodes (`deploy .#nas`).
    ./uplink-nas.nix

    ./journal-upload.nix # fleet journald substrate sender — refs #135
    ./nas-client.nix
    # backups.nix (ws2b borg client) DELETED 2026-08-21 unbuilt, with the
    # NAS-side repo server — Tom ruled the borg layer redundant against the
    # physical-redundancy stack (RAID 1 + LaCie + snapshots).
    ./services.nix
    ./atuin.nix
    ../client/audio.nix # same dock microphone/speakers on either physical seat
    ./immich-ml.nix # transferred socket-activated ML from the retired worker
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
    # forwarded to strix loopback and consumed locally by Caddy.
    ../../modules/microvm-host.nix
    ../../modules/cli-anything.nix
    ../../modules/browser-desktop.nix
    ../../modules/keyring-autounlock.nix # TPM-sealed keyring unlock at boot, no typing
    ../../modules/handwriting-annotation.nix
    ../../modules/qwen-tts.nix
    ../../modules/strix.nix
    ../../modules/gvisor.nix # runsc on PATH; gate below (G1, 2026-09-23)
    ../../modules/fleet-hosts.nix
    # ax on the fleet (2026-09-23): the HARNESS node, see myAxFleet below.
    ../../modules/ax-fleet
    # kubectl + the google/ax binaries, behind myAxClient.enable. Imported on
    # all three interactive hosts, OFF on all three; read that module's header
    # for the runbook and for what it deliberately does not declare.
    ../../modules/ax-client.nix
    # The Cloudflare Substrate's strix side (2026-09-23, E1/A2): the
    # gentle capacity pusher and the interpreter-host puller, both declared
    # ON below (2026-09-24). The NAS side is hosts/nas/substrate-link.nix.
    ../../modules/substrate.nix
    # The academic OCR drain's standing submit (services.academicDrain.standing, ON below): a nightly lane B run on
    # the floor this box's puller serves (2026-09-25).
    ../../modules/academic-drain.nix
  ];

  networking.hostName = "strix";
  hardware.bluetooth.enable = lib.mkForce false;

  # ── Substrate on this box: declared ON (2026-09-24) ────────────────────
  # modules/substrate.nix. Two user units on tom's manager, replacing the
  # hand-started nohup processes of
  # ~/today/wednesday-prep-2026-09-23/substrate (RUN.md) with the same
  # configuration (runtimes opus/halogen/codex/codex-rw, pusher peerCacheDir
  # "inherit"). Tokens: secrets/substrate-floor-token.age (FLOOR_TOKEN) and
  # secrets/substrate-link-token-strix.age (this holder's LINK_TOKENS
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
        "ssh:strix" = 1800000;
      };
      sshRuntimes."ssh:strix" = {
        host = "strix";
        harness = "pi";
        seat = "halogen";
      };
    };
  };

  services.academicDrain.standing = {
    enable = false;
    onCalendar = "*-*-* 01:30:00";
  };

  myAxFleet = {
    enable = true;
    role = "harness";
    guardInterfaces = [ ];
    lan = {
      interface = "enp191s0";
      address = "10.42.0.2";
      # The wired port: "Wired connection 1" autoconnects with DHCP (MEASURED
      # nmcli, 2026-09-23). The guard covers it and it never takes the LAN
      # routes from the wifi (fix round 3).
      extraInterfaces = [ ];
    };
  };

  myGvisor.enable = false;

  # Primary physical seat again (2026-09-16); Zenbook remains a second seat.
  # Agent services stay independent of either compositor.
  myDisplay.enable = false;
  myDisplay.session = "sway";
  services.browser-desktop.enable = true;
  services.handwriting-annotation.enable = true;
  services.qwen-tts.enable = true;

  # Both stay on their proven pre-migration side until the real HDD and service
  # state have passed the associated issue's cutover checklist.
  # The 2026-08-02 atomic cutover (#131): media core and its PostgreSQL now
  # live on the NAS; the strix keeps only the tailnet identity, the
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

  services.caddy.virtualHosts."http://drain.internal".extraConfig = ''
    reverse_proxy 127.0.0.1:8740
  '';

  # myAxClient (kubectl + ax) is ON here by mkDefault from myAxFleet's
  # harness role (modules/ax-fleet/default.nix); ax-client-topology in
  # flake.nix pins that.

  services.halogen.client.enable = true;
  # Flipped post-flash after the zero-TOFU host-key check (2026-07-05): the
  # delivered /etc/ssh/ssh_host_ed25519_key matched mesh-registry.nix, so
  # agenix may now decrypt against it.
  mySecrets.enable = true;

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
