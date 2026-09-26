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
# WHAT IT IS NOW, in one line: a stationary LAN compute node at 10.42.0.5,
# wired into the BE550's Ethernet port 2 in another room from the coordinator
# (no link of any other kind between the two), that owns Immich ML for the
# whole house, ships its journal to the NAS, and is reached over ordinary SSH.
#
# WHAT IT IS NOT:
#   * not a tailnet node — no node identity on any control plane. The
#     2026-08-21 ruling said this as "the NAS is the fleet's single tailscale
#     sink"; since 2026-09-01 the fleet has two tailnets and this box is on
#     neither (the NAS runs its own headscale, the coordinator keeps
#     tailscale.com as the emergency rail).
#   * not a display — no compositor, no greeter, no VNC. THE WORKER HAS NO
#     DISPLAY: that is the whole of the claim, stated without reference to
#     which other boxes do (the 2026-09-11 morning wording "ONLY the
#     coordinator has a display output" was superseded the same afternoon
#     and is not restated here, so no flip elsewhere in the fleet ever needs
#     to come back and edit this paragraph). It opts out of the fleet-wide
#     seat below, and home/voxtype.nix and home/piri.nix ship nothing to a
#     host with no display (home/remote.nix, the VNC half, left the tree
#     with the 2026-09-11 headless flip). Home Manager itself STAYS:
#     tom's shell, atuin, the user timers and the herdr client are all real
#     here; only the graphical session is absent. Console recovery is the VT
#     getty autologin modules/common.nix keeps on every host.
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
#     model-shedding adapter both go. The tripwire's original Layer 2 SSH'd to
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
    ./immich-ml.nix # moved here from the coordinator 2026-08-21 (#229)
    ./journal-upload.nix # sender half of the #135 substrate — Strix boxes only
    ../../modules/cli-anything.nix
    ../../modules/strix.nix
    ../../modules/gvisor.nix # runsc on PATH; gate below (G1, 2026-09-23)
    # TWINS ONLY: kills the stock 127.0.0.2 self-mapping and points both twins'
    # names at their static LAN addresses (#273). Without it gethostname()
    # resolves to loopback, which every distributed library happily binds — the
    # rank-1-hangs-forever failure. The NAS must NOT import this.
    ../../modules/fleet-hosts.nix
    # ax on the fleet: the INFERENCE role, a tainted k3s agent of the NAS
    # since 2026-09-25; see myAxFleet below.
    ../../modules/ax-fleet
    # kubectl + the google/ax binaries, behind myAxClient.enable. Imported on
    # all three interactive hosts, OFF on all three; read that module's header
    # for the runbook and for what it deliberately does not declare.
    ../../modules/ax-client.nix
  ];

  networking.hostName = "worker";

  # ── ax on the fleet: THE kill switch for this host (the INFERENCE role) ──
  # "halogen inference mainly on worker" (Tom, 2026-09-23), and on 2026-09-25,
  # verbatim: "the amd strix halo worker SHOULD be available in the cluster
  # (not just halogen inference)". This box is a k3s AGENT of the NAS
  # (modules/ax-fleet/inference.nix), tainted
  # ax.mecattaf.dev/role=inference:NoSchedule and labelled
  # ate.dev/substrate-version=none, so no pod that runs today lands here: the
  # node is available to a workload that tolerates the taint, and to nothing
  # else. Halogen stays this box's host service, outside the cluster; ax
  # sandboxes on the coordinator still reach 10.42.0.5:8731 through
  # Substrate's egress gateway on the NAS. The kubelet reserves 100Gi for the
  # system, which caps kubepods.slice near 23 GiB of the 125 whatever Halogen
  # is doing (INFERRED from kubelet's default enforce-node-allocatable=pods).
  #
  # Switch order: the NAS (admits 10.42.0.5), then the coordinator (accepts
  # the worker's VXLAN), then this host; and only once
  # secrets/k3s-agent-token.age names this host's key (the gate below). This
  # host adopts candidates on its own (rolling, below); the gate is what keeps
  # an unready join out of a candidate. Rollback: `enable = false`, switch,
  # then `sudo ax-fleet-teardown` (on PATH whatever the switch says). The
  # guards stay for the role whatever `enable` says (modules/ax-fleet/agent.nix).
  myAxFleet = {
    enable = true;
    role = "inference";
    lan = {
      interface = "enp191s0";
      address = "10.42.0.5";
    };
    # No tailnet on this box (services.tailscale.enable = mkForce false,
    # below): there is no tailscale0 to isolate from the LAN leg, so the
    # guard chain renders no tailnet rules here.
    guardInterfaces = [ ];
  };

  # gVisor runsc for direct rootless `runsc run` jobs (modules/gvisor.nix).
  # OFF until Tom flips it; the lane recommends the worker first.
  myGvisor.enable = false;

  # ── no display, no compositor ──────────────────────────────────────────────
  # One line, not two forces: myDisplay.enable (modules/display.nix) is the
  # fleet's "is there a seat here" option, and modules/common.nix derives
  # programs.niri.enable and services.greetd.enable from it — so opting out
  # here turns off the greeter and the compositor together, along with the
  # display-bound user services (voxtype, piri). Nothing graphical
  # runs on this box; VT1 simply gets the getty autologin like the other VTs.
  # The flake asserts every host's niri and greetd EQUAL its myDisplay, so
  # this cannot drift out of agreement in either direction.
  myDisplay.enable = false;

  # ── the LAN identity ───────────────────────────────────────────────────────
  # WIRED. This box lives in another room from the coordinator, and its one
  # link to the house is an Ethernet cable from its 5GbE port (enp191s0) into
  # the BE550's LAN port 2, right beside the NAS's port 1. There is no wifi
  # profile: the mt7925e radio sits idle (its ASPM hardening in
  # modules/strix.nix stays — the silicon is on the board, and a driver that
  # never associates cannot roam-crash).
  #
  # STATIC addressing, same rationale as before the move: this box is
  # stationary and load-bearing — the NAS's Immich dials worker:3003 for every
  # ML batch, the NAS admits 10.42.0.5 for journal upload and the models
  # export, and hosts/nas/network.nix pins the name to this address. None of
  # that may depend on a DHCP round-trip at link-up or on a lease renewal
  # ("anything dns/dhcp related must never bite", 2026-08-21). .5 sits below
  # the NAS's DHCP pool (.10–.200), so the pool can never hand it out.
  #
  # ⚠ ensureProfiles NEVER DELETES a profile it stopped ensuring: any profile
  # this file no longer names must be removed on the box by hand
  # (`nmcli connection delete <name>`), or a stale one can hold 10.42.0.5 on a
  # second interface beside this profile. The 2026-09-11 list is in
  # DECISIONS.md.
  #
  # interface-name IS pinned: the firewall admission this host depends on —
  # :3003 in ./immich-ml.nix — is interface-scoped to enp191s0, so an
  # interface rename must fail loudly here rather than half-work there.
  networking.networkmanager.ensureProfiles.profiles.lan = {
    connection = {
      id = "lan";
      type = "ethernet";
      interface-name = "enp191s0";
      autoconnect = true;
      autoconnect-priority = 110;
    };
    ipv4 = {
      method = "manual";
      address1 = "10.42.0.5/24";
      gateway = "10.42.0.1";
      dns = "10.42.0.1";
      ignore-auto-dns = true;
    };
    ipv6.method = "disabled";
  };

  # ── Borrowing model weights from the NAS Library (2026-08-21 ruling) ──────
  # The NAS exports its models tree read-only + root-squashed to this host
  # (hosts/nas/models.nix, fsid=6). Only an operator's explicit
  # local-models-borrow transaction reads it into /var/lib/local-models;
  # activation, boot, and the Halogen unit's start never touch it.
  # Mounted at /mnt/library, NOT /mnt/nas — because /mnt/nas has a real
  # history on this box (Tom: "/mnt/nas WAS taken — i am no longer using it,
  # since i moved the NAS away from ethernet"): it was this host's genuine
  # NAS path in the ethernet-NAS era, then the worker loan repurposed it as a
  # runtime bind of /home/tom/nas-local (recreated at every boot by
  # /root/worker-loan/reassert.sh — the same machinery that kept resurrecting
  # the OCR serving drop-in; whole plane RETIRED 2026-08-21 evening,
  # archived under /root/worker-loan-RETIRED-2026-08-21, corpus data intact
  # at /home/tom/nas-local). Now that the NAS is the house's wifi router
  # rather than an ethernet peer, the path is deliberately NOT resurrected:
  # this host's only NAS view is the read-only Library, and a distinct name
  # says so — /mnt/nas remains free for whatever history does next.
  # soft+nofail, same hardening rationale as the coordinator's
  # nas-client mount: a dead NAS must never hang this box's boot or I/O
  # forever. Halogen serves whatever is already local.
  boot.supportedFilesystems = [ "nfs" ];
  fileSystems."/mnt/library" = {
    # `nas:/models` — since 2026-09-25 this host's NFSv4 pseudo-root is the
    # NAS storage root (read-only, hosts/nas/storage.nix), so the models tree
    # is a path under it, fsid=6, exactly as the coordinator sees it (see
    # hosts/nas/models.nix). Before that the models tree was the pseudo-root
    # and the device was `nas:/`.
    device = "nas:/models";
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
      # An explicit borrow may be invoked shortly after boot, before the LAN
      # link has settled. `_netdev` cannot distinguish the link being up from
      # the NAS actually being reachable, so gate that on NAS reality.
      # Nothing in the boot/update graph accesses this lazy automount.
      "x-systemd.requires=library-reachable.service"
    ];
  };

  # ── The academic-papers corpus, read from the NAS (2026-09-25) ────────────
  # Tom: "nas is where the pdf files are"; "all running on the worker
  # overnight". mecattaf/academic-drain runs lane A (pdftotext) and lane B
  # (Halogen vision) on this host and records every PDF by its coordinator
  # path, /mnt/nas/documents/academic-papers/..., so the same path must
  # resolve here. This is the ONLY resurrection of /mnt/nas on this box, and
  # it is a read-only NFS automount of the documents export, not the
  # loan-era bind of /home/tom/nas-local (retired 2026-08-21, see above).
  # Same hardening as /mnt/library: soft, nofail, lazy automount gated on the
  # NAS answering; a dead NAS costs the drain a page (exit 69, no row), never
  # this box's boot. The staged copy under
  # ~/.local/state/academic-drain/corpus that carried the first night can be
  # deleted once `ls /mnt/nas/documents/academic-papers/originals` answers.
  fileSystems."/mnt/nas/documents" = {
    device = "nas:/documents";
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
      "x-systemd.requires=library-reachable.service"
    ];
  };

  # drain.internal: the academic-drain dashboard (dashboard/serve.sh
  # --bind 10.42.0.5 --port 8740) is fronted by the coordinator's Caddy
  # (hosts/coordinator/default.nix) and resolved by AdGuard
  # (modules/adguardhome.nix). LAN interface only, like immich-ml's :3003.
  networking.firewall.interfaces.enp191s0.allowedTCPPorts = [ 8740 ];
  systemd.services.library-reachable = {
    description = "Wait for the NAS Library export to answer before NFS mounts it";
    serviceConfig = {
      Type = "oneshot";
      # Stay active once passed: this gate exists for the boot race only, so
      # later automount triggers (after the 10min idle unmount) must not
      # re-serialize behind a fresh wait.
      RemainAfterExit = true;
      TimeoutStartSec = "3min";
      # 120s covers link-up plus the NAS's own boot with room; then proceed
      # regardless — a genuinely dead NAS makes an explicit borrow fail while
      # Halogen continues serving what is local.
      ExecStart = pkgs.writeShellScript "wait-library-reachable" ''
        for _ in $(${pkgs.coreutils}/bin/seq 120); do
          if ${pkgs.bash}/bin/bash -c 'exec 3<>/dev/tcp/nas/2049' 2>/dev/null; then
            exit 0
          fi
          ${pkgs.coreutils}/bin/sleep 1
        done
        echo "nas:2049 unreachable after 120s; letting mount.nfs4 try anyway" >&2
      '';
    };
  };
  # ── NFS readahead: undo the kernel's 128KB default (2026-08-29) ──────────
  # Same fix as the coordinator's nfs-nas-readahead (hosts/coordinator/
  # nas-client.nix — full lore and the live A/B measurements there: 88 →
  # 113 MB/s, within ~6% of raw TCP). Kernel ≥5.18 gives every NFS mount a
  # 128KB bdi readahead window regardless of rsize, which starves the RPC
  # pipeline on the LAN path's RTT and was the real "650 Mbps hotload
  # ceiling" all along. Hooked to the mount unit because the bdi is recreated
  # at the kernel default on every automount trigger — and this mount cycles
  # every 10 idle minutes (x-systemd.idle-timeout above), so a boot-time
  # setter would be reverted within the hour.
  systemd.services.nfs-library-readahead = {
    description = "Raise NFS readahead on /mnt/library (kernel default 128KB caps the LAN path at ~88MB/s)";
    wantedBy = [ "mnt-library.mount" ];
    after = [ "mnt-library.mount" ];
    serviceConfig.Type = "oneshot";
    # Same findmnt guard as the coordinator's setter: the mount JOB fires this
    # unit even when mount.nfs4 itself failed, and `mountpoint -d` then
    # answers with the autofs trigger's bdi, which has no read_ahead_kb.
    script = ''
      ${pkgs.util-linux}/bin/findmnt --type nfs4 --mountpoint /mnt/library >/dev/null || exit 0
      echo 16384 > "/sys/class/bdi/$(${pkgs.util-linux}/bin/mountpoint -d /mnt/library)/read_ahead_kb"
    '';
  };

  services.local-models.libraryPath = "/mnt/library/weights";

  # ── the fleet's resident inference server ─────────────────────────────────
  # Halogen Flash holds this box's GPU and most of its memory for the life of
  # the process. Both twins declare the same Halogen server and 27B alternate
  # in modules/strix.nix (so the two cannot drift); only here does Flash start
  # at boot, and the coordinator's utility-model dials http://worker:8731.

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
  # matters: ARP REACHABLE, ping, :3003 answering `pong`, the model port
  # serving. The likeliest cause of the earlier failure is a stale AP client
  # entry or a wifi idle/power-save interaction on a box that had been sitting
  # untouched for weeks and had no traffic of its own — the NAS had a warm ARP
  # entry precisely because this box talks to it constantly for DHCP and DNS,
  # while the coordinator had never exchanged a packet with it. Not pinned down
  # further, because it did not survive the move to the declarative profile.
  #
  # The operational lesson that DOES survive: an idle wireless box with no
  # traffic of its own is not reliably reachable from a peer station, which is
  # one more reason this host has a static address, a constant journal upload
  # to the NAS, and no wireless leg at all — it is wired into the BE550, and
  # the AP is out of the picture.

  # ── SSH reachability: the one line that must not be got wrong ──────────────
  # The retired closure carried `services.openssh.openFirewall = false` plus a
  # tailscale0-only :22 admission, on the premise that this box was reachable
  # exclusively over the tailnet. Removing tailscale (below) removes tailscale0,
  # which under that premise would leave NO door at all — a headless box in
  # another room with no console. So the override is DELETED and :22 falls back
  # to the NixOS default (open on every interface), exactly matching the
  # coordinator's live posture on the same LAN, in the same trust domain, behind
  # the same NAS NAT. The LAN path (10.42.0.5) is the ONLY path — there is no
  # second rail to fall back to, which is one more reason :22 stays on the
  # default (every interface) rather than an interface-scoped admission that a
  # NIC rename could silently close.

  # ── no tailnet on this box ─────────────────────────────────────────────────
  # Tom's #229 ruling, unchanged: this is a stationary LAN compute node reached
  # over ordinary SSH, and it holds no node identity anywhere. He removed the
  # stale worker node from the Tailscale admin console himself; `tailscale
  # logout` ran on the box at verification time.
  #
  # This block used to carry two more lines — `extraUpFlags`/`extraSetFlags`
  # mkForced to [ ] — and its comment explained exactly why: "enable alone is
  # not enough: the fleet-wide extraUpFlags/extraSetFlags in modules/common.nix
  # would otherwise remain defined and read as intent." That reason DIED on
  # 2026-09-01, when the fleet-wide tailscale tier was retired to
  # hosts/coordinator/tailscale.nix. Both lists are now empty by default, so the
  # overrides had nothing left to override, and keeping a mkForce under a
  # justification that is no longer true is how a reader learns to distrust the
  # comments. They are gone; flake.nix still asserts both lists empty, which is
  # now a tripwire on modules/common.nix rather than a check on this file.
  #
  # The enable line STAYS, and stays mkForce. It is not defending against
  # today's tree — nothing sets it true any more — it is the standing statement
  # that this box must not acquire a tailnet by inheritance. The fleet just
  # demonstrated that a module can hand every host a daemon it never asked for,
  # and this is the one host where that must fail loudly rather than quietly
  # work. It is also what keeps modules/secrets.nix from declaring an authkey
  # here: that block is gated on `services.tailscale.enable`, and a stale key
  # would silently re-join the box on its next flash.
  #
  # If this host ever DOES rejoin a tailnet, it joins the NAS's headscale
  # (hosts/nas/headscale.nix), not tailscale.com — that control plane survives
  # on the coordinator alone, as the emergency rail, and widening it is not the
  # way to give a LAN box a tailnet.
  services.tailscale.enable = lib.mkForce false;

  # agenix delivery. The host key at /etc/ssh/ssh_host_ed25519_key is UNCHANGED
  # across the retirement (verified live 2026-08-21 against the registry row), so
  # the delivered tier re-minted for this box in the same commit decrypts on the
  # first boot of the new closure — no flash, no host-key dance.
  mySecrets.enable = true;

  # ── the agent token must name THIS host before k3s runs here ─────────────
  # modules/ax-fleet/k3s.nix delivers secrets/k3s-agent-token.age here as
  # k3s's --token-file. secrets.nix lists this host as a recipient since
  # 2026-09-25, but a recipient list is not a ciphertext: the file minted on
  # 2026-09-23 is sealed to the admin key, the coordinator (b4VnIg) and the NAS
  # (sKUETw) only (MEASURED, `grep -a '^->'`). Switched before the rekey,
  # agenix cannot decrypt it and k3s restarts forever with no token
  # (Type=exec, Restart=always), unattended: this host adopts the NAS's
  # candidates on its own (rolling, below). So the refusal lives in the build,
  # where the NAS's nightly build of this host fails and publishes nothing:
  #   - evaluation: the worker-less mint, by content hash. Reading the stanza
  #     tags at evaluation is not an option: builtins.readFile refuses a file
  #     holding a NUL byte ("cannot be represented as a Nix string", and
  #     tryEval does not catch it; MEASURED on Nix 2.34.8), and an age payload
  #     is random bytes, 96 of them after this file's 388-byte header, so a
  #     re-mint has about a 31 % chance (1 - (255/256)^96) of holding one.
  #   - build (system.checks): the ciphertext's header carries this host's
  #     stanza, `-> ssh-ed25519 <tag> ...`, with the tag derived from the
  #     registry key the way age derives it (base64, unpadded, of the first
  #     4 bytes of the SHA-256 of the SSH wire-format public key). TKMZIQ for
  #     today's key: MEASURED 2026-09-25, computed from the registry and
  #     stamped by age itself on a test mint; it matches the tag REPORTED in
  #     ~/today/evals-2026-09-23/ax-fleet/REVIEW-LOG.md:82.
  #     This one stays as the standing check: a mint without this host, or a
  #     reflash with a new host key, fails it too.
  # Both only where the agenix ciphertext is what this host would read
  # (a test token file declares no secret, see k3s.nix).
  # The rekey, Tom's (same plaintext: the live NAS and coordinator use it):
  #   cd ~/mecattaf/dotfiles && EDITOR=: nix develop -c agenix -e secrets/k3s-agent-token.age -i <admin identity>
  # never `agenix -r`, which re-encrypts every file in secrets.nix.
  assertions =
    let
      # sha256 of secrets/k3s-agent-token.age as minted 2026-09-23 (MEASURED
      # `sha256sum`, at origin/main 47f3b540).
      workerlessMint = "8365a83e47425623da5250b0693111eea902768307c5152e0cb57eccf5635c2b";
    in
    [
      {
        assertion =
          !(config.age.secrets ? k3s-agent-token)
          || builtins.hashFile "sha256" config.age.secrets.k3s-agent-token.file != workerlessMint;
        message = ''
          hosts/worker/default.nix: secrets/k3s-agent-token.age is still the 2026-09-23 mint (sha256 ${workerlessMint}), sealed to the admin key, the coordinator and the NAS only. This host cannot decrypt it, so its k3s agent would restart forever with no token. Re-encrypt that one file to the recipients secrets.nix lists (the worker among them), keeping the plaintext, and commit it:
            cd ~/mecattaf/dotfiles && EDITOR=: nix develop -c agenix -e secrets/k3s-agent-token.age -i <admin identity>
          Not `agenix -r` (it re-encrypts every secret). Check: grep -a '^-> ssh-ed25519' secrets/k3s-agent-token.age | cut -d' ' -f3 lists TKMZIQ. Then switch the NAS, the coordinator, and this host last.'';
      }
    ];
  system.checks = lib.optional (config.age.secrets ? k3s-agent-token) (
    pkgs.runCommand "ax-fleet-agent-token-names-worker"
      {
        hostKey = (import ../../modules/mesh-registry.nix).worker.hostKey;
        ciphertext = config.age.secrets.k3s-agent-token.file;
      }
      ''
        tag=$(printf '%s' "$hostKey" | cut -d' ' -f2 | base64 -d | sha256sum | cut -c1-8 \
          | tr a-f A-F | basenc --base16 -d | base64 | tr -d '=')
        # The header only: every line before the `--- <mac>` line.
        awk '/^--- /{exit} {print}' "$ciphertext" > header
        if ! grep -q -x -E -- "-> ssh-ed25519 $tag [A-Za-z0-9+/]+" header; then
          echo "secrets/k3s-agent-token.age has no stanza for the worker (ssh-ed25519 tag $tag, from modules/mesh-registry.nix); it carries:" >&2
          grep -- '^-> ' header | cut -d' ' -f2,3 >&2
          echo "Re-encrypt it, same plaintext: cd ~/mecattaf/dotfiles && EDITOR=: nix develop -c agenix -e secrets/k3s-agent-token.age -i <admin identity>" >&2
          exit 1
        fi
        echo "k3s-agent-token.age names the worker (tag $tag)" > "$out"
      ''
  );

  # OFF, and it stays OFF (modules/ax-client.nix). This host is a cluster
  # node now, but an agent is not a client: kubectl and ax are the
  # coordinator's (the harness role turns them on there), and nothing here
  # needs the admin kubeconfig. The flip is Tom's, one host at a time, and
  # ax-client-topology in flake.nix goes red on it by design.
  myAxClient.enable = false;

  # ── Fleet candidate adoption (#354, 2026-09-13): ROLLING ─────────────────
  # The worker adopts the NAS's signed nightly candidate on its own when it is
  # safe to disturb (modules/update-adopt.nix). "Safe" here is one fact: the
  # one inference server is not serving. halogen-idle defers on /health
  # in_flight/queued and on any established :8731 session (Halogen runs
  # --network=host); an ACTIVE alternate means an operator is mid-experiment
  # (`halogen-switch qwen38-27b`), so that defers too. After a switch, Halogen
  # must answer /health status ok within the 10-minute probe window (it
  # re-reads a 30 GB loan on restart) or the switch is rolled back.
  myUpdateAdopt = {
    enable = true;
    policy = "rolling";
    userManagers = [ "tom" ];
    gates = [
      {
        name = "halogen-idle";
        argv = [
          config.myUpdateAdopt.gatesBin
          "halogen-idle"
          "8731"
        ];
      }
      {
        name = "halogen-alternate";
        argv = [
          config.myUpdateAdopt.gatesBin
          "units-inactive"
          "system"
        ]
        ++ map (name: "podman-halogen-${name}.service") (
          builtins.attrNames config.services.halogen.alternates
        );
      }
      # The academic OCR drain's lane B batch (2026-09-25; the coordinator submits it nightly,
      # hosts/coordinator services.academicDrain.standing). lane_b_batch.py holds this flock for a whole
      # batch (lane_b_batch.py:361-365), but halogen-idle can read idle between two pages, so a switch
      # that restarts podman-halogen mid-batch would end the night as an 'outage' yield
      # (ocr.substrate.workflow.js:127, INFERRED). Defer while the lock is held; a missing file is free.
      {
        name = "academic-drain-lane-b";
        argv = [
          config.myUpdateAdopt.gatesBin
          "flock-free"
          "/home/tom/.local/state/academic-drain/lane-b/main/.lane-b.lock"
        ];
      }
    ];
    probes = [
      {
        name = "halogen-healthy";
        argv = [
          config.myUpdateAdopt.gatesBin
          "halogen-healthy"
          "8731"
        ];
      }
    ];
    criticalUnits = [ { unit = "podman-halogen.service"; } ];
  };
}
