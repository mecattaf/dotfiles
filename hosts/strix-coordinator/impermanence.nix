{
  lib,
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
    "/home" # tom's home: ~/.ssh (keys, known_hosts, the scan upload key), GitHub
    # credentials for the nightly's fleet/ branch, the keyring
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

  # /etc/shadow is rebuilt at every boot. tom's console password comes from a
  # root-only hash file the runbook writes before the first boot; ssh logins
  # use keys and sudo needs no password, so a missing file locks the console
  # password only.
  users.users.tom.hashedPasswordFile = "${persist}/etc/impermanence/tom.hash";
}
