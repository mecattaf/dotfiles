{
  lib,
  pkgs,
  ...
}:
# ─── strix-coordinator: a root wiped at every boot (prepared 2026-11-25) ─────
# Tom, 2026-11-25: "re strix reboot you ca go ahead with it", with
# impermanence in the same pass. Deploy it only through the one-shot boot in
# the description of the PR that adds this file (stage with `nix-env --set`
# and `switch-to-configuration boot`, keep the old entry as the EFI default,
# `bootctl set-oneshot` the new one), never with `switch`: a switch cannot
# move /, and a failed first boot must fall back to the old generation.
#
# Layout, chosen from the real disk (one 930 GB ext4 partition, no btrfs, so
# no subvolume rollback): `/` is a tmpfs, and the ext4 partition that was `/`
# is mounted at /persist. Its old contents stay where they were, so every
# declared path below is bound from /persist<path> without copying a byte:
# /persist/nix is the store that was /nix, /persist/home the home that was
# /home. Everything not declared here starts empty at each boot. The old,
# undeclared contents (the old /tmp, /var/tmp, /var/cache, /root, ...) stay
# visible under /persist until they are deleted by hand after the first boot;
# nothing is hidden under a mount point.
#
# Scratch that must not use RAM: /tmp and /var/tmp are bound from new,
# separate directories under /persist/scratch (the old /tmp and /var/tmp are
# left alone). /tmp, where builds and the nightly's clones go, is emptied at
# every boot; /var/tmp keeps systemd's 30-day ageing, as its meaning requires.
#
# Measuring free space: `df -h /` now describes the tmpfs. The store's disk is
# `df -h /nix`, which is the same number as `df -h /` before this change.
let
  persist = "/persist";
  bindFrom = source: {
    device = source;
    fsType = "none";
    options = [ "bind" ];
  };
  same = path: bindFrom "${persist}${path}";

  # Needed by the activation script, which runs in the initrd.
  bootDirs = [
    "/nix"
    "/var/lib/nixos" # uid and gid allocations: files on /persist keep their owners
  ];

  dirs = [
    "/home" # on disk, but pruned to homeKeep at every boot (see below)
    "/var/log" # the journal
    "/var/lib/systemd" # linger (the nightly's systemd-run --user), timer stamps, random seed, coredumps
    "/var/lib/private" # DynamicUser state
    "/var/lib/local-models" # the model store Gufo, llama-swap, D3 and Qwen TTS read
    "/var/lib/tailscale" # the node identity
    "/var/lib/NetworkManager" # secret_key: stable DHCP and IPv6 identity
    "/etc/NetworkManager/system-connections" # the Freebox fallback connection (imperative)
    "/etc/credstore.encrypted" # keyring-seal's TPM-sealed credential
    "/var/lib/failure-markers"
    "/var/lib/tripwire"
  ];

  # tom's home keeps only these paths across a boot (Tom, 2026-11-25: strix
  # is lean and impermanent; ~/compute "is EXACTLY what must be removed as
  # part of an impermanent configuration"). Everything else in it, such as
  # ~/compute, ~/.wt, ~/.cache and old tool state, is removed at every boot
  # before /home is mounted. home-manager links its files again at boot.
  # Home stays on the disk rather than in the 4 GiB RAM root, because the
  # nightly's builds run as tom and fill ~/.cache/nix while strix is up.
  # Paths are relative to the home.
  homeKeep = [
    ".ssh" # the key strix uses for nix copy and git over SSH, known_hosts, and
    # authorized_keys, the only place the scanner's restricted upload key is
    ".local/share/keyrings" # the keyring keyring-unlock-boot opens with the TPM-sealed password
    ".local/state/home-manager" # home-manager's generation record and GC root,
    ".local/state/nix" # and the per-user profiles it uses, so the boot
    ".nix-profile" # activation stays a re-activation, not a first install
    ".bash_history" # shell history
    ".local/share/fish" # shell history (fish_history)
    ".local/share/atuin" # shell history and atuin's own key
    ".terminfo" # kitty's terminfo for ssh from the Zenbook, not installed system-wide
    ".local/state/fleet-deploy" # failure-marker episodes a shell already showed;
    # the markers themselves persist in /var/lib/failure-markers
  ];

  homePrune = pkgs.writeShellApplication {
    name = "home-prune";
    runtimeInputs = [ pkgs.coreutils ];
    text = builtins.readFile ./home-prune.sh;
  };
in
{
  # The ext4 partition keeps its partuuid; only its mount point moves.
  disko.devices.disk.main.content.partitions.root.content.mountpoint = lib.mkForce persist;
  disko.devices.nodev."/" = {
    fsType = "tmpfs";
    mountOptions = [
      "size=4G"
      "mode=755"
    ];
  };

  fileSystems = {
    ${persist}.neededForBoot = true;
    "/tmp" = bindFrom "${persist}/scratch/tmp";
    "/var/tmp" = bindFrom "${persist}/scratch/var-tmp";
  }
  // lib.genAttrs bootDirs (p: same p // { neededForBoot = true; })
  // lib.genAttrs dirs same;

  boot.tmp.cleanOnBoot = true;

  # Prune tom's home to homeKeep once per boot, after the disk is mounted at
  # /persist and before /home is bound from it. A failure is logged and does
  # not stop the boot: /home then mounts unpruned, as before this change.
  systemd.services.home-prune = {
    description = "Prune tom's home to the declared paths";
    unitConfig = {
      DefaultDependencies = false;
      RequiresMountsFor = [ "${persist}/home" ];
    };
    before = [ "home.mount" ];
    wantedBy = [ "home.mount" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${homePrune}/bin/home-prune ${persist}/home/tom ${lib.escapeShellArgs homeKeep}";
    };
  };

  # Host identity read straight from /persist: no copy in /etc to go stale.
  environment.etc."machine-id".source = "${persist}/etc/machine-id";
  services.openssh.hostKeys = [
    {
      path = "${persist}/etc/ssh/ssh_host_ed25519_key";
      type = "ed25519";
    }
    {
      path = "${persist}/etc/ssh/ssh_host_rsa_key";
      type = "rsa";
      bits = 4096;
    }
  ];
  age.identityPaths = [
    "${persist}/etc/ssh/ssh_host_ed25519_key"
    "${persist}/etc/ssh/ssh_host_rsa_key"
  ];

  # A headless box whose root account is locked must not wait at an emergency
  # prompt nobody can open. A failure in the initrd (no /persist, no /nix)
  # panics and reboots after 30 s; during the trial the one-shot entry is spent
  # by then, so the previous default generation starts. A failed mount in
  # stage 2 does not stop the boot, so sshd (its keys are on /persist, mounted
  # in the initrd) stays reachable for the checks and the rollback.
  boot.kernelParams = [
    "boot.panic_on_fail"
    "panic=30"
  ];
  systemd.enableEmergencyMode = false;

  # /etc/shadow is rebuilt at every boot. tom's console password comes from a
  # root-only hash file the runbook writes before the first boot; ssh logins
  # use keys and sudo needs no password, so a missing file locks the console
  # password only.
  users.users.tom.hashedPasswordFile = "${persist}/etc/impermanence/tom.hash";
}
