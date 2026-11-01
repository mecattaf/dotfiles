{ pkgs, dsh }:
let
  expected = pkgs.writeText "dsh-mnemon-expected.json" (builtins.toJSON dsh.mnemonRows);
  withoutMnemon = dsh.override {
    profilePlugins = dsh.profilePlugins // {
      mnemon = [ ];
    };
  };
in
pkgs.runCommand "dsh-mnemon"
  {
    nativeBuildInputs = [
      pkgs.nodejs
      pkgs.jq
      (pkgs.python3.withPackages (ps: [ ps.pyyaml ]))
    ];
  }
  ''
    set -euo pipefail
    build="$TMPDIR"
    export HOME="$build/home" DSH_HOME="$build/dsh-home" TMPDIR="$build/tmp"
    export MNEMON_DATA_DIR="$build/memory" MNEMON_EMBED_ENDPOINT=http://127.0.0.1:9
    export PYTHONDONTWRITEBYTECODE=1
    unset QWEN_TOKEN_PLAN_API_KEY MNEMON_EMBED_API_KEY MNEMON_EMBED_MODEL MNEMON_EMBED_PROTOCOL
    mkdir -p "$HOME" "$TMPDIR" "$build/workspace"
    cd "$build/workspace"
    dsh=${dsh}/bin/dsh
    mnemon=${dsh.mnemonPackage}/bin/mnemon

    "$mnemon" --version | grep -F '0.2.13'
    "$mnemon" store create smoke
    "$mnemon" --store smoke remember 'The amber otter selected the east bridge.' --cat decision --source synthetic > "$TMPDIR/remember.json"
    "$mnemon" --store smoke --readonly recall 'amber otter' --basic > "$TMPDIR/recall.json"
    jq -e 'length == 1 and .[0].content == "The amber otter selected the east bridge." and .[0].source == "synthetic"' "$TMPDIR/recall.json"
    # Opening a different store must not retrieve the first store's facts.
    "$mnemon" store create other
    "$mnemon" --store other --readonly recall 'amber otter' --basic | jq -e 'length == 0'
    # Read-only mode cannot silently persist a write.
    if "$mnemon" --store smoke --readonly remember 'must not be written' > "$TMPDIR/readonly.out" 2> "$TMPDIR/readonly.err"; then
      echo 'mnemon accepted a write in readonly mode' >&2
      exit 1
    fi

    export MNEMON_PLUGIN=${dsh.plugins.mnemon}
    node ${./documents.mjs}

    "$dsh" mnemon --dump-config > "$TMPDIR/mnemon.yml" 2> "$TMPDIR/dump.err"
    test ! -s "$TMPDIR/dump.err"
    python3 -I ${./check_dump.py} "$TMPDIR/mnemon.yml" ${expected}
    for profile in headless herdr; do
      "$dsh" "$profile" --dump-config > "$TMPDIR/$profile.yml" 2> "$TMPDIR/dump.err"
      test ! -s "$TMPDIR/dump.err"
      python3 -I ${./check_dump.py} "$TMPDIR/$profile.yml"
    done
    test "$(readlink "$DSH_HOME/profiles/mnemon/node_modules/dsh-mnemon")" = ${dsh.plugins.mnemon}
    test "$(stat -c %a "$DSH_HOME/profiles/mnemon/package.json")" = 600
    test ! -e "$DSH_HOME/profiles/herdr/node_modules/dsh-mnemon"
    test ! -e "$DSH_HOME/profiles/headless/node_modules"

    # Unknown session stops after plugins mount, before inference. No provider
    # or model is contacted; loader failures must still surface on stderr.
    rc=0
    "$dsh" mnemon --session-id session-none 'reply OK' > "$TMPDIR/boot.out" 2> "$TMPDIR/boot.err" || rc=$?
    cat "$TMPDIR/boot.err" >&2
    test "$rc" = 1
    grep -qF 'dsh: session "session-none" does not exist' "$TMPDIR/boot.err"
    if grep -Ei '(failed to load|cannot find|module_not_found|error:|unhandled|TypeError|ReferenceError)' "$TMPDIR/boot.err"; then
      exit 1
    fi
    export DSH_BIN="$dsh"
    export MNEMON_GUFO_CONFIG=${pkgs.lib.escapeShellArg (builtins.toJSON dsh.localProviders.gufo)}
    export MNEMON_MODEL_ID=${(builtins.head dsh.localProviders.gufo.models).id}
    node ${./mock-turn.mjs}
    # Declaratively deselecting the utility removes its runtime store link
    # and config rows, while preserving the already-created memory database.
    ${withoutMnemon}/bin/dsh mnemon --dump-config > "$TMPDIR/deselected.yml" 2> "$TMPDIR/dump.err"
    test ! -s "$TMPDIR/dump.err"
    python3 -I ${./check_dump.py} "$TMPDIR/deselected.yml"
    test ! -e "$DSH_HOME/profiles/mnemon/node_modules/dsh-mnemon"
    "$mnemon" --store smoke --readonly recall 'amber otter' --basic | jq -e 'length == 1'
    test ! -e "$HOME/.claude/settings.json"
    test ! -e "$HOME/.codex/hooks.json"
    touch "$out"
  ''
