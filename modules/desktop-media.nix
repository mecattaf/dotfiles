{ pkgs, ... }:
# Local-network media + printing plane for the desktop (coordinator only).
#
# The two appliances this box should "just work" with:
#   - a JBL Authentics 200  — AirPlay 2 + Chromecast, wired to enp191s0 as
#     10.42.0.56 (see hosts/coordinator/uplink-nas.nix for the dedicated link)
#   - a Brother HL-L2445DW  — driverless IPP, 192.168.1.38 (wifi)
# Both are found over mDNS / DNS-SD: a multicast query to 224.0.0.251:5353.
#
# Why nothing worked before this module (diagnosed 2026-07-24):
#   1. No mDNS at all. avahi was not installed, and common.nix's firewall
#      (enable = true, no LAN holes) dropped inbound UDP 5353. A multicast probe
#      for _googlecast/_raop/_ipp got ZERO responders even though the JBL pings
#      fine and its cast/airplay ports are open — Chrome's Cast picker, PipeWire's
#      AirPlay discovery, and CUPS printer discovery all saw an empty network.
#   2. PipeWire had no RAOP (AirPlay) sender module, so a discovered JBL could
#      not be selected as an output sink.
#   3. No CUPS, so there was nothing to print to.
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
  # --- mDNS / DNS-SD discovery (the shared root cause) ---
  # avahi owns :5353 and browses both interfaces; openFirewall punches UDP 5353
  # so multicast replies reach us. Chrome does its own mDNS and only needs the
  # port open; OwnTone + CUPS talk to the avahi daemon over D-Bus.
  services.avahi = {
    enable = true;
    nssmdns4 = true; # resolve <device>.local (e.g. the printer's web UI)
    openFirewall = true; # UDP 5353
  };
  # systemd-resolved also wants :5353 for its own mDNS stub; hand mDNS to avahi so
  # the daemon binds cleanly. This only disables resolved's MULTICAST DNS — it
  # merges with the AdGuard module's [Resolve] block (DNS/Domains) and leaves the
  # unicast app → resolved → AdGuard → DoH path in modules/adguardhome.nix intact.
  services.resolved.settings.Resolve.MulticastDNS = false;

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
  # user-set level survives restarts.
  systemd.services.owntone-select-speaker = {
    description = "Select the JBL AirPlay 2 output in OwnTone";
    wantedBy = [ "multi-user.target" ];
    after = [ "owntone.service" ];
    requires = [ "owntone.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "owntone-select-speaker" ''
        for _ in $(seq 60); do
          id=$(${pkgs.curl}/bin/curl -sf localhost:3689/api/outputs \
               | ${pkgs.jq}/bin/jq -r '.outputs[]
                   | select(.type == "AirPlay 2" and .name == "Office speaker")
                   | .id')
          if [ -n "$id" ]; then
            ${pkgs.curl}/bin/curl -sf -X PUT "localhost:3689/api/outputs/$id" \
              -H 'Content-Type: application/json' -d '{"selected": true}'
            exit 0
          fi
          sleep 2
        done
        echo "JBL AirPlay 2 output never appeared in OwnTone" >&2
        exit 1
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

  # --- printing (Brother) ---
  # Modern Brother printers speak driverless IPP Everywhere, which CUPS
  # auto-configures once avahi is up — no per-model driver needed. brlaser covers
  # the older mono-laser models as a fallback.
  services.printing = {
    enable = true;
    drivers = [ pkgs.brlaser ];
  };

  # The printer came online after the 2026-07-24 module landed: a Brother
  # HL-L2445DW at 192.168.1.38, advertising _ipp._tcp with rp=ipp/print and
  # URF/PWG raster, i.e. fully driverless. Discovery is NOT the problem any more —
  # avahi sees it and cups-browsed is running.
  #
  # But Chrome's print dialog was still empty (2026-07-25), because discovery only
  # produced a CUPS *temporary* queue — the on-demand kind CUPS materialises per
  # job and tears down again. The split is visible in CUPS itself: `lpstat -e`
  # listed Brother_HL_L2445DW while `lpstat -t` answered "No destinations added".
  # Chrome enumerates permanent destinations, so it had nothing to show.
  #
  # (2026-07-25, later) With a permanent queue in place Chrome's dialog can STILL
  # come up empty when the printer is deep-asleep: Chrome re-checks destinations
  # at dialog-open and the sleeping Brother answers too slowly (~300ms+ RTT and
  # sometimes not at all). Waking the printer makes it appear. If this bites too
  # often, disable Deep Sleep in the Brother's web UI at
  # http://BRW08F97E55F396.local.
  #
  # ensurePrinters runs lpadmin to create a real, persistent queue, so the printer
  # is there at dialog-open instead of depending on discovery timing.
  # model = "everywhere" is driverless IPP: CUPS pulls capabilities off the
  # printer itself, so no PPD or vendor driver is pinned. Addressed by its mDNS
  # hostname rather than the current DHCP lease so a new address cannot silently
  # break the queue (nssmdns4 above is what resolves it).
  #
  # CAVEAT (2026-07-25, unresolved): ensure-printers has been observed to run,
  # report success, and create nothing — the current permanent queue on
  # coordinator was created by hand with the exact lpadmin invocation the unit
  # should have run. On a fresh machine, verify the queue actually exists
  # (`lpstat -t`) before trusting the unit.
  hardware.printers = {
    ensureDefaultPrinter = "Brother_HL_L2445DW";
    ensurePrinters = [
      {
        name = "Brother_HL_L2445DW";
        description = "Brother HL-L2445DW";
        location = "Home";
        deviceUri = "ipp://BRW08F97E55F396.local:631/ipp/print";
        model = "everywhere";
        ppdOptions.PageSize = "A4";
      }
    ];
  };

  # `lpadmin -m everywhere` has to TALK to the printer to fetch its capabilities,
  # so nixpkgs' ensure-printers oneshot fails whenever the printer is powered off —
  # which for a household printer is most of the time, including during the nightly
  # fleet deploy. Retry on a slow cadence instead of leaving a failed unit behind
  # (the 2026-07-15 auto-upgrade breakage was exactly this shape: one unrelated
  # non-zero exit poisoning the whole fleet update).
  systemd.services.ensure-printers = {
    startLimitIntervalSec = 0; # never latch into start-limit-hit
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = "5min";
    };
  };
}
