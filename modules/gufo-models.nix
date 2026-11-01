{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
# One deployment row drives its Gufo command, proxy route, idle lifetime and
# required model-store loans. No model bytes enter Nix or move at activation.
let
  cfg = config.services.gufo;
  catalog = import ../lib/local-models.nix { inherit lib; };
  modelStore = import ../lib/model-store.nix { inherit catalog lib; };
  artifactType = lib.types.enum (builtins.attrNames modelStore.materialized);
  dirOf = id: modelStore.materialized.${id}.directory;
  primaryOf = id: modelStore.materialized.${id}.primary;
  bundleCheck = import ../lib/model-bundle-check.nix { inherit lib pkgs modelStore; };
  required =
    m:
    lib.unique (
      [ m.artifact ]
      ++ m.extraArtifacts
      ++ lib.filter (x: x != null) [
        m.dflashArtifact
        m.dsparkArtifact
      ]
      ++ lib.mapAttrsToList (_: voice: voice.artifact) m.voices
    );
  voiceType = lib.types.submodule {
    options = {
      artifact = lib.mkOption { type = artifactType; };
      wav = lib.mkOption { type = lib.types.str; };
      text = lib.mkOption { type = lib.types.str; };
    };
  };
  modelType = lib.types.submodule (
    { config, name, ... }:
    let
      m = config;
    in
    {
      options = {
        artifact = lib.mkOption {
          type = artifactType;
          description = "Catalog artifact: the same ID used by NAS library-fetch and explicit local-models-borrow.";
        };
        modality = lib.mkOption {
          type = lib.types.enum [
            "llm"
            "tts"
            "asr"
            "image"
            "video"
          ];
          default = "llm";
        };
        servedModelName = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = "Gufo's wire name; defaults to this deployment's API ID.";
        };
        idleSeconds = lib.mkOption {
          type = lib.types.ints.positive;
          default =
            if
              builtins.elem m.modality [
                "tts"
                "asr"
              ]
            then
              cfg.demand.audioIdleSeconds
            else
              cfg.demand.textIdleSeconds;
        };
        serve = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
          description = "Arguments to upstream Gufo mkGufoServe, such as context, sessions, think and extraArgs. Artifact paths, wire identity and loopback address/port are generated.";
        };
        mmproj = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Vision sidecar relative to this deployment's artifact directory.";
        };
        mtp = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "MTP sidecar relative to this deployment's artifact directory.";
        };
        dflashArtifact = lib.mkOption {
          type = lib.types.nullOr artifactType;
          default = null;
        };
        dsparkArtifact = lib.mkOption {
          type = lib.types.nullOr artifactType;
          default = null;
        };
        extraArtifacts = lib.mkOption {
          type = lib.types.listOf artifactType;
          default = [ ];
          description = "Additional catalog artifacts required before this deployment may start.";
        };
        voices = lib.mkOption {
          type = lib.types.attrsOf voiceType;
          default = { };
        };
      };
    }
  );
  commandFor =
    m:
    inputs.gufo.lib.${pkgs.stdenv.hostPlatform.system}.mkGufoServe (
      m.serve
      // {
        gufo = cfg.package;
        inherit (m) modality servedModelName;
        model = if m.modality == "llm" then primaryOf m.artifact else dirOf m.artifact;
        host = "127.0.0.1";
        port = "$GUFO_DEMAND_PORT";
        extraArgs =
          (m.serve.extraArgs or [ ])
          ++ lib.optionals (m.mmproj != null) [
            "--mmproj"
            "${dirOf m.artifact}/${m.mmproj}"
          ];
        voices = lib.mapAttrs (_: voice: {
          wav = "${dirOf voice.artifact}/${voice.wav}";
          text = "${dirOf voice.artifact}/${voice.text}";
        }) m.voices;
      }
      // lib.optionalAttrs (m.mtp != null) {
        speculative = "mtp";
        mtpModel = "${dirOf m.artifact}/${m.mtp}";
      }
      // lib.optionalAttrs (m.dflashArtifact != null) {
        speculative = "dflash2";
        dflashModel = primaryOf m.dflashArtifact;
      }
      // lib.optionalAttrs (m.dsparkArtifact != null) {
        speculative = "dspark";
        dsparkModel = primaryOf m.dsparkArtifact;
      }
    );
  launcher =
    id: m:
    pkgs.writeShellScript "gufo-demand-${id}" ''
      set -eu
      GUFO_DEMAND_PORT="$1"
      ${bundleCheck (required m)}
      exec ${commandFor m}
    '';
in
{
  options.services.gufo.models = lib.mkOption {
    type = lib.types.attrsOf modelType;
    default = { };
    description = "Declarative Gufo deployments, keyed by API model ID. Each row generates a llama-swap route and its complete wanted artifact set. The existing default/alternate/audio declarations seed the initial roster.";
  };
  config = lib.mkIf cfg.enable {
    services.local-models.requirements.gufo = (
      lib.unique (lib.concatMap required (builtins.attrValues cfg.models))
    );
    services.llama-swap.settings.models = lib.mapAttrs (
      id: m:
      {
        cmd = "${launcher id m} \${PORT}";
        checkEndpoint = "/ready";
        ttl = m.idleSeconds;
        useModelName = m.servedModelName;
        timeouts.responseHeader = 1200;
      }
      // lib.optionalAttrs (m.modality == "llm") {
        capabilities = {
          "in" = [ "text" ] ++ lib.optional (m.mmproj != null) "image";
          out = [ "text" ];
          tools = true;
        }
        // lib.optionalAttrs (m.serve ? context) { context = m.serve.context; };
      }
    ) cfg.models;
    assertions = lib.mapAttrsToList (id: m: {
      assertion =
        builtins.length (
          lib.filter (x: x) [
            (m.mtp != null)
            (m.dflashArtifact != null)
            (m.dsparkArtifact != null)
          ]
        ) <= 1;
      message = "Gufo deployment ${id} may choose only one speculative backend.";
    }) cfg.models;
  };
}
