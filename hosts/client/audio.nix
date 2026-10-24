{ pkgs, ... }:
# client audio intake — the iContact Camera Pro webcam mic is the mic Tom
# actually speaks into (meetings, the call-record scripts), so it is pinned as
# the default PipeWire source rather than left to WirePlumber's priority
# election. Moved here from hosts/strix/audio.nix on 2026-09-11 with the
# webcam itself: the strix's USB peripherals live on the Thunderbolt
# dock the thin client sits on now (R-7), and the strix keeps only its
# Ryzen HD Audio and Radeon HDMI — no real mic. Call recording therefore
# captures this exact USB node (dictation and Parakeet were removed on
# 2026-09-30). The voice path never follows a changed
# default-source selection.
#
# The node name carries the unit's USB serial, so the rule is the same on any
# host the camera is plugged into. The runtime repair below is PER HOST
# (WirePlumber state is local): re-run `amixer -c Pro sset Mic 36% cap` once
# on this box when the mic first goes silent.
#
# Diagnosed 2026-08-04 after /voice reported "No audio detected from
# microphone": two independent capture faults, both invisible from the PipeWire
# side. A third, on the OUTPUT side, joined them on 2026-10-14; its repair lives
# in bin/audio-route, not in this file:
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
#  3. (2026-10-14, "INZONE earphones not playing sound".) The Sony INZONE Buds
#     sink was the running default, Chrome's stream was linked (S16LE 2ch
#     48 kHz, 0 xruns) and `wpctl get-volume` said 0.24: inaudible at listening
#     level, not digital silence. wpctl and the F7/F8 OSD print the CUBIC
#     (perceptual) number on every device, so a displayed 24 % is a linear gain
#     of 0.24^3 = 0.0138, about -37 dB, and the OSD's "24%" looks fine.
#     `volume down` (F7 on the Glove80, the Duo's XF86AudioLowerVolume key)
#     had walked it there in 3 % steps. WirePlumber persists that gain per route
#     under `alsa_card.usb-Sony_INZONE_Buds-00:output:analog-output` in
#     ~/.local/state/wireplumber/default-routes and re-applies it whenever the
#     route becomes active again (replug, boot, profile change; a bare
#     `wpctl set-default` selects no route, the stored value is simply already
#     live then), so the level survives unplugs. All that is specific to the
#     Buds is that the dongle has no ALSA volume element (`amixer -c <Buds>`
#     shows only `PCM Playback Switch` booleans; node Props carry
#     channelVolumes == softVolumes), so the whole attenuation is software gain
#     applied before S16_LE output and there is no hardware control to lift.
#     Repaired live with `wpctl set-volume <buds sink id> 0.5`, which is what
#     F8 does; bin/audio-route now lifts a picked sink below 0.30 to 0.50 and
#     says so, which catches the route-switch recurrence only: walking the live
#     default down with `volume down` again still shows nothing but the OSD
#     number. For the next reader, `wpctl get-volume` exits 0 on "not found" and
#     "does not support volume" (wpctl 0.5.15), so the parsed stdout, not the
#     rc, is the check (bin/volume's level() still trusts the rc and parses $2
#     blind; it has not been touched here).
#
#  4. (2026-10-24, muffled above 100%, quiet below it.) F9 selected the
#     analog-stereo sink: the receiver's USB descriptor names it Chat (PCM 0).
#     iec958-stereo is actually Game/music (PCM 1), with ordinary stereo PCM.
#     Both advertise S16_LE, 2ch, 48 kHz. Moved music to Game, retaining the
#     mono mic. The independent hardware volume, read through the receiver's
#     HID status using ZoneOut's verified Buds layout, was only 4/30; balance
#     was centered at 50 and sidetone 0. Set hardware volume to 20/30 with
#     desktop gain at 35%, then verified the hardware read-back. Software
#     boost had been compensating for that hardware attenuation and clipping.
#     F9 now chooses Game; F8 caps only INZONE software gain at unity.
#     WirePlumber saved output:iec958-stereo+input:mono-fallback; the device
#     rule also picks that profile when there is no saved state.
#
# The rule below fixes (2) properly: giving the webcam node a session priority
# well above every other capture device makes it win the election outright, so
# a stale or cleared default-nodes state can no longer move the intake.
{
  services.pipewire.wireplumber.extraConfig."51-client-default-source" = {
    "monitor.alsa.rules" = [
      {
        # PC-mode INZONE receiver: Game playback plus the existing mic.
        matches = [
          {
            "device.name" = "alsa_card.usb-Sony_INZONE_Buds-00";
            "device.product.id" = "0x0ec2";
          }
        ];
        actions.update-props = {
          "device.profile" = "output:iec958-stereo+input:mono-fallback";
        };
      }
      {
        # Matched on node.name, which carries the USB serial — precise for this
        # unit. Replacing the webcam means updating this string; the symptom
        # would be the default input silently reverting to the Buds.
        matches = [
          {
            "node.name" = "alsa_input.usb-DCX-241206-FAY_iContact_Camera_Pro_01.00.00-02.analog-stereo";
          }
        ];
        actions.update-props = {
          # Stock ALSA sources land around 1000-2000; 3000 is unambiguous.
          "priority.session" = 3000;
        };
      }
      # The Sound Blaster GS3 on the same dock is the sink Tom listens on;
      # pinned the same way so the default output never drifts to the INZONE
      # dongle or the laptop's own codec across replugs (doc §7.2). Same
      # USB-serial node name bin/audio-route dials.
      {
        matches = [
          {
            "node.name" =
              "alsa_output.usb-Creative_Technology_Ltd_Sound_Blaster_GS3_1120050704030604-01.analog-stereo";
          }
        ];
        actions.update-props = {
          "priority.session" = 3000;
        };
      }
    ];
  };

  # The access tag must precede 73-seat-late.rules, which applies the ACL.
  # NixOS extraRules is 99-local.rules, so use an explicitly ordered file.
  services.udev.packages = [
    (pkgs.writeTextDir "lib/udev/rules.d/70-inzone-buds.rules" ''
      SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="054c", ATTR{idProduct}=="0ec2", TAG+="uaccess"
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0ec2", TAG+="uaccess"
    '')
  ];

  # Absent until now, which is why the zeroed hardware mixer above took a
  # `nix shell nixpkgs#alsa-utils` to even see. The PipeWire-level tools
  # (wpctl/pw-record) cannot read or write raw ALSA mixer elements, so keep
  # amixer/alsamixer/arecord on the box for the next time capture looks dead.
  environment.systemPackages = [
    pkgs.alsa-utils
    (pkgs.callPackage ../../pkgs/zoneout.nix { })
  ];
}
