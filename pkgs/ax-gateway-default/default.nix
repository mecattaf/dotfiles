# ax-gateway-default: a separate client binary built from stock ax's module
# tree (same vendorHash, no ax patch). See main.go and
# modules/ax-fleet/gateways.nix.
{ ax }:
ax.overrideAttrs (old: {
  pname = "ax-gateway-default";
  postPatch = (old.postPatch or "") + ''
    mkdir -p cmd/ax-gateway-default
    cp ${./main.go} cmd/ax-gateway-default/main.go
    cp ${./main_test.go} cmd/ax-gateway-default/main_test.go
  '';
  subPackages = [ "cmd/ax-gateway-default" ];
  # Codex review 1: the gateway-safety rule has unit tests; run only this package's.
  doCheck = true;
  checkFlags = [ "-v" "-run=^Test(HostIsOpen|UnsafeReason)$" ];
  meta = (old.meta or { }) // {
    description = "Points ax Tasks without a usable gateway at their atespace's default Gateway";
    mainProgram = "ax-gateway-default";
  };
})
