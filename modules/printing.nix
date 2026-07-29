{
  pkgs,
  ...
}:

# Shared home-printer plane. common.nix imports this for the active NixOS fleet
# and future hosts.
{
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
  # used on coordinator. The mDNS hostname survives DHCP lease changes.
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
