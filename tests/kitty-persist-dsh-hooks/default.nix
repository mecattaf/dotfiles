{
  pkgs,
  dsh,
  # The kitty-persist program the session host installs: `harness check` on
  # the generated definition, and one turn in a session it holds (./turn.mjs
  # part 5).
  kitty-persist,
}:
# kitty-persist-hooks in real dsh turns (see ./turn.mjs): the `native`
# profile with only the log sink and the plugin, a mock OpenAI provider on
# loopback, a stub `kitty-persist` program that logs each call, then the real
# program and a holder of its own. Also: the plugin row mounts in that
# profile with the bare program name, the wrapper exports its harness name,
# and the stock headless profile mounts no such row. No network, no key: the
# wrapper of this check reads no key file.
let
  withHooks = dsh.override {
    qwenKeyFile = null;
    profilePlugins = dsh.profilePlugins // {
      native = [
        "stderr-log"
        "kitty-persist-hooks"
      ];
    };
  };
  defs = dsh.plugins.kitty-persist-hooks.definitions;
  definition = pkgs.writeText "dsh-native.json" (builtins.toJSON (defs.definition "native"));
in
assert withHooks.nixProfiles.native.env.DSH_KITTY_PERSIST_HARNESS == "dsh-native";
assert !(withHooks.nixProfiles.herdr.env ? DSH_KITTY_PERSIST_HARNESS);
pkgs.runCommand "kitty-persist-dsh-hooks"
  {
    nativeBuildInputs = [
      pkgs.nodejs
      (pkgs.python3.withPackages (ps: [ ps.pyyaml ]))
    ];
  }
  ''
    set -euo pipefail
    build="$TMPDIR"
    export HOME="$build/home" DSH_HOME="$build/dsh-home" TMPDIR="$build/tmp"
    export PYTHONDONTWRITEBYTECODE=1
    unset QWEN_TOKEN_PLAN_API_KEY GEMINI_API_KEY OPENCODE_ZEN_FREE_API_KEY KITTY_PERSIST_ID
    mkdir -p "$HOME" "$TMPDIR" "$build/workspace"
    mkdir -m 700 "$DSH_HOME"
    cd "$build/workspace"
    dsh=${withHooks}/bin/dsh

    "$dsh" native --dump-config > "$TMPDIR/native.yml"
    "$dsh" headless --dump-config > "$TMPDIR/headless.yml"
    python3 -I - "$TMPDIR/native.yml" "$TMPDIR/headless.yml" <<'EOF'
    import sys, yaml
    class L(yaml.SafeLoader): pass
    L.add_constructor("!!js", lambda l, n: l.construct_scalar(n))
    L.add_constructor("tag:yaml.org,2002:js", lambda l, n: l.construct_scalar(n))
    def rows(tree):
        stack = [tree]
        while stack:
            item = stack.pop()
            if isinstance(item, dict):
                if isinstance(item.get("id"), str):
                    yield item
                stack.extend(item.values())
            elif isinstance(item, list):
                stack.extend(item)
    native = {r["id"]: r for r in rows(yaml.load(open(sys.argv[1]), Loader=L))}
    headless = {r["id"] for r in rows(yaml.load(open(sys.argv[2]), Loader=L))}
    row = native.get("kitty-persist-hooks")
    assert row is not None and row.get("disabled") is not True, "plugin row missing in native"
    assert row.get("config") == {"command": "kitty-persist"}, row.get("config")
    assert "kitty-persist-hooks" not in headless, "plugin row in the stock headless profile"
    EOF
    grep -qE "export DSH_KITTY_PERSIST_HARNESS='?dsh-native'?$" "$dsh"

    # The program accepts the definition (exit 0; 64 would be invalid).
    cp ${definition} "$TMPDIR/dsh-native.json"
    XDG_CONFIG_HOME="$TMPDIR/check-config" ${kitty-persist}/bin/kitty-persist harness check "$TMPDIR/dsh-native.json"

    export DSH_BIN="$dsh" KP_DEFINITION=${definition} KP_PROGRAM=${kitty-persist}/bin/kitty-persist
    export MOCK_GUFO_CONFIG=${pkgs.lib.escapeShellArg (builtins.toJSON dsh.localProviders.gufo)}
    export MOCK_MODEL_ID=${(builtins.head dsh.localProviders.gufo.models).id}
    node ${./turn.mjs}
    touch "$out"
  ''
