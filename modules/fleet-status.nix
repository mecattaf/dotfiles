{
  config,
  lib,
  pkgs,
  ...
}:
# ─── fleet-status: the graded per-host collector, and the fan-out view ──────
#
# Issue #356, 2026-09-13. Every host gets `fleet-status-collect` plus
# /etc/fleet-status/profile.json, which says what that host is EXPECTED to
# have. The profile is what separates `missing-by-design` from `unknown`: the
# NAS has no user manager by design, while a twin whose user manager does not
# answer is unknown. The coordinator also gets `fleet-status` and
# /etc/fleet-status/hosts.json, and it fans the collector out as
# `ssh root@<name>` over the mesh (modules/mesh.nix already authorizes tom's
# key for root on every host). There is no daemon, no timer and no database.
# DECISIONS.md 2026-09-13 records why.
#
# Roles come from the configuration, not from hostnames, so a moved service
# moves its facts with it:
#   halogen    services.halogen.enable            → podman-halogen*, /health, /cache
#   runs       services.tally-kernel.enable       → both Tally planes, IDs only
#   fara       services.fara-browser-model.enable → the on-demand FARA unit
#   attention  the Herdr server host (home/herdr.nix gates its unit on
#              hostName == "coordinator", and so does this module; the
#              flake's herdr-oom-isolation check pins that shape)
# The profile NAME is still per host, because it names the expectation set in
# the terminal view. An unlisted hostname fails evaluation instead of quietly
# shipping as "unprofiled".
let
  host = config.networking.hostName;

  profileNames = {
    coordinator = "strix-desk";
    worker = "strix-inference";
    nas = "appliance";
    client = "thin-client";
  };

  # The fan-out order is the reading order of the view: the desk first, then
  # the inference box, the appliance and the laptop, which may be asleep.
  order = [
    "coordinator"
    "worker"
    "nas"
    "client"
  ];

  registry = import ./mesh-registry.nix;

  enabled = name: config.services.${name}.enable or false;

  roles =
    lib.optional (enabled "halogen") "halogen"
    ++ lib.optional (enabled "tally-kernel") "runs"
    ++ lib.optional (host == "coordinator") "attention"
    ++ lib.optional (enabled "fara-browser-model") "fara";

  profile = {
    name = profileNames.${host} or "unprofiled";
    # The user manager is expected wherever Home Manager gives tom a session.
    # The NAS is built with withHomeManager = false (flake.nix mkHost).
    user_manager = config ? home-manager;
    inherit roles;
    halogen_port = config.services.halogen.port or 8731;
    # Declared mounts are checked against the live mount table.
    # noauto/automount mounts may legitimately be absent.
    mounts = lib.mapAttrsToList (_: fs: {
      mountpoint = fs.mountPoint;
      on_demand = lib.elem "noauto" fs.options || lib.elem "x-systemd.automount" fs.options;
    }) config.fileSystems;
  };

  hosts = map (name: {
    inherit name;
    profile = profileNames.${name};
    target = "root@${builtins.head registry.${name}.aliases}";
    # Every node, the coordinator included, is collected as root over ssh.
    # A local run as tom cannot read root-only state: #354's update-adopt
    # keeps /var/lib/update-adopt at 0700, so the coordinator's own update
    # facts would stay unknown forever. It would also grade the coordinator
    # through a different code path (no runuser) than the other three.
    # tom → root@coordinator is authorized by the mesh (MEASURED 2026-09-13:
    # `ssh -o BatchMode=yes root@coordinator id -u` → 0). If the coordinator's
    # sshd is broken, the view reads it UNREACHABLE, which is the truth.
    transport = "ssh";
  }) order;

  collectOnly = pkgs.runCommand "fleet-status-collect" { } ''
    mkdir -p "$out/bin"
    ln -s ${pkgs.fleet-status}/bin/fleet-status-collect "$out/bin/fleet-status-collect"
  '';

  isDashboard = host == "coordinator";
in
{
  assertions = [
    {
      assertion = profileNames ? ${host};
      message = "modules/fleet-status.nix: host `${host}` has no fleet-status profile; add it to profileNames.";
    }
    {
      assertion = lib.all (n: registry ? ${n}) order;
      message = "modules/fleet-status.nix: every fan-out host must be in modules/mesh-registry.nix.";
    }
  ];

  environment.etc."fleet-status/profile.json".text = builtins.toJSON profile;
  environment.etc."fleet-status/hosts.json" = lib.mkIf isDashboard {
    text = builtins.toJSON hosts;
  };

  environment.systemPackages = [ (if isDashboard then pkgs.fleet-status else collectOnly) ];
}
