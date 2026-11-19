{
  lib,
  pkgs,
  osConfig,
  ...
}:
# Shared physical-seat suite. The Zenbook receives speech playback
# helpers; compute and NAS do not acquire GUIs.
# App logins stay local to each machine; no credentials are copied here.
let
  displayHost = osConfig.myDisplay.enable;
in
{
  home.packages = lib.optionals displayHost [
    # PCM transport/player only; Qwen weights and inference stay on strix.
    pkgs.qwen-speech
    # Speech queue playback (speech-wake and Parakeet were
    # removed on 2026-09-30).
    pkgs.speech-session
    # No Claude Desktop or ChatGPT desktop apps (Tom, 2026-10-12: "installed
    # chatgp and claude apps must also be gone").
  ];
}
