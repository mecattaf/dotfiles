{ pkgs, configurations }:
# checks.dsh-master: the Master profile folders as NAS renders them.
#
#   1. eval: NAS renders them from activation; no other host does; Home
#      Manager owns nothing under ~/.dsh;
#   2. check_render.py: one folder per pair, identical dependencies, the app
#      bundle the only bundle difference, engine on only in master, no
#      permission rows, the pair rows, the seat, the policy;
#   3. dsh-master render in a scratch DSH_HOME: confined to profiles/master*,
#      idempotent, restores a changed file and says so, owns
#      pnpm-workspace.yaml: dsh's own text (compared with what the release's
#      dsh writes for a new profile) plus the build policy, replacing a copy
#      that differs, one DSH's plugin manager changed included;
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
        allowBuilds
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
  # in a Master folder must come through byte-identical; a workspace file
  # that is not the rendered one is replaced and reported.
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

  $dm render > "$TMPDIR/first.out" 2> "$TMPDIR/first.err"
  # The workspace file starts with the text dsh itself writes for a new
  # profile; the build policy follows it.
  DSH_HOME="$TMPDIR/init-home" ${releaseDsh} plugin --profile master-init version-exemptions > /dev/null
  cmp "$TMPDIR/init-home/profiles/master-init/pnpm-workspace.yaml" ${master.dshWorkspace}
  head -c "$(stat -c %s ${master.dshWorkspace})" ${master.pnpmWorkspace} | cmp - ${master.dshWorkspace}
  grep -qx '  "msgpackr-extract": false' ${master.pnpmWorkspace}
  for p in master master-gufo master-opus; do
    cmp ${master.pnpmWorkspace} "$DSH_HOME/profiles/$p/pnpm-workspace.yaml"
    test "$(stat -c %a "$DSH_HOME/profiles/$p/pnpm-workspace.yaml")" = 644
    grep -qx "updated $p/pnpm-workspace.yaml" "$TMPDIR/first.out"
  done
  # master had a workspace file and no render state: someone else wrote it.
  grep -qx 'dsh-master: master/pnpm-workspace.yaml was changed outside dsh-master; replacing it' "$TMPDIR/first.err"
  test "$(wc -l < "$TMPDIR/first.err")" = 1
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
  $dm status | grep -qx 'master: rendered current, installed no, node_modules present'

  # install refuses a folder without the workspace file, or with another
  # one, before running dsh; status calls it stale.
  rm "$DSH_HOME/profiles/master-gufo/pnpm-workspace.yaml"
  $dm status | grep -qx 'master-gufo: rendered stale, installed no, node_modules absent'
  if $dm install --dsh /nonexistent master-gufo 2> "$TMPDIR/noworkspace.err"; then exit 1; fi
  grep -q 'master-gufo is not the rendered version' "$TMPDIR/noworkspace.err"
  $dm render --quiet
  cmp ${master.pnpmWorkspace} "$DSH_HOME/profiles/master-gufo/pnpm-workspace.yaml"
  # A build DSH's plugin manager recorded as pending (dsh-plugin-manager
  # recordPendingBuilds) is replaced by the rendered policy, and said so.
  printf '  esbuild: set this to true or false\n' >> "$DSH_HOME/profiles/master-gufo/pnpm-workspace.yaml"
  $dm status | grep -qx 'master-gufo: rendered stale, installed no, node_modules absent'
  if $dm install --dsh /nonexistent master-gufo 2> /dev/null; then exit 1; fi
  $dm render --quiet 2> "$TMPDIR/pending.err"
  grep -qx 'dsh-master: master-gufo/pnpm-workspace.yaml was changed outside dsh-master; replacing it' "$TMPDIR/pending.err"
  cmp ${master.pnpmWorkspace} "$DSH_HOME/profiles/master-gufo/pnpm-workspace.yaml"
  # A folder rendered before render owned the file (its state records no
  # digest of it) gets the file replaced, with that reason.
  python3 -I -c 'import json, sys; s = json.load(open(sys.argv[1])); s["rendered"].pop("pnpm-workspace.yaml"); json.dump(s, open(sys.argv[1], "w"))' \
    "$DSH_HOME/profiles/master-gufo/.dsh-master.json"
  cp ${master.dshWorkspace} "$DSH_HOME/profiles/master-gufo/pnpm-workspace.yaml"
  $dm render --quiet 2> "$TMPDIR/migrate.err"
  grep -qx 'dsh-master: master-gufo/pnpm-workspace.yaml predates dsh-master rendering it; replacing it' "$TMPDIR/migrate.err"
  cmp ${master.pnpmWorkspace} "$DSH_HOME/profiles/master-gufo/pnpm-workspace.yaml"
  grep -q '"pnpm-workspace.yaml"' "$DSH_HOME/profiles/master-gufo/.dsh-master.json"

  # install judges the folder, not dsh's exit: a lockfile and a built lib/
  # for each dependency (.js for the fork, .mjs for dsh-claude).
  opus="$DSH_HOME/profiles/master-opus"
  mkdir -p "$opus/node_modules/dsh-superagent/lib" "$opus/node_modules/@norman-else/dsh-claude/lib"
  touch "$opus/node_modules/dsh-superagent/lib/index.js"
  if $dm install --dsh ${pkgs.coreutils}/bin/true master-opus 2> "$TMPDIR/nolock.err"; then exit 1; fi
  grep -q 'no pnpm-lock.yaml; @norman-else/dsh-claude has no built lib/' "$TMPDIR/nolock.err"
  touch "$opus/pnpm-lock.yaml" "$opus/node_modules/@norman-else/dsh-claude/lib/index.mjs"
  $dm install --dsh ${pkgs.coreutils}/bin/true master-opus | grep -qx 'installed master-opus'
  $dm status | grep -qx 'master-opus: rendered current, installed current, node_modules present'

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
