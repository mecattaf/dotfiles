# Projection for nix eval --apply: include every generateUnits input, without
# realizing the candidate directory. A baseline is useful only if userTree is
# the actual live directory; gates.py enforces that before comparing inputs.
c: {
  userTree = toString c.environment.etc."systemd/user".source;
  systemd = toString c.systemd.package;
  packages = map toString c.systemd.packages;
  inherit (c.systemd) additionalUpstreamUserUnits;
  units = builtins.mapAttrs (_: u: {
    inherit (u)
      enable
      text
      aliases
      wantedBy
      requiredBy
      upheldBy
      overrideStrategy
      ;
    unit = toString u.unit;
  }) c.systemd.user.units;
}
