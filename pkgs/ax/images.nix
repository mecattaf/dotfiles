{
  callPackage,
  dockerTools,
  cacert,
  redis,
  # The patched ax (pkgs/ax: sandbox-class + P1). Passed in so every host seeds
  # and references the same derivation.
  ax,
}:
# The ax control-plane images for the fleet (DESIGN.md section 8): ax-server,
# ax-controller and ax-redis, each an OCI layout with a `digest` file, seeded
# into the NAS registry as ax/<name>:<tag> and referenced by digest in the
# ax-fleet-40-ax manifest (modules/ax-fleet/ax.nix).
#
# Upstream publishes no image (ko:// references only, deploy/*.yaml), so these
# are built here from the same pkgs/ax the CLI uses.
let
  ociLayout = callPackage ./oci-layout.nix { };
  tag = "v${ax.version}-p1";

  axImage =
    cmd:
    ociLayout {
      name = "ax/${cmd}";
      inherit tag;
      image = dockerTools.buildLayeredImage {
        name = "ax/${cmd}";
        inherit tag;
        contents = [ cacert ];
        config = {
          Entrypoint = [ "${ax}/bin/${cmd}" ];
          Env = [ "SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt" ];
          User = "65532:65532";
        };
      };
    };
in
{
  inherit tag ociLayout;

  ax-server = axImage "ax-server";
  ax-controller = axImage "ax-controller";

  # nixpkgs redis, not upstream's redis:7-alpine. Upstream's image patches
  # protected mode off; a stock redis-server refuses non-loopback clients when
  # it has no password, so the manifest passes --protected-mode no. It is
  # reachable only as a ClusterIP (DESIGN.md section 9).
  ax-redis = ociLayout {
    name = "ax/ax-redis";
    tag = "${redis.version}";
    image = dockerTools.buildLayeredImage {
      name = "ax/ax-redis";
      tag = "${redis.version}";
      contents = [ ];
      extraCommands = ''
        mkdir -p data
      '';
      config = {
        Entrypoint = [ "${redis}/bin/redis-server" ];
        WorkingDir = "/data";
      };
    };
  };
}
