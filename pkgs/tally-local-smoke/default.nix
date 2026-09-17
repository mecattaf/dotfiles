{
  coreutils,
  writeShellApplication,
}:
# tally-local-smoke — the argv of the `build:LOCAL-SMOKE` kit entry.
#
# WHAT IT IS. The one deliberately LOCAL, deterministic job the box's kit
# enables beside the CUBS campaign: it closes the `usage_source` join the kernel
# has never been given. `exec.run` resolves `usage_source.path_glob` (first `*`
# -> the execution id's digest, tally crates/tally-kernel/src/exec.rs:95-140),
# exports it to the child as TALLY_USAGE_SOURCE_PATH together with
# TALLY_EXECUTION_ID (exec.rs:689), and writes `usage_source{kind,path}` into the
# `witness_record` (exec.rs:953-958). This script's whole job is to leave one
# line at that path carrying the execution id it was given, so the artifact and
# the receipt name each other.
#
# WHY A PACKAGE NOW, AND NOT THE `pkgs.writeShellScript` IT WAS. Ruling 4
# (2026-09-16 evening) moved the kit out of the store into a git-tracked file
# read at runtime (home/dot_config/tally/kit.json, rendered by
# tools/render-tally-kit.py). A git-tracked argv may not be a hashed store path:
# it would go stale the moment this derivation rebuilt, and refreshing it would
# be exactly the switch ruling 4 removed. So the kit names the STABLE per-user
# profile path /etc/profiles/per-user/tom/bin/tally-local-smoke, and for that
# path to exist the thing must be a package in `home.packages` — which means a
# `$out/bin/<name>`, which `writeShellScript` (a bare file) does not produce and
# `writeShellApplication` does. The bytes are unchanged; only the shape is.
#
# `runtimeInputs` IS DELIBERATELY EMPTY and every program is named by its store
# path in the text below. The kernel runs the argv with env_clear and an EMPTY
# env_allowlist (exec.rs:681-687): the child sees the two TALLY_ variables and
# NOTHING else — no PATH at all. A `runtimeInputs` list would make
# writeShellApplication emit `export PATH="…:$PATH"`, which under the
# `set -o nounset` it also emits is a reference to an unset variable. Absolute
# store paths need no PATH and cannot be shadowed, which is what the FT-3
# probe's clause K4 runs under `env -i`.
writeShellApplication {
  name = "tally-local-smoke";
  runtimeInputs = [ ];
  text = ''
    ${coreutils}/bin/mkdir -p "$(${coreutils}/bin/dirname "$TALLY_USAGE_SOURCE_PATH")"
    printf '{"kind":"tally-usage/1","execution_id":"%s","argv_ref":"build:LOCAL-SMOKE","tokens":{"out":0},"ok":true}\n' \
      "$TALLY_EXECUTION_ID" > "$TALLY_USAGE_SOURCE_PATH"
    exit 0
  '';
}
