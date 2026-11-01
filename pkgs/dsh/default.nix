{
  lib,
  writeShellApplication,
  formats,
  bubblewrap,
  coreutils,
  findutils,
  writeText,
  llm-agents,
  dsh-plugins,
  # Retired subscription: no fleet key is delivered. An explicit external
  # override may still supply a credential for another installation.
  qwenKeyFile ? null,
  # The stock profiles the wrapper will boot. Everything else, but the
  # Nix-declared profiles below, is refused, so a custom profile cannot carry
  # the web or sdk-minimal bundles past the name check.
  profiles ? [
    "headless"
    "sdk"
    "acp"
  ],
}:
# dsh: DeepSeek Harness from llm-agents.nix (Tom's ruling, 2026-10-22: "use
# llm-agents.nix"), served signed by numtide's cache, so nothing in the 712 MB
# tree builds here. This wrapper is the only `dsh` on PATH: `dsh` stays out of
# home/agent-tools.nix's keepFromLlmAgents (two bin/dsh would collide). A
# direct llm-agents.dsh reference also skips that list's meta.available
# filter, so a broken bump fails the build loudly instead of silently dropping
# dsh.
#
# What the wrapper does, in order:
#   1. unsets DEEPSEEK_*: DEEPSEEK_BASE_URL alone repoints the official
#      adapter, which attaches the whole session log to any base URL;
#   2. DSH_TELEMETRY_DISABLED=1, the only full OTel opt-out;
#   3. refuses (exit 2, one stderr line): `dsh plugin` (plugins come from Nix
#      only), any profile but `profiles` (Tom, 2026-10-22: "no dsh web,
#      ever"; sdk-minimal pins danger-full-access), --from-default-profile
#      outside `profiles`, an empty profile word or `--profile` value, any
#      argv without a profile except a lone --version/-V/--help/-h,
#      DSH_PERMISSION_MODE=danger-full-access, a DSH_HOME under /tmp or
#      $TMPDIR (dsh's in-process write tool reaches both), and a cwd that is
#      $HOME or one of its parents, contains DSH_HOME or sits inside it. The
#      cwd is the write fence, and a writable profile patch is code (`!!js`
#      runs with full Node privileges);
#   4. puts the policy overlays (./config.nix, ./sessions.patch.yml) right
#      after the profile word, where `--patch` must go, so they are the last
#      config layer whatever DSH_HOME is. Overlays the caller passes come after
#      them (the gate's smoke overlay relies on that);
#   5. for a Nix-declared profile (`herdr`, below): adds its own overlay and
#      environment, and rewrites $DSH_HOME/profiles/<name>/package.json (0600)
#      and its node_modules links to the store plugins, every boot, before
#      dsh reads them. dsh's cordis.yml and cordis.patch.yml there are never
#      touched, and a store link no longer declared is removed;
#   6. reads the Qwen key from its agenix file into QWEN_TOKEN_PLAN_API_KEY
#      for the exec'd dsh only: never on argv, never echoed, never written
#      under DSH_HOME. dsh drops every *KEY*/*TOKEN* name and every DSH_* name
#      from the children it spawns, so the model's bash does not inherit it.
#      A missing file means no key, and the route fails MISSING_CREDENTIAL.
# It never sets DSH_HOME: ~/.dsh by default, an explicit one is respected.
let
  unwrapped = llm-agents.dsh;

  runner = writeShellApplication {
    name = "dsh-bwrap";
    runtimeInputs = [
      bubblewrap
      coreutils
    ];
    text = builtins.readFile ./dsh-bwrap.sh;
  };

  config = import ./config.nix {
    inherit lib formats runner;
  };
  sessions = ./sessions.patch.yml;

  # Profiles declared here rather than shipped by dsh. `herdr` is the stock
  # headless tuple plus the three plugins of pkgs/dsh-plugins and their
  # stderr log sink, for Tom to run by hand inside a Herdr pane
  # (`dsh herdr "<task>"`). Substrate drives the stock `headless` profile,
  # which never mounts them. The guard comes before dsh-herdr, which cannot
  # load without it either way. The owned plugins carry a private npm scope:
  # dsh resolves a bundle name from its own installation before the profile,
  # so a generic name could one day be shadowed by a dependency of a bump.
  nixProfiles = {
    herdr = {
      bundles = [
        "@deepseek-ai/dsh-base"
        "@deepseek-ai/dsh-headless"
        "@mecattaf/stderr-log"
        "@mecattaf/herdr-guard"
        "@dsh-external/dsh-herdr-toolkit"
        "jevcore-dsh"
      ];
      packages = {
        "@mecattaf/stderr-log" = dsh-plugins.stderr-log;
        "@mecattaf/herdr-guard" = dsh-plugins.herdr-guard;
        "@dsh-external/dsh-herdr-toolkit" = dsh-plugins.dsh-herdr;
        "jevcore-dsh" = dsh-plugins.jevcore;
      };
      patch = config.herdr;
      # No herdr call outlives 10 minutes (an unbounded `pane wait-output`
      # or `agent wait` included). DSH_HERDR_PREVIEW_REQUIRED stays unset: it
      # is the model checking itself, not a human gate.
      env.DSH_HERDR_CLI_TIMEOUT_MS = "600000";
    };
  };
  manifest =
    name: p:
    writeText "dsh-profile-${name}.json" (
      builtins.toJSON {
        name = "dsh-profile-${name}";
        private = true;
        dependencies = lib.mapAttrs (_: drv: drv.version) p.packages;
        dsh.profile.bundles = p.bundles;
      }
    );
  # One `case` arm per Nix-declared profile, indented for the wrapper text.
  nixProfileCase = lib.concatMapStringsSep "\n  " (
    name:
    let
      p = nixProfiles.${name};
    in
    lib.concatStringsSep "\n  " (
      [
        "${name})"
        "  overlays+=(--patch ${p.patch})"
      ]
      ++ lib.mapAttrsToList (k: v: "  export ${k}=${lib.escapeShellArg v}") p.env
      ++ [
        "  sync_profile ${name} ${manifest name p} ${
            lib.escapeShellArgs (lib.mapAttrsToList (pkg: drv: "${pkg}=${drv}") p.packages)
          }"
        "  ;;"
      ]
    )
  ) (lib.attrNames nixProfiles);

  allowed = profiles ++ lib.attrNames nixProfiles;
  profileCase = lib.concatStringsSep " | " allowed;
in
writeShellApplication {
  name = "dsh";
  # bwrap on PATH for the model's own commands; the sandbox itself uses the
  # absolute runner the policy pins.
  runtimeInputs = [
    bubblewrap
    coreutils
    findutils
  ];
  passthru = {
    inherit
      unwrapped
      runner
      sessions
      qwenKeyFile
      nixProfiles
      ;
    profiles = allowed;
    plugins = dsh-plugins;
    inherit (config)
      policy
      acp
      herdr
      herdrRows
      localProviders
      smoke
      policyIds
      disabledIds
      ;
  };
  meta = {
    description = "DeepSeek Harness behind the fleet policy (Qwen Cloud, Gufo and ds4 routes, hardened sandbox)";
    mainProgram = "dsh";
    inherit (unwrapped.meta) license platforms;
  };
  text = ''
    # Bash imports xtrace from an exported SHELLOPTS; the key read below must
    # never be traced.
    { set +o xtrace; } 2>/dev/null
    unset DEEPSEEK_API_KEY DEEPSEEK_BASE_URL DEEPSEEK_SEARCH_BASE_URL
    # Public dummy bearers for the keyless Gufo and ds4 servers, never agenix
    # secrets.
    export GUFO_API_KEY=local-no-auth
    export DS4_API_KEY=local-no-auth
    export DSH_TELEMETRY_DISABLED=1

    refuse() {
      echo "dsh: $*; refused by the fleet wrapper" >&2
      exit 2
    }

    if [ "''${1-}" = plugin ]; then
      refuse "plugins come from Nix only (no dsh plugin)"
    fi
    # dsh would read an empty first word as `--profile ""`, and the no-profile
    # branch below would boot it unwrapped.
    if [ "$#" -gt 0 ] && [ -z "''${1//[[:space:]]/}" ]; then
      refuse "an empty first argument"
    fi

    # The launcher reads its own options up to the first token it does not
    # know; a bare first word is shorthand for --profile <word>.
    profile=""
    have_profile=0
    from_default=""
    dump_default=0
    dumping=0
    launcher=()
    if [ "$#" -gt 0 ] && [ "''${1:0:1}" != - ]; then
      profile="$1"
      have_profile=1
      shift
    fi
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --profile)
          if [ "$have_profile" = 1 ] || [ "$#" -lt 2 ]; then break; fi
          profile="$2"
          have_profile=1
          shift 2
          ;;
        --profile=*)
          if [ "$have_profile" = 1 ]; then break; fi
          profile="''${1#--profile=}"
          have_profile=1
          shift
          ;;
        --patch | --from-default-profile)
          if [ "$#" -lt 2 ]; then break; fi
          if [ "$1" = --from-default-profile ]; then from_default="$2"; fi
          launcher+=("$1" "$2")
          shift 2
          ;;
        --patch=* | --from-default-profile=*)
          case "$1" in --from-default-profile=*) from_default="''${1#*=}" ;; esac
          launcher+=("$1")
          shift
          ;;
        --dump-default-config)
          dump_default=1
          dumping=1
          launcher+=("$1")
          shift
          ;;
        --dump-config | --dump-config-schema)
          dumping=1
          launcher+=("$1")
          shift
          ;;
        *) break ;;
      esac
    done

    # No profile: only a lone --version or --help reaches dsh unwrapped.
    # Anything else would let dsh pick the profile itself, past every check.
    if [ "$have_profile" = 0 ]; then
      if [ "''${#launcher[@]}" = 0 ] && [ "$#" = 1 ]; then
        case "$1" in
          -V | --version | -h | --help) exec ${unwrapped}/bin/dsh "$1" ;;
        esac
      fi
      refuse "no profile given (dsh <profile> ..., or a lone --version/--help)"
    fi
    if [ -z "''${profile//[[:space:]]/}" ]; then
      refuse "an empty profile name"
    fi

    case "$profile" in
      ${profileCase}) ;;
      *) refuse "profile '$profile' is not one of: ${lib.concatStringsSep ", " allowed}" ;;
    esac
    if [ -n "$from_default" ]; then
      case "$from_default" in
        ${profileCase}) ;;
        *) refuse "--from-default-profile '$from_default' is not one of: ${lib.concatStringsSep ", " allowed}" ;;
      esac
    fi
    if [ "''${DSH_PERMISSION_MODE-}" = danger-full-access ]; then
      refuse "DSH_PERMISSION_MODE=danger-full-access"
    fi

    # dsh treats a blank DSH_HOME as unset.
    dsh_home="''${DSH_HOME-}"
    if [ -z "''${dsh_home//[[:space:]]/}" ]; then dsh_home="$HOME/.dsh"; fi
    dsh_home="$(realpath -m -- "$dsh_home")"
    # dsh's in-process write and edit tools may write /tmp and os.tmpdir()
    # outside any sandbox, and a patch file under DSH_HOME is code.
    # Prefixes end in exactly one slash, so `/` itself matches everything
    # (bash never matches a quoted empty expansion followed by `/*`).
    for t in /tmp "''${TMPDIR:-/tmp}"; do
      t="$(realpath -m -- "$t")"
      case "$dsh_home/" in
        "''${t%/}/"*) refuse "DSH_HOME ($dsh_home) is under $t, which dsh's write tool can reach" ;;
      esac
    done
    here="$(pwd -P)"
    here_dir="''${here%/}/"
    home="$(realpath -m -- "$HOME")"
    case "$home/" in
      "$here_dir"*) refuse "the working directory $here is \$HOME or contains it, which would make it the writable workspace" ;;
    esac
    case "$dsh_home/" in
      "$here_dir"*) refuse "the working directory $here contains DSH_HOME ($dsh_home)" ;;
    esac
    case "$here/" in
      "$dsh_home"/*) refuse "the working directory $here is inside DSH_HOME ($dsh_home)" ;;
    esac
    # dsh-bwrap masks this too; DSH_* names never reach it.
    export DSHWRAP_HOME="$dsh_home"

    # A Nix-declared profile's manifest and plugin links, rewritten in place
    # (temp name, then rename) so a concurrent boot never reads half of one.
    # Temp links are staged in a per-process directory beside node_modules
    # (same filesystem, so the rename stays atomic), where no other boot's
    # sweep of undeclared store links can delete them mid-rename.
    sync_profile() {
      local dir="$dsh_home/profiles/$1" manifest="$2" pair name link i=0
      shift 2
      if [ ! -d "$dsh_home" ]; then (umask 077 && mkdir -p -- "$dsh_home"); fi
      mkdir -p -- "$dir/node_modules"
      install -m 0600 -- "$manifest" "$dir/package.json.$$"
      mv -f -- "$dir/package.json.$$" "$dir/package.json"
      local stage="$dir/.sync.$$" keep=" "
      rm -rf -- "$stage"
      mkdir -- "$stage"
      for pair in "$@"; do
        name="''${pair%%=*}"
        link="$dir/node_modules/$name"
        mkdir -p -- "$(dirname -- "$link")"
        i=$((i + 1))
        ln -sfn -- "''${pair#*=}" "$stage/$i"
        mv -fT -- "$stage/$i" "$link"
        keep+="$link "
      done
      rmdir -- "$stage"
      while IFS= read -r -d "" link; do
        case "$keep" in *" $link "*) ;; *) rm -f -- "$link" ;; esac
      done < <(find "$dir/node_modules" -mindepth 1 -maxdepth 2 -type l -lname '${builtins.storeDir}/*' -print0)
    }

    overlays=(--patch ${config.policy} --patch ${sessions})
    case "$profile" in
      acp) overlays+=(--patch ${config.acp}) ;;
      ${nixProfileCase}
    esac
    # --dump-default-config prints the bundle layers only and takes no --patch.
    if [ "$dump_default" = 1 ]; then overlays=(); fi
  ''
  # Without a key file nothing reads `dumping`; shellcheck would fail the build.
  + lib.optionalString (qwenKeyFile == null) ''

    : "$dumping"
    unset QWEN_TOKEN_PLAN_API_KEY
  ''
  + lib.optionalString (qwenKeyFile != null) ''

    # Not for config dumps, which make no request. Never traced.
    { set +o xtrace; } 2>/dev/null
    if [ "$dumping" = 0 ] && [ -r ${lib.escapeShellArg qwenKeyFile} ]; then
      QWEN_TOKEN_PLAN_API_KEY="$(< ${lib.escapeShellArg qwenKeyFile})"
      export QWEN_TOKEN_PLAN_API_KEY
    fi
  ''
  + ''

    exec ${unwrapped}/bin/dsh --profile "$profile" "''${overlays[@]}" "''${launcher[@]}" "$@"
  '';
}
