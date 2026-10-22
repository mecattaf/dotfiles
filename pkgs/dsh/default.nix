{
  lib,
  writeShellApplication,
  formats,
  bubblewrap,
  coreutils,
  llm-agents,
  # The agent host's agenix path for the Qwen Token Plan key. home/dsh.nix
  # passes osConfig's path, or null where the secret is not declared.
  qwenKeyFile ? "/run/agenix/qwencloud-token",
  # The profiles the wrapper will boot. Everything else is refused, so a
  # custom profile cannot carry the web or sdk-minimal bundles past the name
  # check. The plugin PR adds its own profile here.
  profiles ? [
    "headless"
    "sdk"
    "acp"
  ],
}:
# dsh: DeepSeek Harness from llm-agents.nix (Tom's ruling, 2026-10-22: "use
# llm-agents.nix"), served signed by numtide's cache, so nothing in the 712 MB
# tree builds here. This wrapper is the only `dsh` on PATH: `dsh` stays out of
# home/home.nix's keepFromLlmAgents for the same reason pi does there (two
# bin/dsh would collide). A direct llm-agents.dsh reference also skips that
# list's meta.available filter, so a broken bump fails the build loudly
# instead of silently dropping dsh.
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
#   5. reads the Qwen key from its agenix file into QWEN_TOKEN_PLAN_API_KEY
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

  profileCase = lib.concatStringsSep " | " profiles;
in
writeShellApplication {
  name = "dsh";
  # bwrap on PATH for the model's own commands; the sandbox itself uses the
  # absolute runner the policy pins.
  runtimeInputs = [
    bubblewrap
    coreutils
  ];
  passthru = {
    inherit
      unwrapped
      runner
      sessions
      profiles
      qwenKeyFile
      ;
    inherit (config)
      policy
      acp
      smoke
      policyIds
      disabledIds
      ;
  };
  meta = {
    description = "DeepSeek Harness behind the fleet policy (Qwen Cloud route, hardened sandbox)";
    mainProgram = "dsh";
    inherit (unwrapped.meta) license platforms;
  };
  text = ''
    # Bash imports xtrace from an exported SHELLOPTS; the key read below must
    # never be traced.
    { set +o xtrace; } 2>/dev/null
    unset DEEPSEEK_API_KEY DEEPSEEK_BASE_URL DEEPSEEK_SEARCH_BASE_URL
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
      *) refuse "profile '$profile' is not one of: ${lib.concatStringsSep ", " profiles}" ;;
    esac
    if [ -n "$from_default" ]; then
      case "$from_default" in
        ${profileCase}) ;;
        *) refuse "--from-default-profile '$from_default' is not one of: ${lib.concatStringsSep ", " profiles}" ;;
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

    overlays=(--patch ${config.policy} --patch ${sessions})
    if [ "$profile" = acp ]; then overlays+=(--patch ${config.acp}); fi
    # --dump-default-config prints the bundle layers only and takes no --patch.
    if [ "$dump_default" = 1 ]; then overlays=(); fi
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
