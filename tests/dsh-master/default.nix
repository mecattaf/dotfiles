{ pkgs, configurations }:
# checks.dsh-master: the Master profile folders as NAS renders them.
#
#   1. eval: NAS renders them from activation; no other host does; Home
#      Manager owns nothing under ~/.dsh;
#   2. check_render.py: one folder per pair, identical dependencies, the app
#      bundle the only bundle difference, engine on only in master, no
#      permission rows, the pair rows, the seat, the policy;
#   3. dsh-master render in a scratch DSH_HOME: confined to profiles/master*,
#      idempotent, restores a changed file and says so, writes dsh's own
#      pnpm-workspace.yaml (compared with what the release's dsh writes for a
#      new profile) only where none exists;
#   4. dsh-master settings seed against a stub of the floor's settings API;
#   5. dsh-master check with the release's own dsh on the first-party half of
#      each folder (no network, no plugin): every rendered row is in the
#      composed tree, and no patch warning. A row aimed at a missing id fails.
#
# The extension rows (llm-claude, dsh-superagent) need the plugins installed;
# `dsh-master check` covers them on NAS after `dsh-master install`.
let
  inherit (pkgs) lib;
  nas = configurations.nas;
  hm = nas.config.home-manager.users.tom;
  cfg = hm.programs.dsh.master;
  master = cfg.package;
  releaseDsh = lib.getExe' nas.config.dshd.releases.nas.dsh "dsh";
  python = pkgs.python3.withPackages (ps: [ ps.pyyaml ]);
  enabledOn = name: configurations.${name}.config.home-manager.users.tom.programs.dsh.master.enable;
  # Both pins in the form the tag gives them; false once one is set by hand.
  pinsFollowTag =
    c:
    c.superagent == "github:mecattaf/dsh-superagent-prototype#${c.tag}"
    && c.claude == "github:mecattaf/dsh-claude#${c.tag}";
  # check_render.py's expectations: the configured values, never the
  # module's defaults restated, so a documented override stays green.
  expectOf =
    c: package:
    pkgs.writeText "dsh-master-expect.json" (
      builtins.toJSON {
        pairs = lib.mapAttrs (
          _: pair:
          lib.filterAttrs (_: v: v != null) {
            inherit (pair) provider model reasoningEffort;
          }
        ) c.pairs;
        pairEnv = lib.mapAttrs (_: pair: { inherit (pair) env maxWorkers; }) c.pairs;
        presets = lib.mapAttrs (_: pair: pair.preset) c.pairs;
        inherit (c)
          defaultPair
          stateDir
          claudeConfigDir
          tag
          superagent
          claude
          superagentRows
          ;
        pinsFollowTag = pinsFollowTag c;
        inherit (nas.pkgs.dsh) policyIds policyRows;
        inherit (package) dropped;
      }
    );
  expect = expectOf cfg master;
  masterOf =
    module:
    (nas.extendModules { modules = [ { home-manager.users.tom.programs.dsh.master = module; } ]; })
    .config.home-manager.users.tom.programs.dsh.master;
  # One tag value moves both pins (the module's defaults), whatever the
  # NAS itself sets.
  retagged = masterOf { tag = "floor-v2.99"; };
  # A fork-only re-tag and a changed Workflow row (docs/dsh-master.md):
  # rendered as configured, and the check stays green.
  overridden = masterOf {
    superagent = "github:mecattaf/dsh-superagent-prototype#floor-v2.98";
    superagentRows = [
      {
        id = "dsh-superagent-scheduled";
        disabled = false;
      }
      {
        id = "dsh-superagent-workflow";
        disabled = false;
        config = {
          pollMs = 5000;
          concurrency = 4;
          maxAttempts = 1;
          pair = "";
        };
      }
    ];
  };
in
assert cfg.enable;
assert builtins.elem master hm.home.packages;
assert hm.home.activation ? dshMasterProfiles;
assert lib.all (name: !(enabledOn name)) [
  "client"
  "strix-coordinator"
  "strix-worker"
];
assert
  !(lib.any (file: lib.hasPrefix ".dsh/" file.target || file.target == ".dsh") (
    builtins.attrValues hm.home.file
  ));
assert
  master.profileNames == [
    "master"
    "master-gufo"
    "master-opus"
  ];
# The Claude pair binds dsh-claude's preset; Gufo binds none.
assert cfg.pairs.opus.preset == "claude" && cfg.pairs.gufo.preset == null;
assert pinsFollowTag retagged && retagged.claude == "github:mecattaf/dsh-claude#floor-v2.99";
assert !(pinsFollowTag overridden) && overridden.claude == "github:mecattaf/dsh-claude#${overridden.tag}";
pkgs.runCommand "dsh-master" { nativeBuildInputs = [ python ]; } ''
  set -euo pipefail
  export HOME="$TMPDIR/home" PYTHONDONTWRITEBYTECODE=1
  mkdir -p "$HOME"
  python3 -I ${./check_render.py} ${master} ${expect}
  python3 -I ${./check_render.py} ${overridden.package} ${expectOf overridden overridden.package} > "$TMPDIR/overridden.out"
  grep -qx 'ok identical dependencies across profiles, pinned as configured' "$TMPDIR/overridden.out"
  DSH_MASTER=${master}/share/dsh-master/dsh-master.py SEED=${master}/share/dsh-master/settings.seed.json \
    python3 -I ${./test_seed.py} -v

  dm=${lib.getExe master}
  # status exits 1 while any folder is stale or not installed; its lines go to status.out.
  status() { local rc=0; $dm status > "$TMPDIR/status.out" || rc=$?; test "$rc" = "$1"; }
  # A lock that pins what package.json asks; a second argument re-tags the
  # fork's pin, as a failed install over an earlier good one leaves it.
  lock() {
    python3 -I - "$1" "''${2:-}" <<'PY'
  import json, sys, yaml
  folder, stale = sys.argv[1], sys.argv[2]
  with open(f"{folder}/package.json", encoding="utf-8") as stream:
      deps = json.load(stream)["dependencies"]
  pin = lambda d, s: s.rpartition("#")[0] + "#" + stale if stale and d == "dsh-superagent" else s
  lock = {"lockfileVersion": "9.0", "importers": {".": {"dependencies": {d: {"specifier": pin(d, s), "version": s} for d, s in deps.items()}}}}
  with open(f"{folder}/pnpm-lock.yaml", "w", encoding="utf-8") as stream:
      yaml.safe_dump(lock, stream)
  PY
  }
  tree() { (cd "$1" && find . -printf '%p %m %y\n' | sort && find . -type f -print0 | sort -z | xargs -0 sha256sum); }

  # 3. Confinement and idempotency. A foreign profile and dsh's own files
  # in a Master folder must come through byte-identical.
  export DSH_HOME="$TMPDIR/dsh-home"
  mkdir -p "$DSH_HOME/profiles/web" "$DSH_HOME/profiles/master/node_modules/x"
  echo '{"name":"dsh-profile-web"}' > "$DSH_HOME/profiles/web/package.json"
  echo '[]' > "$DSH_HOME/profiles/web/cordis.patch.yml"
  echo '[]' > "$DSH_HOME/profiles/master/cordis.yml"
  echo 'lock' > "$DSH_HOME/profiles/master/pnpm-lock.yaml"
  echo 'packages: [.]' > "$DSH_HOME/profiles/master/pnpm-workspace.yaml"
  echo '- id: home' > "$DSH_HOME/cordis.patch.yml"
  keep() { (cd "$DSH_HOME" && sha256sum cordis.patch.yml profiles/web/* profiles/master/cordis.yml profiles/master/pnpm-lock.yaml profiles/master/pnpm-workspace.yaml); }
  keep > "$TMPDIR/keep.before"

  $dm render > "$TMPDIR/first.out"
  # The workspace file a new folder gets is the one dsh itself writes.
  DSH_HOME="$TMPDIR/init-home" ${releaseDsh} plugin --profile master-init version-exemptions > /dev/null
  cmp "$TMPDIR/init-home/profiles/master-init/pnpm-workspace.yaml" ${master.pnpmWorkspace}
  for p in master-gufo master-opus; do
    cmp ${master.pnpmWorkspace} "$DSH_HOME/profiles/$p/pnpm-workspace.yaml"
    test "$(stat -c %a "$DSH_HOME/profiles/$p/pnpm-workspace.yaml")" = 644
    grep -qx "created $p/pnpm-workspace.yaml" "$TMPDIR/first.out"
  done
  if grep -q 'created master/' "$TMPDIR/first.out"; then exit 1; fi
  for p in master master-gufo master-opus; do
    grep -qx "install needed: $p" "$TMPDIR/first.out"
    cmp ${master}/profiles/$p/cordis.patch.yml "$DSH_HOME/profiles/$p/cordis.patch.yml"
    cmp ${master}/profiles/$p/package.json "$DSH_HOME/profiles/$p/package.json"
    test "$(stat -c %a "$DSH_HOME/profiles/$p/package.json")" = 600
    test "$(stat -c %a "$DSH_HOME/profiles/$p/cordis.patch.yml")" = 644
  done
  test "$(ls "$DSH_HOME/profiles" | sort | tr '\n' ' ')" = "master master-gufo master-opus web "
  tree "$DSH_HOME" > "$TMPDIR/tree.first"
  $dm render > "$TMPDIR/second.out" 2> "$TMPDIR/second.err"
  test ! -s "$TMPDIR/second.out" && test ! -s "$TMPDIR/second.err"
  tree "$DSH_HOME" > "$TMPDIR/tree.second"
  cmp "$TMPDIR/tree.first" "$TMPDIR/tree.second"
  keep | cmp - "$TMPDIR/keep.before"
  status 1
  grep -qx 'master: rendered current, installed no, node_modules present' "$TMPDIR/status.out"

  # install refuses a folder without the workspace file, before running dsh;
  # status calls it stale.
  rm "$DSH_HOME/profiles/master-gufo/pnpm-workspace.yaml"
  status 1
  grep -qx 'master-gufo: rendered stale, installed no, node_modules absent' "$TMPDIR/status.out"
  if $dm install --dsh /nonexistent master-gufo 2> "$TMPDIR/noworkspace.err"; then exit 1; fi
  grep -q 'master-gufo has no pnpm-workspace.yaml' "$TMPDIR/noworkspace.err"
  $dm render --quiet
  cmp ${master.pnpmWorkspace} "$DSH_HOME/profiles/master-gufo/pnpm-workspace.yaml"

  # install judges the folder, not dsh's exit: a lockfile and a built lib/
  # for each dependency (.js for the fork, .mjs for dsh-claude).
  opus="$DSH_HOME/profiles/master-opus"
  mkdir -p "$opus/node_modules/dsh-superagent/lib" "$opus/node_modules/@norman-else/dsh-claude/lib"
  touch "$opus/node_modules/dsh-superagent/lib/index.js"
  if $dm install --dsh ${pkgs.coreutils}/bin/true master-opus 2> "$TMPDIR/nolock.err"; then exit 1; fi
  grep -q 'no pnpm-lock.yaml; @norman-else/dsh-claude has no built lib/' "$TMPDIR/nolock.err"
  touch "$opus/node_modules/@norman-else/dsh-claude/lib/index.mjs"
  # A failed install over an earlier one: the old lock and the old lib/
  # stay. Whatever dsh exits, that is not installed.
  lock "$opus" floor-v0.0
  if $dm install --dsh ${pkgs.coreutils}/bin/true master-opus 2> "$TMPDIR/stale.err"; then exit 1; fi
  grep -qF "install failed (exit 0): pnpm-lock.yaml pins dsh-superagent as 'github:mecattaf/dsh-superagent-prototype#floor-v0.0'" "$TMPDIR/stale.err"
  if $dm install --dsh ${pkgs.coreutils}/bin/false master-opus 2> "$TMPDIR/stale1.err"; then exit 1; fi
  grep -qF 'install failed (exit 1): pnpm-lock.yaml pins dsh-superagent' "$TMPDIR/stale1.err"
  status 1
  grep -qx 'master-opus: rendered current, installed no, node_modules present' "$TMPDIR/status.out"
  lock "$opus"
  $dm install --dsh ${pkgs.coreutils}/bin/true master-opus | grep -qx 'installed master-opus'
  status 1
  grep -qx 'master-opus: rendered current, installed current, node_modules present' "$TMPDIR/status.out"
  # Every folder installed: status exits 0. A master* folder no build
  # renders is listed as an orphan and fails nothing.
  for p in master master-gufo; do
    f="$DSH_HOME/profiles/$p"
    mkdir -p "$f/node_modules/dsh-superagent/lib" "$f/node_modules/@norman-else/dsh-claude/lib"
    touch "$f/node_modules/dsh-superagent/lib/index.js" "$f/node_modules/@norman-else/dsh-claude/lib/index.mjs"
    lock "$f"
    $dm install --dsh ${pkgs.coreutils}/bin/true $p | grep -qx "installed $p"
  done
  mkdir "$DSH_HOME/profiles/master-retired"
  status 0
  grep -qx 'master-retired: orphan, not rendered by this build (remove it by hand when no instance uses it)' "$TMPDIR/status.out"
  test "$(grep -c 'rendered current, installed current' "$TMPDIR/status.out")" = 3
  rmdir "$DSH_HOME/profiles/master-retired"

  # install runs dsh with pnpm and git on PATH (dsh plugin spawns pnpm).
  grep -q '${lib.getBin nas.pkgs.pnpm}/bin' ${lib.getExe master}
  grep -q '${lib.getBin nas.pkgs.git}/bin' ${lib.getExe master}

  # A changed copy is put back, and the change is reported.
  echo '- id: hand-edit' >> "$DSH_HOME/profiles/master-gufo/cordis.patch.yml"
  $dm render --quiet > "$TMPDIR/third.out" 2> "$TMPDIR/third.err"
  test ! -s "$TMPDIR/third.out"
  grep -q 'master-gufo/cordis.patch.yml was changed outside dsh-master' "$TMPDIR/third.err"
  cmp ${master}/profiles/master-gufo/cordis.patch.yml "$DSH_HOME/profiles/master-gufo/cordis.patch.yml"

  # No DSH_HOME yet: nothing is created. A symlinked folder is refused.
  DSH_HOME="$TMPDIR/absent" $dm render --quiet 2> "$TMPDIR/absent.err"
  test ! -e "$TMPDIR/absent" && grep -q 'does not exist' "$TMPDIR/absent.err"
  mkdir -p "$TMPDIR/linked/profiles" "$TMPDIR/elsewhere"
  ln -s "$TMPDIR/elsewhere" "$TMPDIR/linked/profiles/master"
  if DSH_HOME="$TMPDIR/linked" $dm render --quiet 2> "$TMPDIR/linked.err"; then exit 1; fi
  grep -q 'symbolic link' "$TMPDIR/linked.err" && test -z "$(ls -A "$TMPDIR/elsewhere")"

  # 5. The release's dsh composes the first-party half of each folder with
  # every row in place and no warning.
  export DSH_HOME="$TMPDIR/probe-home"
  mkdir -p "$DSH_HOME" "$TMPDIR/cwd"
  cd "$TMPDIR/cwd"
  $dm render --quiet --from ${master.probes} > /dev/null
  $dm check --from ${master.probes} --dsh ${releaseDsh} | tee "$TMPDIR/check.out"
  test "$(grep -c '^ok ' "$TMPDIR/check.out")" = 3
  printf -- '- id: no-such-row\n  disabled: true\n' >> "$DSH_HOME/profiles/master-opus/cordis.patch.yml"
  if $dm check --from ${master.probes} --dsh ${releaseDsh} master-opus 2> "$TMPDIR/typo.err"; then exit 1; fi
  grep -q 'stderr: .*no-such-row' "$TMPDIR/typo.err"
  touch "$out"
''
