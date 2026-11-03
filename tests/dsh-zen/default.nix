{ pkgs, dsh }:
# dsh-zen: the hand-run `zen` profile (pkgs/dsh, docs/free-lanes.md). Same
# sandbox as dsh-config: no network, a private DSH_HOME, and no key by
# construction (the NAS package's `keyFiles` is empty; only home/dsh.nix adds
# the agenix paths). What it proves:
#   - jiesou's plugin package built, so its installCheck passed (peer-only
#     imports, host allowlist), and nothing in the dsh installation shadows
#     its npm scope;
#   - `zen --dump-config` composes with the plugin row mounted, the fleet rows
#     intact, `credentials` re-enabled (the headless bundle disables it) and
#     Zen as the default route; `headless` mounts none of it and keeps
#     `credentials` disabled;
#   - DSH_ROUTE and DSH_KEY_SLOT overlays and refusals in the wrapper;
#   - a boot of `zen` with an unknown session id stops after the plugins
#     mounted and before any model call, with the plugin's own ready line:
#     the import against this dsh's pi-ai (the manifest says ^0.85.1, the
#     fleet ships 1.3.0), createProvider and registerAdapter all ran. The
#     catalog comes from a seeded last-good cache, since the sandbox has no
#     network; the unpkg fetch falls back to the plugin's 1.19.0 constant.
# Nothing here talks to opencode.ai; the live smoke is Tom's first `dsh zen`.
let
  inherit (pkgs) lib;
  plugin = dsh.plugins.opencode-zen-free;
  base = {
    localProviders = dsh.localProviders;
    cloudProviders = dsh.cloudProviders;
    defaultRoute = dsh.defaultRoute;
    disabled = dsh.disabledIds;
    runner = "${dsh.runner}/bin/dsh-bwrap";
  };
  zenPresent = [
    "stderr-log"
    dsh.zenProvider
    "credentials"
  ];
  otherPlugins = [
    "herdr-guard"
    "dsh-herdr-toolkit"
    "jev"
    "mnemon"
  ];
  expect = name: attrs: pkgs.writeText "dsh-zen-${name}.json" (builtins.toJSON (base // attrs));
  expectZen = expect "zen" {
    defaultRoute = dsh.routes.zen-deepseek;
    rows = dsh.zenRows;
    present = zenPresent;
    absent = otherPlugins;
  };
  # DSH_ROUTE replaces the profile's own default-model row, nothing else.
  expectZenGlm = expect "zen-glm" {
    defaultRoute = dsh.routes.zen-glm;
    rows = builtins.removeAttrs dsh.zenRows [ "agent-default-model" ];
    present = zenPresent;
    absent = otherPlugins;
  };
  expectHeadless = expect "headless" {
    absent = [
      dsh.zenProvider
      "stderr-log"
    ];
    disabledRows = [ "credentials" ];
  };
  # The slot reader, with key files that exist only inside this sandbox and
  # hold no secret. Static paths: the sandbox build directory is /build.
  keyed = dsh.override {
    keyFiles = {
      GEMINI_API_KEY = map (n: "/build/keys/gemini-${toString n}") (lib.range 1 3);
      OPENCODE_ZEN_FREE_API_KEY = map (n: "/build/keys/zen-${toString n}") (lib.range 1 4);
    };
  };
  # The seeded last-good catalog, in the plugin's own cache format.
  catalog = pkgs.writeText "opencode-zen-free-provider-catalog.json" (
    builtins.toJSON {
      zen = [ { id = "deepseek-v4.1-flash-free"; } ];
      models."deepseek-v4.1-flash-free" = {
        name = "DeepSeek V4.1 Flash";
        reasoning_options = [ ];
        limit = {
          context = 1048576;
          output = 32768;
        };
        modalities.input = [ "text" ];
      };
      userAgent = "opencode/1.19.0";
    }
  );
in
pkgs.runCommand "dsh-zen"
  {
    nativeBuildInputs = [
      pkgs.nodejs
      (pkgs.python3.withPackages (ps: [ ps.pyyaml ]))
    ];
  }
  ''
    set -euo pipefail
    # Built, so its installCheck passed.
    : ${plugin}
    test -f ${plugin}/lib/index.js
    test -f ${plugin}/cordis.patch.yml
    test ! -e ${plugin}/node_modules
    # The plugin's scope: nothing in the dsh installation, which resolves
    # bundle names first, may shadow it.
    u=${dsh.unwrapped}/lib/node_modules
    test ! -e "$u/@jiesou"
    test ! -e "$u/@deepseek-ai/dsh/node_modules/@jiesou"

    build="$TMPDIR"
    export HOME="$build/home" DSH_HOME="$build/dsh-home" TMPDIR="$build/tmp"
    export PYTHONDONTWRITEBYTECODE=1
    unset GEMINI_API_KEY OPENCODE_ZEN_FREE_API_KEY OPENCODE_API_KEY QWEN_TOKEN_PLAN_API_KEY
    mkdir -p "$HOME" "$build/cwd" "$TMPDIR"
    mkdir -m 700 "$DSH_HOME"
    cd "$build/cwd"
    dsh=${dsh}/bin/dsh
    if grep -qF /run/agenix "$dsh"; then
      echo "dsh-zen: the check's wrapper names a key file" >&2
      exit 1
    fi

    dump() {
      name="$1" expect="$2"
      shift 2
      "$@" > "$TMPDIR/$name.yml" 2> "$TMPDIR/$name.err"
      if [ -s "$TMPDIR/$name.err" ]; then
        echo "$*: stderr not empty:" >&2
        cat "$TMPDIR/$name.err" >&2
        exit 1
      fi
      python3 -I ${../dsh-config/check_dump.py} "$TMPDIR/$name.yml" "$expect"
    }
    dump zen ${expectZen} "$dsh" zen --dump-config
    dump zen-glm ${expectZenGlm} env DSH_ROUTE=zen-glm "$dsh" zen --dump-config
    dump headless ${expectHeadless} "$dsh" headless --dump-config
    # A slot past every list is still a valid run for a dump.
    dump zen-slot ${expectZen} env DSH_KEY_SLOT=9 "$dsh" zen --dump-config

    # The synced profile: a private manifest and store links only.
    p="$DSH_HOME/profiles/zen"
    test "$(stat -c %a "$p/package.json")" = 600
    test "$(readlink "$p/node_modules/@mecattaf/stderr-log")" = ${dsh.plugins.stderr-log}
    test "$(readlink "$p/node_modules/@jiesou/dsh-opencode-zen-free-provider")" = ${plugin}
    test ! -e "$DSH_HOME/profiles/headless/node_modules"

    refused() {
      set +e
      "$@" > /dev/null 2> "$TMPDIR/refused.err"
      code=$?
      set -e
      if [ "$code" != 2 ] || ! grep -q 'refused by the fleet wrapper' "$TMPDIR/refused.err"; then
        echo "expected a refusal (exit 2), got $code from: $*" >&2
        cat "$TMPDIR/refused.err" >&2
        exit 1
      fi
    }
    refused env DSH_KEY_SLOT=0 "$dsh" zen --dump-config
    refused env DSH_KEY_SLOT=x "$dsh" zen --dump-config
    refused env DSH_KEY_SLOT= "$dsh" zen --dump-config
    refused env DSH_ROUTE=nope "$dsh" zen --dump-config
    refused env DSH_ROUTE=zen-glm "$dsh" mnemon --dump-config

    # The seeded last-good catalog (no network here); the plugin reads it
    # under $DSH_HOME/cache.
    mkdir -p "$DSH_HOME/cache"
    cp ${catalog} "$DSH_HOME/cache/opencode-zen-free-provider-catalog.json"

    # The slot reader of a keyed wrapper: a slot past a list's length says so
    # once on stderr and exports nothing; a dump never reads a file. The
    # files hold no secret and exist only here.
    if mkdir -p /build/keys 2>/dev/null; then
      for f in gemini-1 gemini-2 gemini-3 zen-1 zen-2 zen-3 zen-4; do
        echo "not-a-key-$f" > "/build/keys/$f"
      done
      keyed=${keyed}/bin/dsh
      dump keyed-dump ${expectZen} "$keyed" zen --dump-config
      rc=0
      env DSH_KEY_SLOT=4 "$keyed" zen --session-id session-none "reply OK" > /dev/null 2> "$TMPDIR/slot4.err" || rc=$?
      test "$rc" = 1
      grep -qF 'DSH_KEY_SLOT=4 but GEMINI_API_KEY has only 3 key file(s); no key exported' "$TMPDIR/slot4.err"
      if grep -qF 'OPENCODE_ZEN_FREE_API_KEY has only' "$TMPDIR/slot4.err"; then exit 1; fi
      rc=0
      env DSH_KEY_SLOT=5 "$keyed" zen --session-id session-none "reply OK" > /dev/null 2> "$TMPDIR/slot5.err" || rc=$?
      test "$rc" = 1
      grep -qF 'OPENCODE_ZEN_FREE_API_KEY has only 4 key file(s); no key exported' "$TMPDIR/slot5.err"
      if grep -rF 'not-a-key-' "$TMPDIR" "$DSH_HOME"; then
        echo "dsh-zen: a key file's contents reached a file" >&2
        exit 1
      fi
    else
      echo "dsh-zen: no /build, slot reader not exercised" >&2
    fi

    # The whole tree boots: an unknown --session-id fails in headless after
    # the loader settled and before any model call. The plugin prints its
    # ready line through stderr-log, from the seeded cache.
    rc=0
    "$dsh" zen --session-id session-none "reply OK" > "$TMPDIR/boot.out" 2> "$TMPDIR/boot.err" || rc=$?
    cat "$TMPDIR/boot.err" >&2
    echo "dsh zen boot: exit $rc" >&2
    test "$rc" = 1
    grep -qF 'dsh: session "session-none" does not exist' "$TMPDIR/boot.err"
    grep -qF '[opencode-zen-free-provider] catalog fetch failed' "$TMPDIR/boot.err"
    grep -qF 'using the cached catalog' "$TMPDIR/boot.err"
    grep -qF 'info: [opencode-zen-free-provider] synced 1 free model(s): deepseek-v4.1-flash-free' "$TMPDIR/boot.err"
    if grep -Ei '(failed to load|cannot find|module_not_found|unhandled|TypeError|ReferenceError|skipping profile bundle|incompatible with dsh)' "$TMPDIR/boot.err"; then
      exit 1
    fi
    # No DeepSeek identity minted, no key file read.
    test ! -e "$DSH_HOME/.anonymous-user-id"
    touch "$out"
  ''
