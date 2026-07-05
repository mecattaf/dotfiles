{ config, lib, ... }:
# agenix secret DELIVERY on a host.
#
# Gated behind `mySecrets.enable` (default OFF) so a fresh flash can NEVER fail
# activation because a host key wasn't delivered. Flip it on per host (or in
# common.nix) once the first boot has proven the `nixos-anywhere --extra-files`
# host-key delivery worked and `agenix` decrypts cleanly.
#
# Each host decrypts with its own /etc/ssh/ssh_host_ed25519_key (agenix default
# identity). The recipient ACL lives in ../secrets.nix. Only secrets whose ciphertext
# already exists are declared here; add the rest as they are encrypted.
let
  cfg = config.mySecrets;
in
{
  options.mySecrets.enable = lib.mkEnableOption "agenix secret delivery on this host";

  config = lib.mkIf cfg.enable {
    age.secrets.claude-credentials = {
      file = ../secrets/claude-credentials.age;
      owner = "tom";
      group = "users";
      mode = "600";
    };

    # Seed the Claude Code OAuth credential once into a WRITABLE path Claude owns —
    # agenix delivers a read-only /run/agenix symlink, but Claude must rewrite the
    # file on token refresh, so copy rather than link, and only if absent.
    system.userActivationScripts.seedClaudeCreds.text = ''
      cred="$HOME/.claude-main/.credentials.json"
      if [ ! -e "$cred" ] && [ -r "${config.age.secrets.claude-credentials.path}" ]; then
        mkdir -p "$HOME/.claude-main"
        cp "${config.age.secrets.claude-credentials.path}" "$cred"
        chmod 600 "$cred"
      fi
    '';
  };
}
