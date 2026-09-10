{ pkgs }:
let
  lib = pkgs.lib;
  make =
    extra:
    (import "${pkgs.path}/nixos/lib/eval-config.nix" {
      system = pkgs.stdenv.hostPlatform.system;
      modules = [
        ../../hosts/nas/tailscale-personal.nix
        {
          system.stateVersion = "26.05";
          boot.isContainer = true;
          networking.hostName = "nas";
          networking.nftables.enable = true;
          services.tailscale = {
            enable = true;
            useRoutingFeatures = "server";
            authKeyFile = "/run/headscale-nas-enroll/authkey";
            extraUpFlags = [
              "--login-server=http://10.42.0.1:8090"
              "--advertise-routes=10.42.0.0/24"
            ];
          };
          services.resolved.settings.Resolve.DNSStubListenerExtra = [ "100.64.0.1" ];
        }
        extra
      ];
    }).config;
  variants = {
    disabled = make { };
    enabled = make { myNas.tailscalePersonal.enable = true; };
    minimal = make {
      myNas.tailscalePersonal = {
        enable = true;
        advertiseExitNode = false;
        media.enable = false;
      };
    };
    public = make {
      myNas.tailscalePersonal = {
        enable = true;
        funnel = {
          enable = true;
          policyApproved = true;
        };
      };
    };
    unapproved = make {
      myNas.tailscalePersonal = {
        enable = true;
        funnel.enable = true;
      };
    };
    tls = make {
      myNas.tailscalePersonal = {
        enable = true;
        media.https.enable = true;
      };
      security.acme = {
        acceptTerms = true;
        defaults.email = "operator@example.invalid";
        certs."mecattaf.dev" = {
          dnsProvider = "cloudflare";
          environmentFile = "/run/secrets/test-only-not-provisioned";
          extraDomainNames = [
            "music.mecattaf.dev"
            "plex.mecattaf.dev"
          ];
        };
      };
    };
  };
  summarize = c: {
    enabled = c.myNas.tailscalePersonal.enable;
    failedAssertions = map (a: a.message) (builtins.filter (a: !a.assertion) c.assertions);
    hostTailscale = {
      inherit (c.services.tailscale)
        authKeyFile
        extraUpFlags
        extraSetFlags
        interfaceName
        ;
    };
    hostDns = c.services.resolved.settings.Resolve.DNSStubListenerExtra;
    trusted = c.networking.firewall.trustedInterfaces;
    input = c.networking.firewall.extraInputRules;
    tables = lib.mapAttrs (_: t: t.content) c.networking.nftables.tables;
    certificates = lib.mapAttrs (_: v: {
      inherit (v) listenAddresses useACMEHost extraConfig;
    }) c.services.caddy.virtualHosts;
    lifecycle =
      lib.mapAttrs
        (_: s: {
          inherit (s)
            after
            before
            requires
            bindsTo
            partOf
            wantedBy
            ;
        })
        (
          lib.filterAttrs (
            n: _: n == "container@nas-saas" || n == "caddy" || n == "nftables"
          ) c.systemd.services
        );
    container =
      if !c.myNas.tailscalePersonal.enable then
        null
      else
        let
          n = c.containers.nas-saas;
          k = n.config;
        in
        {
          inherit (n)
            privateNetwork
            enableTun
            ephemeral
            hostAddress
            localAddress
            bindMounts
            forwardPorts
            ;
          inherit (k.networking) nameservers useHostResolvConf;
          tailscale = {
            inherit (k.services.tailscale)
              authKeyFile
              extraUpFlags
              extraSetFlags
              interfaceName
              useRoutingFeatures
              ;
          };
          sockets = lib.mapAttrs (_: s: s.socketConfig.ListenStream) (
            lib.filterAttrs (n: _: lib.hasPrefix "personal-" n) k.systemd.sockets
          );
          proxies = lib.mapAttrs (_: s: s.serviceConfig.ExecStart or null) (
            lib.filterAttrs (n: _: lib.hasPrefix "personal-" n) k.systemd.services
          );
          tables = lib.mapAttrs (_: t: t.content) k.networking.nftables.tables;
          failedAssertions = map (a: a.message) (builtins.filter (a: !a.assertion) k.assertions);
        };
  };
  fixtureData = lib.mapAttrs (_: summarize) variants;
  fixtures = pkgs.writeText "personal-tailnet-fixtures.json" (builtins.toJSON fixtureData);
  rules = pkgs.writeText "personal-tailnet-test.nft" (
    lib.concatStringsSep "\n" (
      lib.mapAttrsToList (
        name: c:
        let
          tables =
            c.networking.nftables.tables
            // lib.optionalAttrs c.myNas.tailscalePersonal.enable (
              lib.mapAttrs' (
                n: v: lib.nameValuePair "container_${n}" v
              ) c.containers.nas-saas.config.networking.nftables.tables
            );
        in
        lib.concatStringsSep "\n" (
          lib.mapAttrsToList (tableName: table: ''
            table ${table.family} ${name}_${tableName} {
              ${table.content}
            }
          '') tables
        )
      ) variants
    )
  );
in
{
  inherit fixtureData fixtures;
  check =
    pkgs.runCommand "nas-personal-tailnet-check"
      {
        nativeBuildInputs = [
          pkgs.python3
          pkgs.nftables
        ];
      }
      ''
        python3 ${./test_policy.py} ${fixtures}
        # LKL gives nft its own sandbox kernel, not the builder/host firewall.
        LD_PRELOAD=${pkgs.lklWithFirewall.lib}/lib/liblkl-hijack.so \
          nft --check --file ${rules}
        touch "$out"
      '';
}
