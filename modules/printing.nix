{
  config,
  lib,
  pkgs,
  ...
}:

# Shared home-printer plane. common.nix imports it fleet-wide; headless.nix
# force-disables it on appliances such as `nas`.
lib.mkIf (!config.myHeadless.enable) {
  # CUPS supplies Chrome's system print dialog and the lp/lpr CLI. The Brother
  # HL-L2445DW speaks IPP Everywhere, so the permanent queue is driverless;
  # brlaser remains installed only as the already-proven fallback.
  services.printing = {
    enable = true;
    drivers = [ pkgs.brlaser ];
  };

  # AirPrint/IPP discovery and .local resolution. systemd-resolved also wants
  # port 5353, so let Avahi own multicast DNS while resolved continues to
  # handle ordinary unicast DNS.
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };
  services.resolved.settings.Resolve.MulticastDNS = false;

  # Discovery alone creates an on-demand temporary queue, which Chrome does
  # not reliably enumerate. Keep one persistent A4 queue with the name already
  # used on coordinator.
  #
  # The queue dials the printer's PINNED LAN ADDRESS, not its mDNS name
  # (2026-08-21): in Deep Sleep the Brother's mDNS responder goes fully mute
  # (avahi-resolve times out even while the IP answers pings), so a .local
  # deviceUri strands jobs exactly when the printer has been idle a while —
  # which is always, for a home printer. The address is safe to hardcode
  # because the NAS pins it by MAC (hosts/nas/router.nix dhcp-host:
  # 10.42.0.4,infinite); an IPP connect to the IP wakes the printer from
  # Deep Sleep reliably. On any network where 10.42.0.4 isn't this printer
  # (laptops roaming), the queue simply errors instead of printing somewhere
  # unexpected — acceptable.
  hardware.printers = {
    ensureDefaultPrinter = "Brother_HL_L2445DW";
    ensurePrinters = [
      {
        name = "Brother_HL_L2445DW";
        description = "Brother HL-L2445DW";
        location = "Home";
        deviceUri = "ipp://10.42.0.4:631/ipp/print";
        model = "everywhere";
        ppdOptions.PageSize = "A4";
      }
    ];
  };

  # `lpadmin -m everywhere` fetches capabilities from the live printer. A
  # sleeping/offline household printer must not permanently poison a fleet
  # update, so retry slowly. NixOS ensure-printers has also been observed to
  # exit successfully without creating its queue; coordinator's live queue
  # had to be created by hand after that exact silent no-op. The explicit
  # lpstat postcondition turns it into a visible failure and retry.
  systemd.services.ensure-printers = {
    startLimitIntervalSec = 0;
    postStart = ''
      ${pkgs.cups}/bin/lpstat -p Brother_HL_L2445DW >/dev/null
    '';
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = "5min";
      # Boot race, observed 2026-08-21 21:26:06 (seven seconds into the
      # boot): network-online.target says yes before the wifi has even
      # associated, lpadmin gets "Host is down", and the failure tripwire
      # screams on every reboot — even though the 5-min retry above then
      # quietly heals it. House doctrine: wait for the printer's reality,
      # not a target's word (the adguardhome wait-bind-addrs pattern). Up
      # to 90s for the IPP port, then proceed regardless — the `-` prefix
      # means a genuinely offline printer degrades to the retry loop, not
      # a louder failure.
      ExecStartPre = "-${pkgs.writeShellScript "wait-printer-reachable" ''
        for _ in $(${pkgs.coreutils}/bin/seq 90); do
          if ${pkgs.bash}/bin/bash -c 'exec 3<>/dev/tcp/10.42.0.4/631' 2>/dev/null; then
            exit 0
          fi
          ${pkgs.coreutils}/bin/sleep 1
        done
        echo "printer 10.42.0.4:631 unreachable after 90s; letting lpadmin try anyway" >&2
      ''}";
    };
  };

  # Print-document faces are explicit even though google-fonts already covers
  # part of this set in common.nix. These names are the stable profiles used by
  # the print skill: book (Garamond/Baskerville), editorial (Source Serif),
  # Times-compatible academic, LaTeX/Computer Modern, and Apple-like sans.
  fonts.packages = with pkgs; [
    eb-garamond
    libre-baskerville
    source-serif
    liberation_ttf
    lmodern
    inter
  ];

  # Claude Code's bounded raw-9100 path for trivial text. It defaults to the
  # printer's DHCP-reserved address and appends CRLF + form feed; rendered
  # documents continue through CUPS (`lp`) instead.
  environment.systemPackages = [
    pkgs.brother-print-text
    pkgs.poppler-utils # pdfinfo/pdftoppm: enforce page count and inspect before lp
  ];
}
