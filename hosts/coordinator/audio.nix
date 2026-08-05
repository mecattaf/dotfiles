{ pkgs, ... }:
# coordinator audio intake — the iContact Camera Pro webcam mic is the mic Tom
# actually speaks into (Claude Code /voice, meetings), so it is pinned as the
# default PipeWire source rather than left to WirePlumber's priority election.
#
# Diagnosed 2026-08-04 after /voice reported "No audio detected from
# microphone". Two independent faults, both invisible from the PipeWire side:
#
#  1. The webcam's *hardware* capture gain (ALSA `Mic Capture Volume` on card
#     `Pro`, range 0-4096) sat at 0, so the USB endpoint streamed digital
#     silence. Every capture path agreed: `pw-record` and a direct
#     `ffmpeg -f alsa -i hw:3` both produced samples that were exactly zero.
#     Meanwhile `wpctl` cheerfully reported the source at 53% and unmuted —
#     PipeWire's number is a cubic mapping onto that same control, and nothing
#     in the graph surfaces "the mixer element is at the bottom of its range".
#     Repaired at runtime with `amixer -c Pro sset Mic 36% cap` (~+5.8 dB),
#     which WirePlumber then persisted to its own state. This is *runtime*
#     state, not declarative: if ~/.local/state/wireplumber is ever wiped the
#     control can come back at the firmware default, so that amixer line is the
#     first thing to re-run if the mic goes silent again.
#
#  2. The stored default source was the node name `asrtest`, left over from an
#     earlier speech-recognition experiment and no longer present in the graph.
#     WirePlumber fell back to whatever won on priority, which is why the
#     default input drifted between the webcam, the INZONE Buds and the unused
#     analog jack across reboots.
#
# The rule below fixes (2) properly: giving the webcam node a session priority
# well above every other capture device makes it win the election outright, so
# a stale or cleared default-nodes state can no longer move the intake.
{
  services.pipewire.wireplumber.extraConfig."51-coordinator-default-source" = {
    "monitor.alsa.rules" = [
      {
        # Matched on node.name, which carries the USB serial — precise for this
        # unit. Replacing the webcam means updating this string; the symptom
        # would be the default input silently reverting to the Buds.
        matches = [
          {
            "node.name" =
              "alsa_input.usb-DCX-241206-FAY_iContact_Camera_Pro_01.00.00-02.analog-stereo";
          }
        ];
        actions.update-props = {
          # Stock ALSA sources land around 1000-2000; 3000 is unambiguous.
          "priority.session" = 3000;
        };
      }
    ];
  };

  # Absent until now, which is why the zeroed hardware mixer above took a
  # `nix shell nixpkgs#alsa-utils` to even see. The PipeWire-level tools
  # (wpctl/pw-record) cannot read or write raw ALSA mixer elements, so keep
  # amixer/alsamixer/arecord on the box for the next time capture looks dead.
  environment.systemPackages = [ pkgs.alsa-utils ];
}
