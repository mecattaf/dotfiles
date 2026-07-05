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

    # Tailscale: join the tailnet on first boot with this host's own pre-auth key
    # (per-host .age; single-use, non-ephemeral, preauthorized, tag:mesh — tagged
    # nodes get key expiry disabled on first auth, so the device never logs out).
    # The autoconnect unit only runs `tailscale up` while BackendState=NeedsLogin,
    # so an already-joined node never re-auths on rebuilds, and rotating the .age
    # ciphertext is a no-op until a `tailscale logout`.
    age.secrets.tailscale-authkey.file =
      ../secrets + "/tailscale-authkey-${config.networking.hostName}.age";

    services.tailscale = {
      authKeyFile = config.age.secrets.tailscale-authkey.path;
      authKeyParameters = {
        ephemeral = false;
        preauthorized = true;
      };
    };

    # The stock autoconnect unit orders only after tailscaled; make it wait for
    # agenix's /run/agenix.d mount too, or it can race the key's decryption at boot.
    systemd.services.tailscaled-autoconnect = {
      after = [ "run-agenix.d.mount" ];
      wants = [ "run-agenix.d.mount" ];
    };
  };
}
