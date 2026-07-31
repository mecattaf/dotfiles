{ pkgs, ... }:
# Local-network media plane for the desktop (coordinator only). The shared
# Brother printing + mDNS plane lives in printing.nix.
#
# The appliance this box should "just work" with:
#   - a JBL Authentics 200  — AirPlay 2 + Chromecast, wired to enp191s0 as
#     10.42.0.56 (see hosts/coordinator/uplink-nas.nix for the dedicated link)
# It is found over mDNS / DNS-SD: a multicast query to 224.0.0.251:5353.
#
# Why nothing worked before this module (diagnosed 2026-07-24):
#   1. No mDNS at all. Avahi was not installed, and common.nix's firewall
#      (enable = true, no LAN holes) dropped inbound UDP 5353. A multicast probe
#      for _googlecast/_raop/_ipp got ZERO responders even though the JBL pings
#      fine and its cast/airplay ports are open.
#   2. PipeWire had no RAOP (AirPlay) sender module, so a discovered JBL could
#      not be selected as an output sink.
#
# --- Why the JBL is driven through OwnTone and not PipeWire's RAOP ---
# (diagnosed 2026-07-25) PipeWire's libpipewire-module-raop-sink speaks the
# 2011-era AirPlay 1 protocol: plaintext RTSP with ANNOUNCE/SDP. This JBL
# firmware (srcvers 366.0) is AirPlay-2-only and rejects every mode the module
# can produce — plain ANNOUNCE gets "403 Forbidden", auth_setup's POST gets
# "400 Bad Request", RSA gets 403 again. Worse, the module unloads itself after
# the RTSP failure, so the discovered sink silently vanishes the moment
# anything plays to it — that was the "sink flaps in and out of existence"
# symptom. AirPlay 2 needs a HomeKit-style transient SRP pairing, an encrypted
# control channel, binary-plist SETUP and PTP timing; verified working against
# this speaker with pyatv, which is how OwnTone talks to it too.
#
# The audio path is therefore:
#   apps -> "Office speaker" null sink -> pw-record (user service) ->
#   FIFO in /var/lib/owntone/music -> owntone (system service, autostarts the
#   pipe on data) -> AirPlay 2 -> JBL
# Latency is a few seconds (AirPlay 2 buffered mode + pipe buffering): fine for
# music, useless for lip-sync video. The bridge streams continuously, which
# also means the JBL is held by an active AirPlay session while this box is up;
# `systemctl --user stop office-speaker-bridge` releases it for e.g. a phone.
# OwnTone's web UI (volume, output selection) is at http://localhost:3689.
let
  musicDir = "/var/lib/owntone/music";
  pipePath = "${musicDir}/office-speaker-pipe";
  # OwnTone expects raw PCM 44100/16/2 on library pipes — keep the bridge's
  # pw-record format in sync with this.
  owntoneConf = pkgs.writeText "owntone.conf" ''
    general {
      uid = "owntone"
      db_path = "/var/lib/owntone/songs3.db"
      cache_dir = "/var/lib/owntone/cache"
      logfile = "/var/lib/owntone/owntone.log"
      loglevel = "info"
    }
    library {
      name = "Office speaker bridge"
      directories = { "${musicDir}" }
    }
  '';
in
{
  # --- "Office speaker" sink (front half of the bridge) ---
  # A null sink so the speaker shows up in the normal audio menu and WirePlumber
  # can remember it as default. Everything played here is captured off its
  # monitor by the office-speaker-bridge user service below.
  # monitor.channel-volumes makes the desktop volume slider actually attenuate
  # what the monitor (and so the speaker) receives.
  services.pipewire.extraConfig.pipewire."10-office-speaker" = {
    "context.objects" = [
      {
        factory = "adapter";
        args = {
          "factory.name" = "support.null-audio-sink";
          "node.name" = "office_speaker";
          "node.description" = "Office speaker";
          "media.class" = "Audio/Sink";
          "audio.position" = [ "FL" "FR" ];
          "audio.rate" = 44100;
          "monitor.channel-volumes" = true;
        };
      }
    ];
  };
  # NOTE: libpipewire-module-raop-discover is deliberately NOT loaded any more.
  # It only ever produced the self-destructing AirPlay 1 sink described above
  # (plus a Freebox sink nobody plays to) and its flapping was a trap: streams
  # routed there died silently. Re-add it here if an actual AirPlay 1 receiver
  # ever joins the network.

  # --- OwnTone (back half of the bridge) ---
  users.users.owntone = {
    isSystemUser = true;
    group = "owntone";
  };
  users.groups.owntone = { };

  # The FIFO is reader owntone / writer tom's user session. tmpfiles was
  # observed ignoring a non-owntone owner here (it created the pipe
  # owntone:owntone regardless), so instead of fighting ownership the pipe is
  # other-writable: 0662 lets any local writer feed it, which on this
  # single-user desktop is exactly tom. The `z` line repairs an existing pipe's
  # mode in place, not just on first creation.
  systemd.tmpfiles.rules = [
    "d ${musicDir} 0755 owntone owntone -"
    "p ${pipePath} 0662 owntone owntone -"
    "z ${pipePath} 0662 owntone owntone -"
  ];

  systemd.services.owntone = {
    description = "OwnTone media server (AirPlay 2 bridge to the JBL)";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "avahi-daemon.service"
    ];
    requires = [ "avahi-daemon.service" ];
    serviceConfig = {
      User = "owntone";
      Group = "owntone";
      StateDirectory = "owntone";
      ExecStart = "${pkgs.owntone}/bin/owntone -f -c ${owntoneConf}";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  # A fresh OwnTone database starts with no outputs selected, so a rebuild or
  # state wipe would silently unroute the speaker. Idempotently select the JBL
  # (by name + protocol, not id — ids are per-database) once it shows up.
  # Selection then persists in OwnTone's own state; volume is left alone so a
  # user-set level survives restarts. The speaker may be powered off during a
  # boot or switch, so this must remain an asynchronous waiter rather than gate
  # system activation on external hardware discovery.
  systemd.services.owntone-select-speaker = {
    description = "Select the JBL AirPlay 2 output in OwnTone";
    wantedBy = [ "multi-user.target" ];
    after = [ "owntone.service" ];
    requires = [ "owntone.service" ];
    serviceConfig = {
      Type = "simple";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = 2;
      ExecStart = pkgs.writeShellScript "owntone-select-speaker" ''
        while true; do
          id=$(${pkgs.curl}/bin/curl -sf localhost:3689/api/outputs \
               | ${pkgs.jq}/bin/jq -r '.outputs[]
                   | select(.type == "AirPlay 2" and .name == "Office speaker")
                   | .id')
          if [ -n "$id" ]; then
            if ${pkgs.curl}/bin/curl -sf -X PUT "localhost:3689/api/outputs/$id" \
              -H 'Content-Type: application/json' -d '{"selected": true}'; then
              exit 0
            fi
          fi
          sleep 2
        done
      '';
    };
  };

  # Front half -> back half: capture the null sink's monitor as raw PCM into
  # OwnTone's pipe. open() on the FIFO blocks until owntone has it open for
  # reading, so ordering against the system service is handled by the kernel.
  # node.dont-move matters because WirePlumber otherwise moves a client stream
  # that initially targets the default sink whenever that default changes. This
  # capture must remain on office_speaker while normal app streams follow the
  # output selected by the user.
  systemd.user.services.office-speaker-bridge = {
    description = "Feed the Office speaker sink into OwnTone's pipe";
    after = [ "pipewire.service" ];
    wants = [ "pipewire.service" ];
    wantedBy = [ "default.target" ];
    serviceConfig = {
      ExecStart = pkgs.writeShellScript "office-speaker-bridge" ''
        exec ${pkgs.pipewire}/bin/pw-record --target office_speaker \
          -P '{ stream.capture.sink = true node.dont-move = true }' \
          --format s16 --rate 44100 --channels 2 - > ${pipePath}
      '';
      Restart = "always";
      RestartSec = 2;
    };
  };
}
