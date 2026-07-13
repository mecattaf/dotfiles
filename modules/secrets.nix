{
  config,
  lib,
  pkgs,
  ...
}:
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

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      # Claude Code OAuth credential — every host EXCEPT the zenbook (jul12 ruling:
      # the laptop is a standalone backup operator for when the coordinator is
      # unreachable, so it logs in with its OWN fresh OAuth session instead of
      # inheriting the coordinator's token — two devices refreshing one shared
      # token can race and sign each other out).
      (lib.mkIf (config.networking.hostName != "zenbook-duo") {
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
      })

      {
        # hermes-agent (Nous Research AI harness) OAuth state — single JSON file
        # covering access/refresh tokens + agent_key. Copy-not-link: hermes rewrites
        # it on token refresh, same reasoning as claude-credentials above.
        age.secrets.hermes-credentials = {
          file = ../secrets/hermes-credentials.age;
          owner = "tom";
          group = "users";
          mode = "600";
        };
        system.userActivationScripts.seedHermesCreds.text = ''
          cred="$HOME/.hermes/auth.json"
          if [ ! -e "$cred" ] && [ -r "${config.age.secrets.hermes-credentials.path}" ]; then
            mkdir -p "$HOME/.hermes"
            cp "${config.age.secrets.hermes-credentials.path}" "$cred"
            chmod 600 "$cred"
          fi
        '';

        # Mesh SSH user key (the shared `tom@mesh` private half). mesh.nix already
        # authorizes this key + seeds known_hosts on every host; this delivers the
        # PRIVATE key so each box can also SSH *out* (any box → any box), and so
        # `nixos-rebuild --target-host` works from anywhere. Encrypted to every host
        # key (common tier), so a reflash restores it automatically — no more manual
        # ~/.ssh provisioning. Copy-not-link: ssh wants a real 600 file tom owns.
        age.secrets.ssh-user-key = {
          file = ../secrets/ssh-user-key.age;
          owner = "tom";
          group = "users";
          mode = "600";
        };
        system.userActivationScripts.seedSshUserKey.text = ''
          key="$HOME/.ssh/id_ed25519"
          if [ ! -e "$key" ] && [ -r "${config.age.secrets.ssh-user-key.path}" ]; then
            mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
            cp "${config.age.secrets.ssh-user-key.path}" "$key"
            chmod 600 "$key"
            ${pkgs.openssh}/bin/ssh-keygen -y -f "$key" > "$key.pub" 2>/dev/null || true
            chmod 644 "$key.pub" 2>/dev/null || true
          fi
        '';

        # A ROOT-owned copy of the same tom@mesh private key, for the nix-daemon (root)
        # and other root-context clients that must SSH OUT across the mesh: distributed
        # builds (modules/build-offload.nix) and the fleet-update failure mirror
        # (modules/fleet-notify.nix). Same ciphertext, delivered 0400 root — ssh refuses
        # a key it can't cleanly own, which a tom-owned /run/agenix path would trip.
        age.secrets.ssh-root-key = {
          file = ../secrets/ssh-user-key.age;
          owner = "root";
          group = "root";
          mode = "400";
        };

        # Tailscale: join the tailnet on first boot with this host's own pre-auth key
        # (per-host .age; single-use, non-ephemeral, preauthorized, tag:mesh — tagged
        # nodes get key expiry disabled on first auth, so the device never logs out).
        # The autoconnect unit only runs `tailscale up` while BackendState=NeedsLogin,
        # so an already-joined node never re-auths on rebuilds, and rotating the .age
        # ciphertext is a no-op until a `tailscale logout`.
        age.secrets.tailscale-authkey.file =
          ../secrets + "/tailscale-authkey-${config.networking.hostName}.age";

        # No authKeyParameters: they append `?ephemeral=…&preauthorized=…` to the key,
        # which the control plane accepts only for OAuth client secrets used as auth
        # keys — a pre-minted tskey-auth key gets rejected as "invalid key" (bit the
        # worker live, jul5). Our keys carry those properties from mint time.
        services.tailscale.authKeyFile = config.age.secrets.tailscale-authkey.path;

        # The stock autoconnect unit orders only after tailscaled; make it wait for
        # agenix's /run/agenix.d mount too, or it can race the key's decryption at boot.
        # It also raced the uplink on the coordinator's first boot (the boot-time
        # `tailscale up` predated wifi, so the join needed a manual restart, refs #37):
        # order after network-online.target and retry with backoff so a late uplink
        # (wifi associating after the unit fired) self-heals instead of staying down.
        systemd.services.tailscaled-autoconnect = {
          after = [
            "run-agenix.d.mount"
            "network-online.target"
          ];
          wants = [
            "run-agenix.d.mount"
            "network-online.target"
          ];
          serviceConfig = {
            Restart = "on-failure";
            RestartSec = "10s";
          };
        };
      }

      # Operator CLI credentials — coordinator ONLY (the ciphertexts aren't decryptable
      # by other hosts, and declaring an undecryptable secret fails activation, so the
      # whole block must be host-gated). Same copy-don't-link pattern as the claude
      # cred: both CLIs rewrite their file on token refresh.
      (lib.mkIf (config.networking.hostName == "coordinator") {
        age.secrets.gh-hosts = {
          file = ../secrets/gh-hosts.age;
          owner = "tom";
          group = "users";
          mode = "600";
        };
        age.secrets.wrangler-config = {
          file = ../secrets/wrangler-config.age;
          owner = "tom";
          group = "users";
          mode = "600";
        };

        system.userActivationScripts.seedOperatorCreds.text = ''
          gh="$HOME/.config/gh/hosts.yml"
          if [ ! -e "$gh" ] && [ -r "${config.age.secrets.gh-hosts.path}" ]; then
            mkdir -p "$HOME/.config/gh"
            cp "${config.age.secrets.gh-hosts.path}" "$gh"
            chmod 600 "$gh"
          fi
          wr="$HOME/.config/.wrangler/config/default.toml"
          if [ ! -e "$wr" ] && [ -r "${config.age.secrets.wrangler-config.path}" ]; then
            mkdir -p "$HOME/.config/.wrangler/config"
            cp "${config.age.secrets.wrangler-config.path}" "$wr"
            chmod 600 "$wr"
          fi
        '';

        # gws (Google Workspace CLI, personal account) — coordinator-only, same
        # ruling as gh/wrangler above. Four files, copy-not-link throughout: gws
        # rewrites credentials.enc + token_cache.json on token refresh, and
        # client_secret.json/.encryption_key travel alongside them for consistency.
        # See ~/.config/gws/HANDOFF.md (2026-07-10) for full provenance/rationale.
        age.secrets.gws-client-secret = {
          file = ../secrets/gws-client-secret.age;
          owner = "tom";
          group = "users";
          mode = "600";
        };
        age.secrets.gws-credentials = {
          file = ../secrets/gws-credentials.age;
          owner = "tom";
          group = "users";
          mode = "600";
        };
        age.secrets.gws-encryption-key = {
          file = ../secrets/gws-encryption-key.age;
          owner = "tom";
          group = "users";
          mode = "600";
        };
        age.secrets.gws-token-cache = {
          file = ../secrets/gws-token-cache.age;
          owner = "tom";
          group = "users";
          mode = "600";
        };
        system.userActivationScripts.seedGwsCreds.text = ''
          mkdir -p "$HOME/.config/gws"
          dst="$HOME/.config/gws/client_secret.json"
          if [ ! -e "$dst" ] && [ -r "${config.age.secrets.gws-client-secret.path}" ]; then
            cp "${config.age.secrets.gws-client-secret.path}" "$dst"
            chmod 600 "$dst"
          fi
          dst="$HOME/.config/gws/credentials.enc"
          if [ ! -e "$dst" ] && [ -r "${config.age.secrets.gws-credentials.path}" ]; then
            cp "${config.age.secrets.gws-credentials.path}" "$dst"
            chmod 600 "$dst"
          fi
          dst="$HOME/.config/gws/.encryption_key"
          if [ ! -e "$dst" ] && [ -r "${config.age.secrets.gws-encryption-key.path}" ]; then
            cp "${config.age.secrets.gws-encryption-key.path}" "$dst"
            chmod 600 "$dst"
          fi
          dst="$HOME/.config/gws/token_cache.json"
          if [ ! -e "$dst" ] && [ -r "${config.age.secrets.gws-token-cache.path}" ]; then
            cp "${config.age.secrets.gws-token-cache.path}" "$dst"
            chmod 600 "$dst"
          fi
        '';
      })

      # Coordinator's Freebox wifi uplink (wlp192s0) PSK — delivered as a root-owned
      # NetworkManager environment file that uplink-nas.nix's ensureProfiles reads
      # via `$FREEBOX_PSK`. Guarded on the ciphertext EXISTING so eval/activation
      # never break if secrets/wifi.age is ever absent; it is committed (since
      # 2026-07-11, refs #37) so this delivery + the freebox-uplink profile are live.
      (lib.mkIf (config.networking.hostName == "coordinator" && builtins.pathExists ../secrets/wifi.age) {
        age.secrets.wifi.file = ../secrets/wifi.age;
      })
    ]
  );
}
