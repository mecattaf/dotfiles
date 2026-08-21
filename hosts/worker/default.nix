{
  config,
  lib,
  pkgs,
  ...
}:
# worker — AMD Strix Halo (gfx1151), the coordinator's identical twin, and since
# 2026-08-21 a PERMANENT first-class fleet member again (#229; Tom's ruling: "the
# worker is FULLY BACK to my device list. not a lease").
#
# This host was retired 2026-07-29 when the device left the house, and that
# departure is what forced the fleet SSH key rotation. It came back running the
# same pre-rotation closure it left with — old user key (rightly refused
# fleet-wide), hermes credentials, a loopback AdGuard — so the reintegration is a
# full re-declaration, not a revert. Everything the old tree carried that the
# 2026-08 architecture superseded is deliberately absent; each omission is
# recorded below rather than silently dropped.
#
# WHAT IT IS NOW, in one line: a stationary LAN compute node at 10.42.0.5 that
# owns Immich ML for the whole house and the worker half of the local-model
# roster, ships its journal to the NAS, and is reached over ordinary SSH.
#
# WHAT IT IS NOT:
#   * not a tailnet node — the NAS is the fleet's single tailscale sink
#     (2026-08-21 ruling). Consequence, accepted: wayvnc has no reachable door
#     here, because modules/common.nix admits :5900 on tailscale0 ONLY and the
#     standing rule is that VNC never touches the raw LAN. The headless display
#     below still exists so the niri session lights an output normally; the
#     screen is simply not remotely viewable until this box has a tailnet again.
#   * not a build pusher — hosts/worker/cache-push.nix is DELETED. That module
#     was a nix post-build-hook that pushed every locally built path into the
#     coordinator's atticd. It held nothing else (its whole body was one
#     `nix.settings.post-build-hook`), and the NAS update-center supersedes it:
#     since 2026-08-21 the NAS builds all fleet closures nightly and publishes
#     them to its own attic, and every device — this one included — PULLS from
#     http://nas:8080/fleet (modules/common.nix). Devices no longer push.
#   * not a DNS island — the AdGuard import is GONE. Per-device AdGuard is
#     FORBIDDEN on this LAN: the loopback instance's upstreams are DoH to
#     1.1.1.1/1.0.0.1/9.9.9.9, exactly the addresses the NAS's dns_hijack drops
#     on tcp/443 (hosts/nas/router.nix), so this box's DNS would go dark the
#     moment it associated. Filtering comes from the LAN resolver at 10.42.0.1.
#     (This is the box the collision was first proven on.)
#   * not a microVM host — modules/microvm-host.nix stays coordinator-only by
#     its own header ("the durable execution and artifact front door").
#   * not a Tally executor or pool — all jobs still execute locally on the
#     coordinator, and nothing here reaches across to that daemon.
#   * not thermally policed — the GPU cooldown tripwire is DEAD (Tom's ruling
#     2026-08-21, at the end of this reintegration). Its two scripts and module
#     are deleted, not carried forward: the sensor/hysteresis layer and the
#     llama-swap shed adapter both go. The tripwire's original Layer 2 SSH'd to
#     the coordinator for a `worker-gpu` Tally lease that no longer exists, and
#     rather than keep a rewritten reflex nobody asked for, the whole thing is
#     retired. The hardware's own thermal management owns this now.
#
# myCluster.role is gone with modules/strix.nix's option (the flake asserts its
# absence); per-host policy is selected by networking.hostName there instead.
{
  imports = [
    ./hardware.nix
    ./disko.nix
    ./headless-display.nix
    ./immich-ml.nix # moved here from the coordinator 2026-08-21 (#229)
    ./journal-upload.nix # sender half of the #135 substrate — Strix boxes only
    ../../modules/cli-anything.nix
    ../../modules/strix.nix
  ];

  networking.hostName = "worker";

  # ── the LAN identity ───────────────────────────────────────────────────────
  # thomas-6ghz, modelled on the zenbook's profile (hosts/zenbook-duo) for the
  # WPA3-SAE/6GHz shape and on the coordinator's (hosts/coordinator/uplink-nas.nix)
  # for the STATIC addressing rationale — this box is stationary and load-bearing:
  # the NAS's Immich dials worker:3003 for every ML batch, the NAS admits
  # 10.42.0.5 for journal upload, and modules/common.nix pins the name fleet-wide.
  # None of that may depend on a DHCP round-trip at association time or on a lease
  # renewal ("anything dns/dhcp related must never bite", 2026-08-21). The dnsmasq
  # dhcp-host pin in hosts/nas/router.nix stays as the guard that keeps the pool
  # from ever handing .5 to anyone else.
  #
  # DELIBERATELY NO BSSID and no band: thomas-6ghz exists on exactly one radio
  # (the BE550's 6GHz; its 5GHz radio is disabled and 2.4GHz carries the separate
  # `thomas` SSID for the printer), so the mt7925e same-SSID roam crash has no
  # surface — and the 6GHz MLD BSSID differs between scan and association, which
  # is what broke activation ON THIS VERY BOX when a pin was tried live. The
  # flake's wcid check carries a matching by-name exemption for this profile.
  #
  # NO Freebox profile: the old wifi-freebox-worker / wifi-sodimo-worker secret
  # profiles are dropped with their ciphertexts. This box's fallback rail is not
  # another SSID — it is the Thunderbolt link to the coordinator (tb-fleet,
  # 10.99.0.1 <-> 10.99.0.2), which is imperative NM state on both ends and must
  # not be disturbed.
  #
  # ⚠ ensureProfiles NEVER DELETES a profile it stopped ensuring, so dropping
  # those two from this file did not remove them from the box — they had to be
  # deleted by hand at the reintegration, and they were. That mattered more than
  # it sounds: the stale Freebox-AB3ACE keyfile carried autoconnect with
  # priority 100 for an SSID that IS still in range (it is the coordinator's own
  # fallback rail). Any hiccup associating to thomas-6ghz and this box would
  # have quietly joined the Freebox segment instead, taken a Freebox DHCP
  # address, and disappeared from 10.42.0.5 — silently breaking Immich ML for
  # the whole house and its journal upload, with nothing pointing at the cause.
  # Deleted alongside it: sodimo_wifi (dead SSID) and the imperative
  # thomas-diag / thomas6-diag test profiles from cutover week. After this host
  # settles, thomas-6ghz is its ONLY wifi profile — the flake asserts exactly
  # that, so a re-added second SSID fails the build rather than the house.
  #
  # interface-name IS pinned (unlike the roaming zenbook): the firewall
  # admissions this host depends on — :3003 in ./immich-ml.nix and :9292 in
  # modules/llama-swap.nix — are interface-scoped to wlp192s0 anyway, so an
  # interface rename must fail loudly here rather than half-work there.
  networking.networkmanager.ensureProfiles.environmentFiles = lib.optional (builtins.pathExists ../../secrets/wifi-lan.age) config.age.secrets.wifi-lan.path;
  networking.networkmanager.ensureProfiles.profiles.thomas-6ghz =
    lib.mkIf (builtins.pathExists ../../secrets/wifi-lan.age)
      {
        connection = {
          id = "thomas-6ghz";
          type = "wifi";
          interface-name = "wlp192s0";
          autoconnect = true;
          autoconnect-priority = 110;
        };
        wifi = {
          mode = "infrastructure";
          ssid = "$BE550_SSID";
        };
        wifi-security = {
          # WPA3-SAE with protected management frames — mandatory on 6GHz.
          key-mgmt = "sae";
          pmf = 3;
          psk = "$BE550_PSK";
        };
        ipv4 = {
          method = "manual";
          address1 = "10.42.0.5/24";
          gateway = "10.42.0.1";
          dns = "10.42.0.1";
          ignore-auto-dns = true;
        };
        ipv6.method = "ignore";
      };

  # ── Borrowing model weights from the NAS Library (2026-08-21 ruling) ──────
  # The NAS exports its models tree read-only + root-squashed to this host
  # (hosts/nas/models.nix, fsid=6); local-models-sync borrows this host's
  # wanted set from here into /var/lib/local-models before llama-swap starts.
  # Mounted at /mnt/library, NOT /mnt/nas — because /mnt/nas has a real
  # history on this box (Tom: "/mnt/nas WAS taken — i am no longer using it,
  # since i moved the NAS away from ethernet"): it was this host's genuine
  # NAS path in the ethernet-NAS era, then the worker loan repurposed it as a
  # runtime bind of /home/tom/nas-local (recreated at every boot by
  # /root/worker-loan/reassert.sh — the same machinery that kept resurrecting
  # the OCR llama-swap drop-in; whole plane RETIRED 2026-08-21 evening,
  # archived under /root/worker-loan-RETIRED-2026-08-21, corpus data intact
  # at /home/tom/nas-local). Now that the NAS is the house's wifi router
  # rather than an ethernet peer, the path is deliberately NOT resurrected:
  # this host's only NAS view is the read-only Library, and a distinct name
  # says so — /mnt/nas remains free for whatever history does next.
  # soft+nofail, same hardening rationale as the coordinator's
  # nas-client mount: a dead NAS must never hang this box's boot or I/O
  # forever — sync just fails visibly and llama-swap serves what is local.
  boot.supportedFilesystems = [ "nfs" ];
  fileSystems."/mnt/library" = {
    # `nas:/` — the models tree is this host's whole NFSv4 pseudo-root (its
    # export line carries fsid=0; see hosts/nas/models.nix).
    device = "nas:/";
    fsType = "nfs4";
    options = [
      "ro"
      "soft"
      "timeo=30"
      "retrans=3"
      "nofail"
      "_netdev"
      "x-systemd.automount"
      "x-systemd.idle-timeout=10min"
    ];
  };
  services.local-models.libraryPath = "/mnt/library/weights";

  # ── Thunderbolt link durability, worker half (2026-08-21 ruling: the
  # coordinator↔worker cable MUST always work — full doctrine and the
  # dual-reboot/replug lore in hosts/coordinator/tb-fleet.nix). This end
  # pins the net module and runs the same heal loop against the
  # coordinator's /30 address; the loud tripwire lives coordinator-side.
  boot.kernelModules = [ "thunderbolt-net" ];
  systemd.services.tb-link-heal = {
    description = "Heal the worker-coordinator Thunderbolt link where software can";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "tb-link-heal" ''
        PATH=${
          lib.makeBinPath [
            pkgs.iputils
            pkgs.coreutils
            pkgs.gnugrep
            pkgs.networkmanager
            pkgs.framework-tool
          ]
        }
        STATE=/var/lib/tb-link-heal
        if ping -c 1 -W 3 10.99.0.1 >/dev/null 2>&1; then
          rm -f "$STATE/pd-reset-stamp"
          exit 0
        fi
        if ls /sys/bus/thunderbolt/devices/ | grep -qE '^[0-9]+-[1-9]'; then
          echo "peer device present but 10.99.0.1 dark — re-activating tb-fleet"
          nmcli connection up tb-fleet || true
        elif ls /sys/bus/thunderbolt/devices/ | grep -qE '^[0-9]+-[0-9]+:'; then
          echo "retimers present but no XDomain peer — rebinding USB4 NHIs"
          for d in 0000:c4:00.5 0000:c4:00.6; do
            echo "$d" > /sys/bus/pci/drivers/thunderbolt/unbind 2>/dev/null || true
          done
          sleep 2
          for d in 0000:c4:00.5 0000:c4:00.6; do
            echo "$d" > /sys/bus/pci/drivers/thunderbolt/bind 2>/dev/null || true
          done
        else
          # PD-blind signature (no retimers at all): CCGx reset, the fix
          # proven on the coordinator 2026-08-21 — see tb-fleet.nix doctrine.
          # Rate-limited: also bounces the other rear USB-C port.
          now=$(date +%s)
          stamp=$(stat -c %Y "$STATE/pd-reset-stamp" 2>/dev/null || echo 0)
          if [ $((now - stamp)) -gt 1800 ]; then
            echo "no retimers on the bus — PD-blind signature; resetting CCGx PD controller"
            framework_tool --pd-reset 2 || true
            sleep 5
            echo USBC000:00 > /sys/bus/platform/drivers/ucsi_acpi/unbind 2>/dev/null || true
            sleep 2
            echo USBC000:00 > /sys/bus/platform/drivers/ucsi_acpi/bind 2>/dev/null || true
            touch "$STATE/pd-reset-stamp"
          else
            echo "PD-blind but CCGx reset already fired recently — holding"
          fi
        fi
      '';
      StateDirectory = "tb-link-heal";
    };
  };
  systemd.timers.tb-link-heal = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "2min";
      AccuracySec = "30s";
    };
  };

  # ── eth-fleet, worker half (doctrine: hosts/coordinator/eth-fleet.nix) ────
  # The 5GbE port cabled directly to the coordinator's twin: the fallback
  # rail that shares nothing with USB-C/PD. Fleet identity 10.99.9.2 on lo;
  # peer fleet route via ethernet at metric 200 loses to the tb-fleet route
  # (metric 50, on the imperative tb-fleet profile) whenever TB is alive.
  # Oneshot rather than networking.localCommands — that unit is masked
  # under NetworkManager (see hosts/coordinator/eth-fleet.nix).
  systemd.services.fleet-identity = {
    description = "Stable fleet identity 10.99.9.2/32 on loopback";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-pre.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.iproute2}/bin/ip addr replace 10.99.9.2/32 dev lo";
    };
  };
  networking.networkmanager.ensureProfiles.profiles.eth-fleet = {
    connection = {
      id = "eth-fleet";
      type = "ethernet";
      interface-name = "enp191s0";
      autoconnect = true;
      autoconnect-priority = 50;
    };
    ipv4 = {
      method = "manual";
      addresses = "10.99.1.2/30";
      never-default = true;
      ignore-auto-dns = true;
      # Keyfile routeN syntax — see hosts/coordinator/eth-fleet.nix.
      route1 = "10.99.9.1/32,10.99.1.1,200";
    };
    ipv6.method = "disabled";
  };
  networking.firewall.trustedInterfaces = [ "enp191s0" ];

  # NM at INFO for the same reason the coordinator pins it: on cutover day this
  # fleet's wifi incidents were forensically blind because NetworkManager had
  # logged nothing for weeks. The journal now leaves the box (./journal-upload.nix),
  # so these lines survive even a hard lockup.
  networking.networkmanager.logLevel = "INFO";

  # A REACHABILITY SCARE, RESOLVED — recorded because it will be re-hit and the
  # wrong conclusion is very easy to reach. Mid-reintegration, while this box was
  # still idling on the imperative `thomas6-diag` DHCP profile at 10.42.0.160,
  # the coordinator could not reach it AT ALL: ARP FAILED, 100% packet loss, "No
  # route to host" — while the wired NAS pinged the very same MAC happily and
  # the coordinator reached other wireless clients (the 2.4GHz printer) fine.
  # That pattern reads exactly like AP client isolation on the 6GHz radio, and
  # it was briefly written up here as such. It is NOT: the two boxes hold the
  # SAME MAC on the SAME AP on the SAME radio before and after, so no
  # per-station AP policy can explain one address working and the other not.
  #
  # Once the declarative profile below took over and this host settled on its
  # static 10.42.0.5, coordinator -> worker was verified good on every path that
  # matters: ARP REACHABLE, ping, :3003 answering `pong`, :9292 serving the
  # roster. The likeliest cause of the earlier failure is a stale AP client
  # entry or a wifi idle/power-save interaction on a box that had been sitting
  # untouched for weeks and had no traffic of its own — the NAS had a warm ARP
  # entry precisely because this box talks to it constantly for DHCP and DNS,
  # while the coordinator had never exchanged a packet with it. Not pinned down
  # further, because it did not survive the move to the declarative profile.
  #
  # The operational lesson that DOES survive: an idle wireless box with no
  # traffic of its own is not reliably reachable from a peer station, which is
  # one more reason this host now has a static address, a constant journal
  # upload to the NAS, and a Thunderbolt rail that owes the AP nothing.

  # ── SSH reachability: the one line that must not be got wrong ──────────────
  # The retired closure carried `services.openssh.openFirewall = false` plus a
  # tailscale0-only :22 admission, on the premise that this box was reachable
  # exclusively over the tailnet. Removing tailscale (below) removes tailscale0,
  # which under that premise would leave NO door at all — a headless box in
  # another room with no console. So the override is DELETED and :22 falls back
  # to the NixOS default (open on every interface), exactly matching the
  # coordinator's live posture on the same LAN, in the same trust domain, behind
  # the same NAS NAT. The LAN path (10.42.0.5) is primary; the Thunderbolt rail
  # (10.99.0.2) is the fallback and is covered by the same default.
  #
  # NB the live pre-reintegration box also carried a HAND-ADDED nftables/iptables
  # accept for 10.99.0.1 on thunderbolt0 that exists nowhere in any closure. It
  # disappears at the first switch; that is fine precisely because :22 is open
  # by default now, and is the reason this must not be "tightened" later without
  # re-checking both rails.

  # ── no tailnet on this box ─────────────────────────────────────────────────
  # Same shape the NAS carried before it became the sink (git history of
  # hosts/nas/default.nix pre-2026-08-21). enable alone is not enough: the
  # fleet-wide extraUpFlags/extraSetFlags in modules/common.nix would otherwise
  # remain defined and read as intent. Tom removes the stale worker node from
  # the Tailscale admin console himself; `tailscale logout` runs on the box at
  # verification time so the machine stops holding a node identity.
  services.tailscale.enable = lib.mkForce false;
  services.tailscale.extraUpFlags = lib.mkForce [ ];
  services.tailscale.extraSetFlags = lib.mkForce [ ];

  # agenix delivery. The host key at /etc/ssh/ssh_host_ed25519_key is UNCHANGED
  # across the retirement (verified live 2026-08-21 against the registry row), so
  # the delivered tier re-minted for this box in the same commit decrypts on the
  # first boot of the new closure — no flash, no host-key dance.
  mySecrets.enable = true;
}
