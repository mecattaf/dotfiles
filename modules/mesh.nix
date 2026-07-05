{ lib, ... }:
# SSH mesh trust, derived from the single-source registry. Every host with a
# recorded host key is pre-seeded into known_hosts (no TOFU prompt); every recorded
# user key is authorized for tom on every host (any box → any box).
#
# Deterministic host *identity* (so known_hosts can be trusted before a host's first
# boot) comes from the secrets layer wiring the private host keys — see the agenix
# work. Until a host's keys are recorded here, it is simply omitted, keeping the
# config valid.
let
  registry = import ./mesh-registry.nix;
  nonEmpty = s: s != "";

  # Operator keys that may also log in as tom (used to reach freshly-flashed hosts
  # from the controller during the flash campaign).
  operatorKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHuyYcI6TtVr2UBvyFXySczeRX+1tnaU3lJ8BdyVvw9s flasher@harness-20260427"
  ];
in
{
  programs.ssh.knownHosts = lib.mapAttrs (_: h: {
    hostNames = h.aliases;
    publicKey = h.hostKey;
  }) (lib.filterAttrs (_: h: nonEmpty h.hostKey) registry);

  users.users.tom.openssh.authorizedKeys.keys = lib.unique (
    lib.filter nonEmpty (lib.mapAttrsToList (_: h: h.userKey) registry) ++ operatorKeys
  );
}
