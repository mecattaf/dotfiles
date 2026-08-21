{ ... }:
# ─── Network-neighborhood discovery: make the NAS show up in Nautilus ───────
#
# Tom's ask (2026-08-21, cutover day): "I want the NAS to actually show its
# files in Network (like a NAS is actually supposed to)." GNOME's Network pane
# is gvfs, and gvfs lists exactly one thing: services it discovered via
# mDNS/DNS-SD (Avahi) — SMB, SFTP, WebDAV. It does not and will never browse
# NFS, which is all this box exported until today, and the box announced
# nothing. That is the whole reason the old attempts failed on the /30 cable
# era ("some racing condition" — no: structurally impossible, twice over,
# since mDNS is link-local and the /30 had no Avahi on either end anyway).
#
# Two halves, both LAN-side:
#   1. Avahi announces the host + an _smb._tcp service record → the "nas"
#      entry appears under Available on Current Network.
#   2. smbd serves the four media trees read-only so clicking that entry
#      shows the actual files.
#
# ── Deliberate scope decisions ──────────────────────────────────────────────
# READ-ONLY, guest, no Samba passwords: the write path stays NFS (the
# coordinator's mounts), so smbd holds no credential state and cannot be a
# second mutation path to the data. This also honors the appliance doctrine —
# no new secrets on this box ("NO SECRET LIVES ON THIS BOX" — the 2026-08-04
# ruling recorded in secrets.nix; an smbpasswd database is exactly the kind of standing state that
# ruling exists to keep off the appliance).
#
# SMB admission is LAN-WIDE (10.42.0.0/24) — Tom's ruling, 2026-08-21: "only
# me and my family use this wifi (feature not a bug)". The wifi PSK is the
# access control; anyone on `thomas` may browse all four trees read-only.
# (First deploy pinned this to the coordinator alone; widened the same day.)
#
# services/ is NOT shared: live service state has no business in a file
# browser. models/ IS shared (Tom, 2026-08-21: "would be nice to check them
# out, nothing to lose") — weights/ is the interesting half; cache/ is nar
# noise but harmless.
{
  services.avahi = {
    enable = true;
    # Announce only on the LAN leg. Never wan0 — the Freebox segment must see
    # a router, not a fileserver.
    allowInterfaces = [ "enp1s0" ];
    publish = {
      enable = true;
      addresses = true;
      # Publishes the static service records below (the SMB announcement).
      userServices = true;
    };
    openFirewall = false; # scoped by hand in extraInputRules below
    extraServiceFiles.smb = ''
      <?xml version="1.0" standalone='no'?>
      <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
      <service-group>
        <name replace-wildcards="yes">%h</name>
        <service>
          <type>_smb._tcp</type>
          <port>445</port>
        </service>
        <!-- device-info makes gvfs render a server icon instead of a blank -->
        <service>
          <type>_device-info._tcp</type>
          <port>0</port>
          <txt-record>model=RackMac</txt-record>
        </service>
      </service-group>
    '';
  };

  services.samba = {
    enable = true;
    openFirewall = false; # scoped by hand in extraInputRules below
    settings = {
      global = {
        "server string" = "nas";
        # Discovery is Avahi's job; kill the legacy NetBIOS plane entirely.
        "disable netbios" = "yes";
        "server min protocol" = "SMB3";
        # Anonymous browsing maps to nobody; there are no Samba accounts to
        # fall through to, and must never be (see header).
        "map to guest" = "Bad User";
        "guest account" = "nobody";
        "load printers" = "no";
        "printcap name" = "/dev/null";
      };
      music = {
        path = "/mnt/nas/music";
        "read only" = "yes";
        "guest ok" = "yes";
      };
      videos = {
        path = "/mnt/nas/videos";
        "read only" = "yes";
        "guest ok" = "yes";
      };
      photos = {
        path = "/mnt/nas/photos";
        "read only" = "yes";
        "guest ok" = "yes";
      };
      documents = {
        path = "/mnt/nas/documents";
        "read only" = "yes";
        "guest ok" = "yes";
      };
      models = {
        path = "/mnt/nas/models";
        "read only" = "yes";
        "guest ok" = "yes";
      };
    };
  };

  # mDNS + SMB to the whole LAN (see the scope ruling in the header). Same
  # nftables shape as every other scoped listener on this box (storage.nix,
  # media.nix, attic.nix …) — scoped to the LAN leg, never wan0.
  networking.firewall.extraInputRules = ''
    iifname "enp1s0" udp dport 5353 accept
    ip saddr 10.42.0.0/24 tcp dport 445 accept
  '';
}
