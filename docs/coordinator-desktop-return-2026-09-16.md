# Coordinator desktop return — 2026-09-16

Tom requested restoring the coordinator as his primary physical desktop with
both ASUS PA27JCV 5K monitors upright and side by side, retaining the Zenbook
as a fully capable secondary seat. This supersedes the September 11 headless
coordinator decision. The laptop has already been unplugged from its TB3 dock.

## Prepared configuration

- Coordinator Niri/greetd/Piri enabled. Same current shared shortcuts, launcher,
  call recorder, Chrome/PWAs, Claude Desktop and ChatGPT packages as the client.
- Shared Kanshi Desktop profile: DP-4 left at 0,0; DP-1 right at 2560,0;
  both 5120x2880 at 60 Hz, scale 2, normal rotation. Single-output fallbacks.
  Zenbook Duo and DuoDocked profiles unchanged. Actual connector identities,
  left/right order and simultaneous 5K need confirmation after recabling.
- Dock iContact and Sound Blaster GS3 WirePlumber rules imported on coordinator.
  The real dock must be attached to exercise webcam, microphone and speakers.
- Existing Herdr projector transport retained on both seats, including self-SSH
  on coordinator: this preserves the tested native clipboard-image bridge and
  per-window focus behavior. Hold-Space capture now accepts coordinator too.
- Alexa wake package/service and its NAS-managed model artifacts on coordinator.
  Capture remains explicitly pinned to the iContact microphone on both seats;
  no automatic switch to an arbitrary internal microphone.
- Speech sessions carry an originating seat; their prompts specify a
  `client--` or `coordinator--` filename prefix for queued spoken replies.
  Unprefixed speech jobs now play on coordinator. Playback and dictation keep
  call/wake inhibition. Inference and the accepted Qwen voice are unchanged.
- Physical Niri owns user portals. Headless Sway remains available on demand,
  but cannot own/stop the physical portals. Chrome's cross-display profile
  guard remains: close Chrome normally on one display before opening that
  data directory on the other; simultaneous use needs separate user-data dirs.
- No physical-session VNC, no changes to worker/NAS services or LAN topology.
- Herdr keep-old and its compositor-independent lifetime are unchanged.

## Validation and boot

Niri configuration validation and launcher, wake, queue, playback and Qwen
unit tests run through runtime-test. Nix checks cover both seat profiles,
portal ownership, launcher behavior, Qwen topology and deadnix. Full coordinator
system built; next-boot deployment uses `nixos-rebuild boot`, not `switch`.
Wake models borrowed explicitly from NAS using the new wanted manifest; no
model pruning. The borrow also fills the already-declared missing Gemma MTP
artifact; it does not start that model.

## After moving

1. Connect displays and dock/peripherals, then boot the normal default entry.
2. Confirm both outputs with `niri msg outputs`; if cables changed connector
   names, update the Desktop profile. Left/right can be swapped in Kanshi.
3. Mod+Return opens a fresh Herdr window; Mod+Ctrl+Shift+Return opens its sidebar;
   Mod+Shift+Return opens a plain terminal. Test image paste and hold-Space.
4. Verify iContact capture, GS3 playback, Alexa, and Shift+F9 call inhibition.
   If iContact produces silence, inspect its ALSA capture gain as documented
   in hosts/client/audio.nix; do not infer audibility from PipeWire levels.
5. Keep the Zenbook on Wi-Fi for SSH recovery. Its off-LAN Headscale enrollment
   was still NeedsLogin at the pre-move inspection; no enrollment changed here.

The physical desktop has not been launched over the live agent sessions.
Boot/menu selection, final system path and post-boot evidence should be checked
against the actual deployment receipt, not inferred from this document.

## Deployment receipt

`nixos-rebuild boot --flake .#coordinator` completed successfully. systemd-boot
now selects generation **234** by default:
`/nix/store/7r7ipnd910garzn30cwlzkmywnx5l3lz-nixos-system-coordinator-26.11.20260723.e2587ca`.
Generation 233 remains available as the previous configuration. The running
system stayed on generation 233; Herdr PID 3798871 and Tally PID 3811939 were
unchanged. No shutdown, compositor launch, service restart or client deployment
was performed. Actual output/audio behavior awaits the physical move.
