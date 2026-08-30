{
  config,
  lib,
  ...
}:
# Declarative login password for tom — refs #54.
#
# Before this, `users.users.tom` declared no password at all, so a freshly
# flashed host wrote `!` into /etc/shadow and the account was locked: greetd's
# agreety fallback could not log tom in, and `su tom` / screen-lock unlock had
# no credential to check. The only recovery was root running `passwd tom` by
# hand on every new box.
#
# Mechanism: option (a) from the issue, but via `hashedPasswordFile` rather than
# a literal `hashedPassword`. The hash never enters git in plaintext — it is an
# agenix ciphertext (../secrets/tom-password-hash.age), decrypted to a
# root-only /run path at activation. Nothing in this repo generates, contains,
# or defaults a password.
#
# Ordering is safe by construction: agenix sets
# `system.activationScripts.users.deps = [ "agenixInstall" ]`, so the plaintext
# is already at `age.secrets.tom-password-hash.path` when NixOS'
# update-users-groups.pl reads it. (Verified for the classic activation-script
# path, which is what this fleet uses — `systemd.sysusers.enable` and
# `services.userborn.enable` are both false. If either is ever turned on,
# re-check that ordering: agenix switches to a systemd unit ordered *after*
# systemd-sysusers, which would run too late for this.)
#
# CAVEAT — this fixes fresh flashes only, by design of `users.mutableUsers`.
# With mutableUsers = true (the fleet's setting), update-users-groups.pl applies
# a declared hash ONLY when it is creating the shadow entry; for a user that
# already has one it preserves whatever is there. So:
#   * a newly flashed host gets the password automatically — the #54 case;
#   * the coordinator, whose tom already exists with `!`, needs one
#     `sudo passwd tom`, once. (The zenbook-duo was in the same position until
#     it left the fleet on 2026-08-30.)
# Making it authoritative everywhere would mean `users.mutableUsers = false`,
# which is deliberately NOT done here: that also rewrites root's shadow entry to
# `!` unless root is declared too, i.e. it would erase the install-time root
# password that is this fleet's last-resort recovery path.
let
  ciphertext = ../secrets/tom-password-hash.age;

  # LOUD NOTE: agenix turns `age.secrets.<name>.file` into a store path at EVAL
  # time, so declaring the secret while the ciphertext is absent breaks every
  # host build and `nix flake check` — not just activation. Gate on existence,
  # the same pattern modules/secrets.nix already uses for
  # secrets/huggingface-token.age and secrets/wifi.age. The repo therefore
  # evaluates today with no .age file present, and the password starts being
  # delivered on the first rebuild after Tom commits the ciphertext. See the
  # summary/issue for the exact `mkpasswd | agenix -e` invocation.
  havePasswordHash = builtins.pathExists ciphertext;
in
{
  # ...and never the nas. The appliance turned mySecrets.enable ON 2026-08-28 for
  # huggingface-token alone; tom-password-hash is a `delivered`-tier ciphertext
  # that excludes it by construction, so without this guard the flip would have
  # pointed `users.users.tom.hashedPasswordFile` at a secret the box cannot
  # decrypt — locking the account out of the appliance, not merely failing loudly.
  config = lib.mkIf (
    config.mySecrets.enable && havePasswordHash && config.networking.hostName != "nas"
  ) {
    age.secrets.tom-password-hash = {
      file = ciphertext;
      # Read by update-users-groups.pl as root. tom must NOT be able to read his
      # own hash back out of /run, so this stays root:root 0400 rather than
      # following the owner = "tom" pattern of the seeded credentials.
      owner = "root";
      group = "root";
      mode = "400";
    };

    users.users.tom.hashedPasswordFile = config.age.secrets.tom-password-hash.path;
  };
}
