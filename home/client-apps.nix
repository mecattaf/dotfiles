{
  lib,
  pkgs,
  osConfig,
  ...
}:
# Shared physical-seat suite. Coordinator and Zenbook receive the same GUI
# apps and speech capture/playback helpers; worker/NAS do not acquire GUIs.
# App logins stay local to each machine; no credentials are copied here.
let
  displayHost = osConfig.myDisplay.enable;
in
{
  home.packages = lib.optionals displayHost [
    # PCM transport/player only; Qwen weights and inference stay on coordinator.
    pkgs.qwen-speech
    # Explicit one-shot feedback only; no wake detector or microphone process.
    pkgs.speech-listening-cue
    # Explicit CPU wake session; installing this CLI creates no boot listener.
    pkgs.speech-session
    pkgs.speech-wake
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
