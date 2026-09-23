# ax-gateway-default: a separate client binary built from stock ax's module
# tree (same vendorHash, no ax patch). See main.go and
# modules/ax-fleet/gateways.nix.
{ ax }:
ax.overrideAttrs (old: {
  pname = "ax-gateway-default";
  postPatch = (old.postPatch or "") + ''
    mkdir -p cmd/ax-gateway-default
    cp ${./main.go} cmd/ax-gateway-default/main.go
  '';
  subPackages = [ "cmd/ax-gateway-default" ];
  doCheck = false;
  meta = (old.meta or { }) // {
    description = "Points ax Tasks without a usable gateway at their atespace's default Gateway";
    mainProgram = "ax-gateway-default";
  };
})
