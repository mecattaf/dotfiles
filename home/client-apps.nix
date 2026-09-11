{
  lib,
  pkgs,
  osConfig,
  ...
}:
# The client's own GUI applications — the short list of things that run ON the
# seat rather than through it.
#
# The thin client's whole point (R-16) is that almost nothing local updates:
# the compositor, kitty, the clipboard bridge, Chrome and the Duo's hardware
# layer, and everything else is the coordinator's, reached over ssh. Chrome is
# the one real local app in that set. These are the deliberate exceptions Tom
# asked for on top of it, and they are host-gated so the exception cannot leak
# onto the other boxes.
#
# ── why this file and not home/home.nix ────────────────────────────────────
# home/home.nix:310-322 already gives every host a set of typed Chrome PWA
# launchers, `claude` among them (:312, https://claude.ai/ in an --app window).
# That is the WEB Claude and it stays. What lands here is the NATIVE desktop
# application, which is a different artefact with a different failure mode (an
# Electron/FHS bundle, its own login, its own MCP surface), so it gets its own
# file with its own reasons rather than being folded into the PWA table.
#
# ── why NOT keepFromLlmAgents ──────────────────────────────────────────────
# `pkgs.llm-agents` is the same catalog these come from, and home/home.nix:36-48
# already curates it — but that allowlist is FLEET-WIDE: every name in it is
# installed on the coordinator, the worker and the NAS as well. Adding an
# Electron GUI there would put a desktop application (and its closure, which
# the NAS's cache has to warm) on hosts that have no display at all — the
# coordinator goes headless immediately after this seat is proven. So the
# gate is by hostName here, not by a new entry there. One catalog, two
# admission rules: fleet-wide CLIs in home.nix, seat-only GUIs here.
#
# ── no credential is delivered ─────────────────────────────────────────────
# Nothing in this file touches agenix. modules/secrets.nix:27-31 records the
# standing ruling for exactly this case: the laptop signs in with its OWN
# session rather than inheriting the coordinator's token, because two devices
# refreshing one token race and sign each other out. Tom logs these apps in by
# hand, once, on the metal.
#
# ── Wayland ────────────────────────────────────────────────────────────────
# Shipped unwrapped, VERIFIED against the built store path
# (claude-desktop-1.49585.0): the innermost wrapper ends in
#   exec …/claude-desktop ${NIXOS_OZONE_WL:+${WAYLAND_DISPLAY:+--ozone-platform-hint=auto …}}
# so it already keys native Wayland off the variable modules/common.nix:407
# exports fleet-wide, and the bubblewrap FHS layer around it inherits the
# session environment. No symlinkJoin/makeWrapper is needed; if a future
# catalog bump drops that conditional the fix is a wrapper here, not a
# fleet-wide flag.
let
  hostName = osConfig.networking.hostName;
in
{
  home.packages = lib.optionals (hostName == "client") [
    # Claude Desktop — Tom's nice-to-have on the seat. Unofficial repack of the
    # vendor's Electron app from the llm-agents catalog (flake input, overlay
    # `pkgs.llm-agents`), FHS-wrapped with bubblewrap. Its portal/sandbox
    # behaviour under niri has never been exercised — the fleet has not had a
    # seat with it until now — so it is a nice-to-have in the literal sense:
    # if it misbehaves on the metal, the PWA at home.nix:312 is the fallback
    # and this line comes out.
    pkgs.llm-agents.claude-desktop

    # ChatGPT's desktop application, from the same catalog and on the same
    # terms (`meta.available` is true for x86_64-linux on the pinned rev;
    # it carries Codex too). Same fallback: the `chatgpt` PWA at home.nix:311.
    pkgs.llm-agents.chatgpt
  ];
}
