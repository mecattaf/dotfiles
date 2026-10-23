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
      # (claude-credentials — the Claude Code OAuth token seeded into
      # ~/.claude/.credentials.json — was declared and copied here until
      # 2026-09-22. The token had been dead since its August 4 rotation, and a
      # seed that fires whenever the file is absent can only ever revert a fresh
      # `/login` after a rebuild. Both Claude seats now log in by hand, once,
      # on the strix: cc into ~/.claude, cc2 into ~/.claude-work.)

      # Only agent hosts and physical seats receive the shared SSH/history keys.
      # Compute logins use mesh authorized public keys, never this private key.
      (lib.mkIf (config.myFleet.has "brain" || config.myFleet.has "seat") {
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

        # atuin's shared fleet-wide history-encryption key (hosts/strix/services.nix
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

      })

      # Operator CLI credentials — brain only (the ciphertexts aren't decryptable
      # by other hosts, and declaring an undecryptable secret fails activation, so the
      # whole block must be host-gated). Same copy-don't-link pattern as the claude
      # cred: both CLIs rewrite their file on token refresh.
      (lib.mkIf (config.myFleet.has "brain") {
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
        # The single full-scope Cloudflare API token (secrets.nix has the provenance).
        # Same copy-not-link delivery as wrangler-config; the runbooks of the crm,
        # email and backlog services read the copied file by that exact path.
        age.secrets.cloudflare-api-token = {
          file = ../secrets/cloudflare-api-token.age;
          owner = "tom";
          group = "users";
          mode = "600";
        };
        # Every login shell exports CLOUDFLARE_API_TOKEN from the delivered file, so
        # wrangler and the curl-based runbooks authenticate without a browser session.
        environment.extraInit = ''
          if [ -r "$HOME/.local/state/cloudflare/api-token" ]; then
            export CLOUDFLARE_API_TOKEN="$(cat "$HOME/.local/state/cloudflare/api-token")"
          fi
        '';

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
          cf="$HOME/.local/state/cloudflare/api-token"
          if [ ! -e "$cf" ] && [ -r "${config.age.secrets.cloudflare-api-token.path}" ]; then
            mkdir -p "$HOME/.local/state/cloudflare"
            chmod 700 "$HOME/.local/state/cloudflare"
            cp "${config.age.secrets.cloudflare-api-token.path}" "$cf"
            chmod 600 "$cf"
          fi
        '';
      })

      # Hugging Face read token — strix AND nas since 2026-08-28. The
      # ciphertext stays optional (pathExists) so the tree still evaluates on a
      # checkout that carries no credential; it went absent-but-declared for the
      # whole life of the declarative CLI, which is precisely why `hf` had been
      # running unauthenticated without ever saying so.
      #
      # The nas is the REAL consumer, not a convenience copy: hosts/nas/models.nix
      # runs library-fetch — "the ONLY thing that ever talks to Hugging Face" —
      # and it curls catalog weights anonymously, so a gated repo 401s the
      # nightly. The strix keeps it for interactive `hf` (Tom, same day:
      # "hf-on-strix is just there as a fallback, honestly").
      #
      # Owner stays `tom` on both: on the nas library-fetch runs as root, which
      # reads a 0400 tom-owned file regardless, and keeping the owner uniform
      # means the interactive `hf` wrapper works on either box unchanged.
      (lib.mkIf
        (
          (config.myFleet.has "brain" || config.myFleet.has "router") && builtins.pathExists hfTokenCiphertext
        )
        {
          age.secrets.huggingface-token = {
            file = hfTokenCiphertext;
            owner = "tom";
            group = "users";
            mode = "400";
          };
        }
      )

      # navidrome-credentials: NOT consumed by the navidrome server (which now
      # runs on the NAS, hosts/nas/media.nix, reached through the strix's
      # navidrome-relay) — read client-side by the navidrome-scan fish function
      # (NAVIDROME_USER / NAVIDROME_PASSWORD). Coordinator-only, matching the
      # recipient tier in secrets.nix. (Its first reader, the cliamp TUI client,
      # was removed 2026-09-17.)
      (lib.mkIf (config.myFleet.has "brain") {
        age.secrets.navidrome-credentials = {
          file = ../secrets/navidrome-credentials.age;
          owner = "tom";
          group = "users";
          mode = "400";
        };
      })

      # qwencloud-token: Qwen Token Plan API key. Two consumers, same shape as
      # huggingface-token — delivered read-only under /run and never copied into a
      # mutable dotfile, because nothing ever rewrites it (unlike the OAuth creds
      # above, which refresh in place).
      # - pi reads it client-side through the `!cat` apiKey in
      #   ~/.pi/agent/models.json (home/pi.nix). Deliberately NOT exported as
      #   QWEN_TOKEN_PLAN_API_KEY in pi's environment: pi's bash tool would hand
      #   it to every subprocess. models.json resolves it per request instead.
      # - dsh (pkgs/dsh, home/dsh.nix) DOES get it as QWEN_TOKEN_PLAN_API_KEY,
      #   set by its wrapper at exec time for the dsh process only. dsh drops
      #   every *KEY*/*TOKEN* name (and every DSH_* name) from the children it
      #   spawns, which removes the reason above, and its headless profile has
      #   no credential store, so the environment is the only delivery that
      #   reaches it. Its bwrap runner also masks /run/agenix from the model's
      #   commands. Not masked: dsh's in-process `read` tool and any same-uid
      #   /proc/<pid>/environ read, the same exposure pi has today.
      # dsh reuses this secret; NAS recipient changes are listed in REKEY.md.
      (lib.mkIf (config.myFleet.has "brain") {
        age.secrets.qwencloud-token = {
          file = ../secrets/qwencloud-token.age;
          owner = "tom";
          group = "users";
          mode = "400";
        };
      })

      # openrouter-token: OpenRouter API key, same shape and same reasoning as
      # qwencloud-token above. pi resolves it per request through the `!cat`
      # apiKey on its built-in `openrouter` provider (home/pi.nix); it is never
      # exported as OPENROUTER_API_KEY.
      (lib.mkIf (config.myFleet.has "brain") {
        age.secrets.openrouter-token = {
          file = ../secrets/openrouter-token.age;
          owner = "tom";
          group = "users";
          mode = "400";
        };
      })

      # codex-auth: the Codex CLI ChatGPT-subscription session (Pro plan,
      # re-logged 2026-10-04). Same shape as claude-credentials above, for the
      # same reason: Codex REWRITES auth.json on every token refresh, so agenix's
      # read-only /run symlink cannot be the live file. Seed once into ~/.codex
      # (Codex's default CODEX_HOME) only if absent; after that the live file is
      # Codex's, and a re-login means re-minting the ciphertext (secrets.nix).
      (lib.mkIf (config.myFleet.has "brain") {
        age.secrets.codex-auth = {
          file = ../secrets/codex-auth.age;
          owner = "tom";
          group = "users";
          mode = "600";
        };

        system.userActivationScripts.seedCodexAuth.text = ''
          auth="$HOME/.codex/auth.json"
          if [ ! -e "$auth" ] && [ -r "${config.age.secrets.codex-auth.path}" ]; then
            mkdir -p "$HOME/.codex"
            cp "${config.age.secrets.codex-auth.path}" "$auth"
            chmod 600 "$auth"
          fi
        '';
      })

      # immich-api-key: full-permissions Immich key (photos.internal), read
      # client-side by agent sessions on the strix for indexing/dedup
      # passes. Delivered to /run/agenix/immich-api-key; replaces the loose
      # ~/immichkey file so the credential survives reflash without re-minting.
      (lib.mkIf (config.myFleet.has "brain") {
        age.secrets.immich-api-key = {
          file = ../secrets/immich-api-key.age;
          owner = "tom";
          group = "users";
          mode = "400";
        };
      })

      # soundcloud-cookies: consumed by the music-consolidation drain's yt-dlp
      # invocations (systemd user units, strix-only).
      (lib.mkIf (config.myFleet.has "brain") {
        age.secrets.soundcloud-cookies = {
          file = ../secrets/soundcloud-cookies.age;
          owner = "tom";
          group = "users";
          mode = "400";
        };
      })

      # youtube-music-cookies: parked for the music-consolidation YT-Music-fallback
      # work (dotfiles secret only — no consumer wired up yet).
      (lib.mkIf (config.myFleet.has "brain") {
        age.secrets.youtube-music-cookies = {
          file = ../secrets/youtube-music-cookies.age;
          owner = "tom";
          group = "users";
          mode = "400";
        };
      })

      # BE550-LAN wifi credentials ($BE550_SSID/$BE550_PSK) — same shape and
      # guard as the Freebox PSK above. Minted at cutover phase 3 of the
      # 2026-08-20 NAS-router rewire. Delivered to the hosts whose
      # thomas-6ghz profile reads it; the worker was one from 2026-08-21
      # (#229) until it went wired-only on 2026-09-11 and left this list with
      # the client's admission, the rekey that also dropped it from the
      # ciphertext's recipients (secrets.nix).
      (lib.mkIf (config.myFleet.has "seat" && builtins.pathExists ../secrets/wifi-lan.age) {
        age.secrets.wifi-lan.file = ../secrets/wifi-lan.age;
      })
    ]
  );
}
