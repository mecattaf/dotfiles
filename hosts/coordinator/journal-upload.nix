{ ... }:
# Fleet journald substrate, sender side (issue #135, workstream 1). Star
# topology with a single sender: zenbook/bridge are thin clients and do not
# upload. Plaintext over the point-to-point /30 (settled decision — nixpkgs
# systemd has no GnuTLS; same trust domain as NFSv4 on the same cable).
{
  services.journald.upload = {
    enable = true;
    settings.Upload.URL = "http://10.77.0.2:19532";
  };

  # The local journal stays persistent and bounded (#135, closing #133 item
  # 4 for journald): volatile storage would lose the final pre-lockup window
  # in an mt7925e-class hard freeze — the exact forensic case that motivates
  # the whole substrate. 4G ≈ 80 days at the measured ~50MB/day.
  services.journald.storage = "persistent";
  services.journald.extraConfig = ''
    SystemMaxUse=4G
  '';
}
