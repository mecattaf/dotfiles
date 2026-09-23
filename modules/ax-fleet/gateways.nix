{
  config,
  lib,
  inputs,
  ...
}:
# ax-fleet gateways: the egress default for every atespace the fleet declares.
#
# Stock ax v0.3.0 fails open: a Task with no `gateway:`, or naming a Gateway
# its atespace lacks, gets an allow-all EgressPolicy (reconciler.go "Default
# to allow all egress"; the client turns "*" into EgressRule{All}, and
# Substrate ignores the port). The fleet does not patch ax (Tom, 2026-09-23
# 08:45Z), so the default is closed from outside it, in three layers:
#
#   1. Declared: every atespace in myAxFleet.ax.atespaces names a default
#      Gateway with a non-empty allowlist and no allow-all host (assertion
#      below). The bootstrap step 80-ax-gateways applies every declared
#      Gateway on the NAS, idempotently.
#   2. Enforced: ax-fleet-gateway-default (control role) polls each declared
#      atespace and points any Task without a usable gateway at the default,
#      through ax's own UpdateTask; the controller then replaces the actor's
#      egress policy with the default's allowlist. The window between a
#      gateway-less Task's first reconcile and the repoint is bounded by the
#      poll interval plus one reconcile; checks.ax-fleet measures it
#      (33-gateway-default, record gateway_default_repoint).
#   3. The link: capacity 0 on a missing gateway (B10), so the floor never
#      dispatches a Task that would need layer 2.
#
# Below all three, the NAS forward chain (control.nix) keeps pods off every
# private range but Halogen, whatever policy ax writes.
let
  cfg = config.myAxFleet;
  system = "x86_64-linux";
  fleetPkgs = inputs.nixpkgs.legacyPackages.${system};
  ax = inputs.self.packages.${system}.ax;
  enforcer = fleetPkgs.callPackage ../../pkgs/ax-gateway-default { inherit ax; };
  on = cfg.enable && cfg.role == "control";

  halogenHost = builtins.head (lib.splitString ":" cfg.halogenEndpoint);
  halogenPort = lib.toInt (lib.last (lib.splitString ":" cfg.halogenEndpoint));
  halogenRule = {
    host = "${halogenHost}/32";
    port = halogenPort;
  };
  allowAll = [
    "*"
    "0.0.0.0/0"
    "::/0"
  ];

  hostRule = lib.types.submodule {
    options = {
      host = lib.mkOption {
        type = lib.types.str;
        description = "A hostname pattern or a CIDR, as ax's HostRule.host.";
      };
      port = lib.mkOption {
        type = lib.types.port;
        description = "Carried for the record; ax v0.3.0 drops it and the NAS chain enforces ports.";
      };
    };
  };

  atespaceType = lib.types.submodule {
    options = {
      defaultGateway = lib.mkOption {
        type = lib.types.str;
        default = "default";
        description = "The Gateway a Task without a usable gateway is pointed at.";
      };
      gateways = lib.mkOption {
        type = lib.types.attrsOf (lib.types.listOf hostRule);
        default = { };
        description = "Gateway name -> egress allowlist, applied by the bootstrap.";
      };
    };
  };

  gatewayDoc =
    ns: name: hosts:
    builtins.toJSON {
      apiVersion = "ax.io/v1alpha1";
      kind = "Gateway";
      metadata = {
        inherit name;
        atespace = ns;
      };
      spec.egress.allowlist.hosts = hosts;
    };

  axServer = "${cfg.axServerClusterIP}:8080";
  spacesArg = lib.concatStringsSep "," (
    lib.mapAttrsToList (ns: a: "${ns}=${a.defaultGateway}") cfg.ax.atespaces
  );
in
{
  options.myAxFleet.ax = {
    atespaces = lib.mkOption {
      type = lib.types.attrsOf atespaceType;
      default = {
        ${cfg.ax.atespace}.gateways = {
          default = [ halogenRule ];
          halogen = [ halogenRule ];
        };
        # ax's CLI default when -a is not given.
        default.gateways.default = [ halogenRule ];
      };
      defaultText = lib.literalExpression ''{ fleet.gateways = { default = [ halogen ]; halogen = [ halogen ]; }; default.gateways.default = [ halogen ]; }'';
      description = "Every atespace the fleet creates, each with its Gateways and the default one.";
    };
    gatewayDefaultInterval = lib.mkOption {
      type = lib.types.str;
      default = "2s";
      description = "ax-fleet-gateway-default's poll interval (a Go duration). A trade between the fail-open window and API load, not an estimate.";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      assertions = lib.flatten (
        lib.mapAttrsToList (ns: a: [
          {
            assertion = a.gateways ? ${a.defaultGateway};
            message = "myAxFleet.ax.atespaces.${ns}: the default Gateway \"${a.defaultGateway}\" is not declared in its gateways; stock ax would give a gateway-less Task allow-all egress.";
          }
          {
            assertion = (a.gateways.${a.defaultGateway} or [ ]) != [ ];
            message = "myAxFleet.ax.atespaces.${ns}: the default Gateway \"${a.defaultGateway}\" has an empty allowlist, which stock ax treats as allow-all.";
          }
          {
            assertion = lib.all (r: !(lib.elem r.host allowAll)) (a.gateways.${a.defaultGateway} or [ ]);
            message = "myAxFleet.ax.atespaces.${ns}: the default Gateway \"${a.defaultGateway}\" must not allow every host.";
          }
        ]) cfg.ax.atespaces
      )
      ++ [
        {
          assertion = cfg.ax.atespaces ? ${cfg.ax.atespace};
          message = "myAxFleet.ax.atespaces must declare myAxFleet.ax.atespace (\"${cfg.ax.atespace}\").";
        }
      ];
    })

    (lib.mkIf on {
      myAxFleet.bootstrap."80-ax-gateways" = ''
        # 80-ax-gateways: every declared Gateway, default ones included
        # (modules/ax-fleet/gateways.nix). Idempotent: ax apply updates.
        export AX_SERVER=http://${axServer}
        for _ in $(seq 1 300); do
          ${lib.getExe fleetPkgs.curl} -fsS -o /dev/null --max-time 5 "$AX_SERVER/healthz" && break
          sleep 2
        done
        ${lib.concatStrings (
          lib.flatten (
            lib.mapAttrsToList (
              ns: a:
              lib.mapAttrsToList (name: hosts: ''
                echo "gateway ${ns}/${name}"
                ${ax}/bin/ax -a ${ns} apply -f ${fleetPkgs.writeText "gateway-${ns}-${name}.json" (gatewayDoc ns name hosts)}
              '') a.gateways
            ) cfg.ax.atespaces
          )
        )}
        echo "ax gateways declared: ${spacesArg}"
      '';

      systemd.services.ax-fleet-gateway-default = {
        description = "ax-fleet: point Tasks without a usable gateway at their atespace's default Gateway";
        wantedBy = [ "multi-user.target" ];
        after = [
          "k3s.service"
          "ax-fleet-bootstrap.service"
        ];
        serviceConfig = {
          ExecStart = "${lib.getExe enforcer} -server ${axServer} -atespaces ${spacesArg} -interval ${cfg.ax.gatewayDefaultInterval}";
          Restart = "always";
          RestartSec = 5;
          # Root: the NAS output chain lets only root reach the Service range.
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          CapabilityBoundingSet = "";
        };
      };
    })
  ];
}
