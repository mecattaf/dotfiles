{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
# ax on the fleet, track ax (DESIGN.md sections 9, 10 and 14 A3). This module
# writes only the myAxFleet extension points (manifests, registrySeed) and, on
# the harness, the coordinator's ax scripts and AX_SERVER. Everything else
# (k3s, the registry, the bootstrap runner, ax-server-proxy.socket) belongs to
# the cluster modules next to this file.
#
# ONE image set for every host. The images are built from the flake's own
# nixpkgs pin and the flake's `ax` package, never from the host's `pkgs`: the
# NAS evaluates from nixpkgs-stable, and the digest the NAS seeds must be the
# digest the coordinator's `ax-fleet-image-ref` prints.
#
# Day one: pi against Halogen only. No Claude credential, no claude-code in the
# task image, no secret in any Task or manifest (DESIGN.md section 11).
let
  cfg = config.myAxFleet;
  system = "x86_64-linux";

  fleetPkgs = inputs.nixpkgs.legacyPackages.${system};
  ax = inputs.self.packages.${system}.ax;
  pi = inputs.llm-agents.packages.${system}.pi;

  images = fleetPkgs.callPackage ../../pkgs/ax/images.nix { inherit ax; };
  agentImage = fleetPkgs.callPackage ../../pkgs/ax-agent-image { inherit ax pi; };

  seeds = {
    ax-server = {
      oci = images.ax-server;
      repo = "ax/ax-server";
      tag = images.tag;
    };
    ax-controller = {
      oci = images.ax-controller;
      repo = "ax/ax-controller";
      tag = images.tag;
    };
    ax-redis = {
      oci = images.ax-redis;
      repo = "ax/ax-redis";
      tag = images.ax-redis.passthru.tag;
    };
    ax-agent = {
      oci = agentImage;
      repo = "ax/ax-agent";
      tag = agentImage.passthru.tag;
    };
  };

  # Pod image references through the containerd mirror for cfg.registry.
  # @digest:<seed>@ is replaced at build time from "<oci>/digest".
  podImage = name: "${cfg.registry}/${seeds.${name}.repo}@@digest:${name}@";

  controlSelector = {
    "ax.mecattaf.dev/role" = "control";
  };

  labels = name: {
    "app.kubernetes.io/name" = name;
    "app.kubernetes.io/part-of" = "ax";
    "app.kubernetes.io/managed-by" = "ax-fleet";
  };

  # The ax-system objects, as data. Rendered to YAML below, then the digests
  # are substituted in a build step (no import-from-derivation).
  objects = [
    {
      apiVersion = "v1";
      kind = "Namespace";
      metadata = {
        name = "ax-system";
        labels = labels "ax-system";
      };
    }

    # ── ax-redis: AOF on a local-path volume (the data pool on the NAS) ──
    {
      apiVersion = "v1";
      kind = "PersistentVolumeClaim";
      metadata = {
        name = "ax-redis-data";
        namespace = "ax-system";
        labels = labels "ax-redis";
      };
      spec = {
        accessModes = [ "ReadWriteOnce" ];
        storageClassName = "local-path";
        resources.requests.storage = "5Gi";
      };
    }
    {
      apiVersion = "apps/v1";
      kind = "Deployment";
      metadata = {
        name = "ax-redis";
        namespace = "ax-system";
        labels = labels "ax-redis";
      };
      spec = {
        replicas = 1;
        # One RWO volume: never two pods at once.
        strategy.type = "Recreate";
        selector.matchLabels."app.kubernetes.io/name" = "ax-redis";
        template = {
          metadata.labels = labels "ax-redis";
          spec = {
            nodeSelector = controlSelector;
            containers = [
              {
                name = "redis";
                image = podImage "ax-redis";
                imagePullPolicy = "IfNotPresent";
                # No password: reachable only as a ClusterIP, and a sandbox
                # reaches only its Gateway allowlist. If one is ever added, both
                # daemons read REDIS_PASSWORD from the environment; never argv.
                args = [
                  "--appendonly"
                  "yes"
                  "--dir"
                  "/data"
                  "--protected-mode"
                  "no"
                ];
                ports = [
                  {
                    containerPort = 6379;
                    name = "redis";
                  }
                ];
                readinessProbe = {
                  tcpSocket.port = 6379;
                  periodSeconds = 5;
                };
                resources = {
                  requests = {
                    cpu = "100m";
                    memory = "128Mi";
                  };
                  limits.memory = "1Gi";
                };
                volumeMounts = [
                  {
                    name = "data";
                    mountPath = "/data";
                  }
                ];
              }
            ];
            volumes = [
              {
                name = "data";
                persistentVolumeClaim.claimName = "ax-redis-data";
              }
            ];
          };
        };
      };
    }
    {
      apiVersion = "v1";
      kind = "Service";
      metadata = {
        name = "ax-redis";
        namespace = "ax-system";
        labels = labels "ax-redis";
      };
      spec = {
        type = "ClusterIP";
        selector."app.kubernetes.io/name" = "ax-redis";
        ports = [
          {
            name = "redis";
            port = 6379;
            targetPort = 6379;
          }
        ];
      };
    }

    # ── ax-server: ClusterIP pinned, never a NodePort (the API has no auth) ──
    {
      apiVersion = "apps/v1";
      kind = "Deployment";
      metadata = {
        name = "ax-server";
        namespace = "ax-system";
        labels = labels "ax-server";
      };
      spec = {
        replicas = 1;
        selector.matchLabels."app.kubernetes.io/name" = "ax-server";
        template = {
          metadata.labels = labels "ax-server";
          spec = {
            nodeSelector = controlSelector;
            containers = [
              {
                name = "ax-server";
                image = podImage "ax-server";
                imagePullPolicy = "IfNotPresent";
                args = [
                  "--addr=:8080"
                  "--redis-addr=ax-redis.ax-system.svc.cluster.local:6379"
                ];
                ports = [
                  {
                    containerPort = 8080;
                    name = "http";
                  }
                ];
                readinessProbe = {
                  httpGet = {
                    path = "/healthz";
                    port = 8080;
                  };
                  initialDelaySeconds = 2;
                  periodSeconds = 5;
                };
                livenessProbe = {
                  httpGet = {
                    path = "/healthz";
                    port = 8080;
                  };
                  initialDelaySeconds = 5;
                  periodSeconds = 10;
                };
                resources = {
                  requests = {
                    cpu = "100m";
                    memory = "128Mi";
                  };
                  limits.memory = "1Gi";
                };
                securityContext = {
                  readOnlyRootFilesystem = true;
                  allowPrivilegeEscalation = false;
                  runAsNonRoot = true;
                };
              }
            ];
          };
        };
      };
    }
    {
      apiVersion = "v1";
      kind = "Service";
      metadata = {
        name = "ax-server";
        namespace = "ax-system";
        labels = labels "ax-server";
      };
      spec = {
        type = "ClusterIP";
        clusterIP = cfg.axServerClusterIP;
        selector."app.kubernetes.io/name" = "ax-server";
        ports = [
          {
            name = "http";
            port = 8080;
            targetPort = 8080;
          }
        ];
      };
    }

    # ── ax-controller: upstream deploy/ax-controller.yaml, plus P1's resync ──
    {
      apiVersion = "v1";
      kind = "ServiceAccount";
      metadata = {
        name = "ax-controller";
        namespace = "ax-system";
        labels = labels "ax-controller";
      };
    }
    {
      apiVersion = "rbac.authorization.k8s.io/v1";
      kind = "ClusterRole";
      metadata = {
        name = "ax-controller";
        labels = labels "ax-controller";
      };
      rules = [
        {
          apiGroups = [ "" ];
          resources = [ "secrets" ];
          verbs = [
            "get"
            "list"
            "watch"
          ];
        }
      ];
    }
    {
      apiVersion = "rbac.authorization.k8s.io/v1";
      kind = "ClusterRoleBinding";
      metadata = {
        name = "ax-controller";
        labels = labels "ax-controller";
      };
      subjects = [
        {
          kind = "ServiceAccount";
          name = "ax-controller";
          namespace = "ax-system";
        }
      ];
      roleRef = {
        apiGroup = "rbac.authorization.k8s.io";
        kind = "ClusterRole";
        name = "ax-controller";
      };
    }
    {
      apiVersion = "apps/v1";
      kind = "Deployment";
      metadata = {
        name = "ax-controller";
        namespace = "ax-system";
        labels = labels "ax-controller";
      };
      spec = {
        # One consumer: P1's resync assumes one controller per Redis group.
        replicas = 1;
        strategy.type = "Recreate";
        selector.matchLabels."app.kubernetes.io/name" = "ax-controller";
        template = {
          metadata.labels = labels "ax-controller";
          spec = {
            nodeSelector = controlSelector;
            serviceAccountName = "ax-controller";
            containers = [
              {
                name = "controller";
                image = podImage "ax-controller";
                imagePullPolicy = "IfNotPresent";
                args = [
                  "--redis-addr=ax-redis.ax-system.svc.cluster.local:6379"
                  "--substrate-endpoint=api.ate-system.svc.cluster.local:443"
                  "--substrate-authority=api.ate-system.svc"
                  "--substrate-token-file=/var/run/secrets/ateapi/token"
                  "--substrate-ca-file=/run/servicedns-ca/trust-bundle.pem"
                  "--template=default-template"
                  "--template-atespace=ax-system"
                  "--running-resync=${toString cfg.ax.runningResyncSeconds}s"
                ];
                env = [
                  {
                    name = "ATENET_ROUTER_ADDR";
                    value = "atenet-router.ate-system.svc.cluster.local:80";
                  }
                  {
                    # MEASURED working on RustFS by the 2026-09-23 probe.
                    name = "AX_SNAPSHOTS_BUCKET";
                    value = "gs://ate-snapshots/ax/";
                  }
                ];
                resources = {
                  requests = {
                    cpu = "100m";
                    memory = "128Mi";
                  };
                  limits.memory = "512Mi";
                };
                securityContext = {
                  readOnlyRootFilesystem = true;
                  allowPrivilegeEscalation = false;
                  runAsNonRoot = true;
                };
                volumeMounts = [
                  {
                    mountPath = "/var/run/secrets/ateapi";
                    name = "ate-token";
                    readOnly = true;
                  }
                  {
                    mountPath = "/run/servicedns-ca";
                    name = "servicedns-ca";
                    readOnly = true;
                  }
                ];
              }
            ];
            volumes = [
              {
                name = "ate-token";
                projected = {
                  defaultMode = 292; # 0444: the controller runs as uid 65532
                  sources = [
                    {
                      serviceAccountToken = {
                        audience = "api.ate-system.svc";
                        expirationSeconds = 7200;
                        path = "token";
                      };
                    }
                  ];
                };
              }
              {
                name = "servicedns-ca";
                projected = {
                  defaultMode = 420;
                  sources = [
                    {
                      clusterTrustBundle = {
                        signerName = "servicedns.podcert.ate.dev/identity";
                        labelSelector.matchLabels."podcert.ate.dev/canarying" = "live";
                        path = "trust-bundle.pem";
                      };
                    }
                  ];
                };
              }
            ];
          };
        };
      };
    }
  ];

  manifestTemplate = fleetPkgs.writeText "ax-fleet-40-ax.yaml.in" (
    lib.concatMapStringsSep "\n---\n" builtins.toJSON objects + "\n"
  );

  # JSON documents are valid YAML; k3s's deploy controller reads multi-doc
  # YAML. Digests are substituted from each image's `digest` file here, at
  # build time, then every document is checked for a leftover placeholder.
  manifest =
    fleetPkgs.runCommand "ax-fleet-40-ax.yaml"
      {
        nativeBuildInputs = [ fleetPkgs.yq-go ];
      }
      ''
        cp ${manifestTemplate} $out
        chmod u+w $out
        ${lib.concatMapStrings (n: ''
          substituteInPlace $out --replace-quiet '@digest:${n}@' "$(cat ${seeds.${n}.oci}/digest)"
        '') (builtins.attrNames seeds)}
        if grep -q '@digest:' $out; then echo "unsubstituted digest in $out" >&2; exit 1; fi
        # Every document parses, and every image is pinned by digest.
        yq -e 'select(.kind == "Deployment") | .spec.template.spec.containers[].image | test("@sha256:[0-9a-f]{64}$")' $out >/dev/null
        test "$(yq -N 'select(.kind != null) | .kind' $out | wc -l)" -eq ${toString (builtins.length objects)}
      '';

  agentRef = fleetPkgs.writeShellScriptBin "ax-fleet-image-ref" ''
    # The ax-agent Task image by digest. atelet rewrites localhost:5000.
    printf 'localhost:5000/ax/ax-agent@%s\n' "$(cat ${agentImage}/digest)"
  '';

  smoke = fleetPkgs.writeShellApplication {
    name = "ax-fleet-smoke";
    runtimeInputs = [
      ax
      agentRef
      fleetPkgs.coreutils
      fleetPkgs.jq
      fleetPkgs.yq-go
    ];
    text = builtins.readFile ./ax-fleet-smoke.sh;
    runtimeEnv = {
      AX_FLEET_ATESPACE = cfg.ax.atespace;
      AX_FLEET_HALOGEN = cfg.halogenEndpoint;
      AX_FLEET_HALOGEN_CIDR = "${builtins.head (lib.splitString ":" cfg.halogenEndpoint)}/32";
      AX_FLEET_RESYNC_SECONDS = toString cfg.ax.runningResyncSeconds;
    };
  };
in
{
  options.myAxFleet.ax = {
    runningResyncSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 15;
      description = "P1's --running-resync: how often ax-controller re-checks Running Tasks for a command exit. A trade between detection lag and controller load, not an estimate.";
    };
    atespace = lib.mkOption {
      type = lib.types.str;
      default = "fleet";
      description = "The ax atespace ax-fleet-smoke runs Tasks and the halogen Gateway in.";
    };
    images = lib.mkOption {
      type = lib.types.attrsOf lib.types.package;
      readOnly = true;
      internal = true;
      default = {
        inherit (images) ax-server ax-controller ax-redis;
        ax-agent = agentImage;
        manifest = manifest;
      };
      description = "The ax images and the rendered manifest, for tests and the flake's packages.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        # Consumed on the NAS (control role) by the cluster modules; declared
        # on every role so the digests any host names are the digests seeded.
        myAxFleet.manifests.ax-fleet-40-ax.source = manifest;
        myAxFleet.registrySeed = lib.mapAttrs (_: s: s) seeds;
      }

      (lib.mkIf (cfg.role == "harness") {
        environment.systemPackages = [
          agentRef
          smoke
        ];
        # ax-server-proxy.socket (harness.nix) listens here and forwards to
        # the ax-server ClusterIP. The ax CLI and ax-conwip both honour it.
        environment.sessionVariables.AX_SERVER = "http://127.0.0.1:8080";
      })
    ]
  );
}
