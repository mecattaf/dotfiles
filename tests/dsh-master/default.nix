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
#      new profile) only where none exists, and in it decides only the
#      configured allowBuilds keys that are absent or undecided; install
#      judges the folder and its lockfile, and refuses a profile a running
#      dshd instance uses;
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
  # dsh's own text plus the configured build decisions: what render leaves.
  buildLines = lib.concatStrings (
    lib.mapAttrsToList (name: allow: "  ${name}: ${lib.boolToString allow}\n") cfg.allowBuilds
  );
  withBuilds = text: if cfg.allowBuilds == { } then text else text + "allowBuilds:\n" + buildLines;
  decidedWorkspace = pkgs.writeText "pnpm-workspace.yaml" (withBuilds (builtins.readFile master.pnpmWorkspace));
  ownWorkspace = pkgs.writeText "pnpm-workspace.yaml" (withBuilds "packages: [.]\n");
  # `dshd ls` and `dshd get` as dshd prints them: floor runs $STUB_PROFILE.
  dshdStub = pkgs.writeShellScript "dshd-stub" ''
    case "$1" in
      ls) echo '{"instances":[{"name":"floor","state":"running"},{"name":"done","state":"stopped"}]}' ;;
      get) printf '{"name":"%s","activeState":"active","profile":{"name":"%s","dshHome":"%s"}}\n' "$3" "$STUB_PROFILE" "$DSH_HOME" ;;
      *) exit 2 ;;
    esac
  '';
  enabledOn = name: configurations.${name}.config.home-manager.users.tom.programs.dsh.master.enable;
  expect = pkgs.writeText "dsh-master-expect.json" (
    builtins.toJSON {
      pairs = lib.mapAttrs (
        _: pair:
        lib.filterAttrs (_: v: v != null) {
          inherit (pair) provider model reasoningEffort;
        }
      ) cfg.pairs;
      pairEnv = lib.mapAttrs (_: pair: { inherit (pair) env maxWorkers; }) cfg.pairs;
      presets = lib.mapAttrs (_: pair: pair.preset) cfg.pairs;
      inherit (cfg)
        defaultPair
        stateDir
        claudeConfigDir
        tag
        ;
      inherit (nas.pkgs.dsh) policyIds policyRows;
      inherit (master) dropped;
    }
  );
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
# One tag value moves both pins.
assert
  cfg.superagent == "github:mecattaf/dsh-superagent-prototype#${cfg.tag}"
  && cfg.claude == "github:mecattaf/dsh-claude#${cfg.tag}";
pkgs.runCommand "dsh-master" { nativeBuildInputs = [ python ]; } ''
  set -euo pipefail
  export HOME="$TMPDIR/home" PYTHONDONTWRITEBYTECODE=1
  mkdir -p "$HOME"
  python3 -I ${./check_render.py} ${master} ${expect}
  DSH_MASTER=${master}/share/dsh-master/dsh-master.py SEED=${master}/share/dsh-master/settings.seed.json \
    python3 -I ${./test_seed.py} -v

  dm=${lib.getExe master}
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
  keep() { (cd "$DSH_HOME" && sha256sum cordis.patch.yml profiles/web/* profiles/master/cordis.yml profiles/master/pnpm-lock.yaml); }
  keep > "$TMPDIR/keep.before"

  $dm render > "$TMPDIR/first.out"
  # The workspace file a new folder gets is the one dsh itself writes.
  DSH_HOME="$TMPDIR/init-home" ${releaseDsh} plugin --profile master-init version-exemptions > /dev/null
  cmp "$TMPDIR/init-home/profiles/master-init/pnpm-workspace.yaml" ${master.pnpmWorkspace}
  for p in master-gufo master-opus; do
    cmp ${decidedWorkspace} "$DSH_HOME/profiles/$p/pnpm-workspace.yaml"
    test "$(stat -c %a "$DSH_HOME/profiles/$p/pnpm-workspace.yaml")" = 644
    grep -qx "created $p/pnpm-workspace.yaml" "$TMPDIR/first.out"
  done
  if grep -q 'created master/' "$TMPDIR/first.out"; then exit 1; fi
  # A folder's own workspace keeps its keys; render adds only the decisions.
  cmp ${ownWorkspace} "$DSH_HOME/profiles/master/pnpm-workspace.yaml"
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
  # Nothing written, and the install still owed is said again.
  if grep -v '^install needed: ' "$TMPDIR/second.out"; then exit 1; fi
  test ! -s "$TMPDIR/second.err"
  for p in master master-gufo master-opus; do grep -qx "install needed: $p" "$TMPDIR/second.out"; done
  tree "$DSH_HOME" > "$TMPDIR/tree.second"
  cmp "$TMPDIR/tree.first" "$TMPDIR/tree.second"
  keep | cmp - "$TMPDIR/keep.before"
  $dm status | grep >/dev/null -x 'master: rendered current, installed no, node_modules present'

  # install refuses a folder without the workspace file, before running dsh;
  # status calls it stale.
  rm "$DSH_HOME/profiles/master-gufo/pnpm-workspace.yaml"
  $dm status | grep >/dev/null -x 'master-gufo: rendered stale, installed no, node_modules absent'
  if $dm install --dsh /nonexistent master-gufo 2> "$TMPDIR/noworkspace.err"; then exit 1; fi
  grep -q 'master-gufo has no pnpm-workspace.yaml' "$TMPDIR/noworkspace.err"
  $dm render --quiet
  cmp ${decidedWorkspace} "$DSH_HOME/profiles/master-gufo/pnpm-workspace.yaml"

  # dsh records an undecided build after a failed install: render decides
  # the configured one, keeps a person's own decision and the other keys,
  # and status says what is still pending.
  ws="$DSH_HOME/profiles/master-gufo/pnpm-workspace.yaml"
  { cat ${master.pnpmWorkspace}; printf 'allowBuilds:\n  msgpackr-extract: set this to true or false\n  other-native: set this to true or false\n'; } > "$ws"
  chmod 600 "$ws"
  $dm status | grep >/dev/null -x 'master-gufo: rendered stale, installed no, node_modules absent, builds pending: msgpackr-extract, other-native'
  $dm render | grep >/dev/null -x 'updated master-gufo/pnpm-workspace.yaml (allowBuilds)'
  ${python}/bin/python3 -I -c 'import sys, yaml; d = yaml.safe_load(open(sys.argv[1])); assert d["allowBuilds"] == {"msgpackr-extract": False, "other-native": "set this to true or false"} and d["nodeLinker"] == "hoisted", d' "$ws"
  test "$(stat -c %a "$ws")" = 600
  $dm status | grep >/dev/null -x 'master-gufo: rendered current, installed no, node_modules absent, builds pending: other-native'
  { cat ${master.pnpmWorkspace}; printf 'allowBuilds:\n  msgpackr-extract: true\n'; } > "$ws"
  if $dm render | grep >/dev/null 'master-gufo/pnpm-workspace'; then exit 1; fi
  grep -qx '  msgpackr-extract: true' "$ws"
  cp ${decidedWorkspace} "$ws"

  # install judges the folder, not dsh's exit: a lockfile that locks this
  # package.json and a built lib/ for each dependency (.js for the fork,
  # .mjs for dsh-claude). A dsh that never ran fails whatever the folder holds.
  export STUB_PROFILE=master
  di="install --dshd ${dshdStub}"
  opus="$DSH_HOME/profiles/master-opus"
  mkdir -p "$opus/node_modules/dsh-superagent/lib" "$opus/node_modules/@norman-else/dsh-claude/lib"
  touch "$opus/node_modules/dsh-superagent/lib/index.js"
  if $dm $di --dsh ${pkgs.coreutils}/bin/true master-opus 2> "$TMPDIR/nolock.err"; then exit 1; fi
  grep -q 'no pnpm-lock.yaml; @norman-else/dsh-claude has no built lib/' "$TMPDIR/nolock.err"
  touch "$opus/node_modules/@norman-else/dsh-claude/lib/index.mjs"
  # An earlier install's lockfile and lib/ (the pin moved, the fetch failed).
  ${python}/bin/python3 -I ${./lockfile.py} "$opus" floor-v0.0
  if $dm $di --dsh ${pkgs.coreutils}/bin/false master-opus 2> "$TMPDIR/stale.err"; then exit 1; fi
  grep -q 'install failed (exit 1): pnpm-lock.yaml locks @norman-else/dsh-claude at github:mecattaf/dsh-claude#floor-v0.0, not ' "$TMPDIR/stale.err"
  $dm status | grep >/dev/null -x 'master-opus: rendered current, installed no, node_modules present'
  ${python}/bin/python3 -I ${./lockfile.py} "$opus"
  if $dm $di --dsh /nonexistent/dsh master-opus 2> "$TMPDIR/notrun.err"; then exit 1; fi
  grep -q 'install failed: /nonexistent/dsh did not run (exit 127)' "$TMPDIR/notrun.err"
  $dm status | grep >/dev/null -x 'master-opus: rendered current, installed no, node_modules present'
  # A running instance of the profile refuses the install, unless --force.
  if STUB_PROFILE=master-opus $dm $di --dsh ${pkgs.coreutils}/bin/true master-opus 2> "$TMPDIR/busy.err"; then exit 1; fi
  grep -q 'dshd instance floor is running master-opus; stop it first' "$TMPDIR/busy.err"
  if $dm install --dshd /nonexistent/dshd --dsh ${pkgs.coreutils}/bin/true master-opus 2> "$TMPDIR/nodshd.err"; then exit 1; fi
  grep -q 'cannot tell which dshd instances run' "$TMPDIR/nodshd.err"
  $dm status | grep >/dev/null -x 'master-opus: rendered current, installed no, node_modules present'
  # A complete folder counts even when dsh exits 1 (pnpm's ignored builds).
  $dm $di --dsh ${pkgs.coreutils}/bin/false master-opus > "$TMPDIR/done.out" 2> "$TMPDIR/done.err"
  grep -qx 'installed master-opus' "$TMPDIR/done.out"
  grep -q 'install exited 1, but the folder is complete' "$TMPDIR/done.err"
  STUB_PROFILE=master-opus $dm install --force --dshd /nonexistent/dshd --dsh ${pkgs.coreutils}/bin/true master-opus | grep >/dev/null -x 'installed master-opus'
  $dm status | grep >/dev/null -x 'master-opus: rendered current, installed current, node_modules present'

  # install runs dsh with pnpm and git on PATH (dsh plugin spawns pnpm).
  grep -q '${lib.getBin nas.pkgs.pnpm}/bin' ${lib.getExe master}
  grep -q '${lib.getBin nas.pkgs.git}/bin' ${lib.getExe master}

  # A changed copy is put back, and the change is reported.
  echo '- id: hand-edit' >> "$DSH_HOME/profiles/master-gufo/cordis.patch.yml"
  $dm render --quiet > "$TMPDIR/third.out" 2> "$TMPDIR/third.err"
  if grep -v '^install needed: ' "$TMPDIR/third.out"; then exit 1; fi
  if grep -q 'install needed: master-opus' "$TMPDIR/third.out"; then exit 1; fi
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
