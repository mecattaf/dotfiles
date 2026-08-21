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
  hfTokenCiphertext = ../secrets/huggingface-token.age;
in
{
  options.mySecrets.enable = lib.mkEnableOption "agenix secret delivery on this host";

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      # Claude Code OAuth credential — coordinator ONLY, and the recipient tier in
      # ../secrets.nix now matches (aug04 ruling), so this MUST stay host-gated:
      # no other host can decrypt the ciphertext, and declaring an undecryptable
      # secret fails activation. The zenbook was already excluded (jul12 ruling:
      # the laptop is a standalone backup operator for when the coordinator is
      # unreachable, so it logs in with its OWN fresh OAuth session instead of
      # inheriting the coordinator's token — two devices refreshing one shared
      # token can race and sign each other out); the nas joined it aug04 for the
      # simpler reason that it has no `claude` and never spent the token.
      (lib.mkIf (config.networking.hostName == "coordinator") {
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
          cred="$HOME/.claude/.credentials.json"
          if [ ! -e "$cred" ] && [ -r "${config.age.secrets.claude-credentials.path}" ]; then
            mkdir -p "$HOME/.claude"
            cp "${config.age.secrets.claude-credentials.path}" "$cred"
            chmod 600 "$cred"
          fi
        '';
      })

      {
        # (hermes-credentials — the Nous Research AI harness's OAuth state — was
        # delivered here until 2026-08-04. The harness is no longer in use fleet-wide,
        # so the secret, its ciphertext, and its recipient rule are all gone. Any
        # already-seeded ~/.hermes/auth.json is stale local state, not managed here.)

        # Fleet SSH user key. mesh.nix already
        # authorizes this key + seeds known_hosts on every host; this delivers the
        # PRIVATE key so each box can also SSH *out* (any box → any box), and so
        # `nixos-rebuild --target-host` works from anywhere. Encrypted to every host
        # key (common tier), so a reflash restores it automatically — no more manual
        # ~/.ssh provisioning. The key is deliberately not an agenix editor
        # recipient. Copy-not-link: ssh wants a real 600 file tom owns.
        age.secrets.ssh-user-key = {
          file = ../secrets/ssh-user-key.age;
          owner = "tom";
          group = "users";
          mode = "600";
        };
        system.userActivationScripts.seedSshUserKey.text = ''
          key="$HOME/.ssh/id_ed25519"
          if [ -r "${config.age.secrets.ssh-user-key.path}" ]; then
            mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
            cp "${config.age.secrets.ssh-user-key.path}" "$key"
            chmod 600 "$key"
            ${pkgs.openssh}/bin/ssh-keygen -y -f "$key" > "$key.pub" 2>/dev/null || true
            chmod 644 "$key.pub" 2>/dev/null || true
          fi
        '';

        # atuin's shared fleet-wide history-encryption key (hosts/coordinator/services.nix
        # runs the sync server; home.nix's programs.atuin points every host at it).
        # Unlike the OAuth creds above, atuin's client NEVER rewrites this file once it
        # exists (`load_key` only writes if the path is absent) — there's no local
        # mutable state to protect, so force-copy on every activation rather than
        # seed-once. That also closes the gap a copy-if-absent seed would leave open: a
        # host that already had its own locally-generated key (from ordinary use before
        # this was wired up) always ends up on the one declared fleet key instead.
        age.secrets.atuin-key = {
          file = ../secrets/atuin-key.age;
          owner = "tom";
          group = "users";
          mode = "600";
        };
        system.userActivationScripts.seedAtuinKey.text = ''
          if [ -r "${config.age.secrets.atuin-key.path}" ]; then
            mkdir -p "$HOME/.local/share/atuin"
            cp "${config.age.secrets.atuin-key.path}" "$HOME/.local/share/atuin/key"
            chmod 600 "$HOME/.local/share/atuin/key"
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

        # No authKeyParameters: they append `?ephemeral=…&preauthorized=…` to the key,
        # which the control plane accepts only for OAuth client secrets used as auth
        # keys — a pre-minted tskey-auth key gets rejected as "invalid key" (bit a
        # first-boot host live, Jul 5). Our keys carry those properties from mint time.
        services.tailscale.authKeyFile = config.age.secrets.tailscale-authkey.path;

        # The stock autoconnect unit orders only after tailscaled; make it wait for
        # agenix's /run/agenix.d mount too, or it can race the key's decryption at boot.
        # It also raced the uplink on the coordinator's first boot (the boot-time
        # `tailscale up` predated wifi, so the join needed a manual restart, refs #37):
        # order after network-online.target and retry so a late uplink (wifi
        # associating after the unit fired) self-heals instead of staying down.
        # A minute keeps permanent auth/config failures from creating a tight
        # restart storm while still recovering promptly from a late network.
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
            RestartSec = "1min";
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

      # Hugging Face read token — coordinator-only operator credential. The
      # ciphertext is deliberately optional so adding the declarative CLI does
      # not require or manufacture a credential. Once provisioned with agenix,
      # the wrapper reads this /run path directly; no activation copy or
      # Hugging Face login cache is involved.
      (lib.mkIf (config.networking.hostName == "coordinator" && builtins.pathExists hfTokenCiphertext) {
        age.secrets.huggingface-token = {
          file = hfTokenCiphertext;
          owner = "tom";
          group = "users";
          mode = "400";
        };
      })

      # navidrome-credentials: NOT consumed by the navidrome server (which now
      # runs on the NAS, hosts/nas/media.nix, reached through the coordinator's
      # navidrome-relay) — read client-side by the cliamp fish function, on
      # whichever box cliamp runs from. Delivered to coordinator + zenbook-duo,
      # matching the recipient tier in secrets.nix. The wrapper exports the
      # file's NAVIDROME_PASSWORD under both that name (which config.toml's
      # ${NAVIDROME_PASSWORD} placeholder interpolates) and NAVIDROME_PASS
      # (which cliamp's config-less env fallback reads).
      (lib.mkIf
        (config.networking.hostName == "coordinator" || config.networking.hostName == "zenbook-duo")
        {
          age.secrets.navidrome-credentials = {
            file = ../secrets/navidrome-credentials.age;
            owner = "tom";
            group = "users";
            mode = "400";
          };
        }
      )

      # qwencloud-token: Qwen Token Plan API key, read client-side by pi through
      # the `!cat` apiKey in ~/.pi/agent/models.json (home/pi.nix). Same shape as
      # huggingface-token — delivered read-only under /run and never copied into a
      # mutable dotfile, because nothing ever rewrites it (unlike the OAuth creds
      # above, which refresh in place). Deliberately NOT exported as
      # QWEN_TOKEN_PLAN_API_KEY in pi's environment: that would hand the key to
      # every subprocess pi's bash tool spawns. models.json resolves it per
      # request instead, so it never enters the agent's process environment.
      (lib.mkIf (config.networking.hostName == "coordinator") {
        age.secrets.qwencloud-token = {
          file = ../secrets/qwencloud-token.age;
          owner = "tom";
          group = "users";
          mode = "400";
        };
      })

      # immich-api-key: full-permissions Immich key (photos.internal), read
      # client-side by agent sessions on the coordinator for indexing/dedup
      # passes. Delivered to /run/agenix/immich-api-key; replaces the loose
      # ~/immichkey file so the credential survives reflash without re-minting.
      (lib.mkIf (config.networking.hostName == "coordinator") {
        age.secrets.immich-api-key = {
          file = ../secrets/immich-api-key.age;
          owner = "tom";
          group = "users";
          mode = "400";
        };
      })

      # soundcloud-cookies: consumed by the music-consolidation drain's yt-dlp
      # invocations (systemd user units, coordinator-only). NOT for cliamp — see
      # secrets.nix for why cliamp needs no secret here.
      (lib.mkIf (config.networking.hostName == "coordinator") {
        age.secrets.soundcloud-cookies = {
          file = ../secrets/soundcloud-cookies.age;
          owner = "tom";
          group = "users";
          mode = "400";
        };
      })

      # youtube-music-cookies: parked for the music-consolidation YT-Music-fallback
      # work (dotfiles secret only — no consumer wired up yet).
      (lib.mkIf (config.networking.hostName == "coordinator") {
        age.secrets.youtube-music-cookies = {
          file = ../secrets/youtube-music-cookies.age;
          owner = "tom";
          group = "users";
          mode = "400";
        };
      })

      # Coordinator's Freebox wifi uplink (wlp192s0) PSK — delivered as a root-owned
      # NetworkManager environment file that uplink-nas.nix's ensureProfiles reads
      # via `$FREEBOX_PSK`. Guarded on the ciphertext EXISTING so eval/activation
      # never break if secrets/wifi.age is ever absent; it is committed (since
      # 2026-07-11, refs #37) so this delivery + the freebox-uplink profile are live.
      (lib.mkIf (config.networking.hostName == "coordinator" && builtins.pathExists ../secrets/wifi.age) {
        age.secrets.wifi.file = ../secrets/wifi.age;
      })

      # Coordinator's BE550-LAN wifi credentials ($BE550_SSID/$BE550_PSK) —
      # same shape and guard as the Freebox PSK above. Minted at cutover
      # phase 3 of the 2026-08-20 NAS-router rewire, once the BE550's live
      # SSID/PSK are read off its admin page; inert until then.
      (lib.mkIf (config.networking.hostName == "coordinator" && builtins.pathExists ../secrets/wifi-lan.age) {
        age.secrets.wifi-lan.file = ../secrets/wifi-lan.age;
      })
    ]
  );
}
