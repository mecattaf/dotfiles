{
  lib,
  writeShellApplication,
  bash,
  coreutils,
  curl,
  findutils,
  git,
  gnugrep,
  gnused,
  jq,
  python3,
  util-linux,
  pi,
}:
# cubs-iteration — ONE bounded Halogen coding iteration on the CUBS tree, the
# argv of every `build:CUBS-<n>` kit entry in home/tally-uplink.nix.
#
# Campaign cubs-halogen-probe-1 (FRONT-12 bootstrap). What it does, the receipt
# it writes, its exit codes and the two operator acts it waits on are in
# docs/local-ai/cubs-campaign.md; the script's own header is the short form.
#
# WHY A writeShellApplication AND NOT A writeShellScript LIKE tally-local-smoke.
# The kernel runs the argv with env_clear and no PATH (tally
# crates/tally-kernel/src/exec.rs:681-689), so every program the script names
# must be a store path it carries. `runtimeInputs` is exactly that carriage,
# and the derivation's shellcheck pass is the cheapest oracle a 600-line
# lease script can have. `inheritPath` stays true: the inherited PATH under
# the kernel is /bin/sh's `/no-such-path` (MEASURED), harmless, and the script
# itself appends the two profile bins LAST so a task's validation_cmd can
# reach `nix develop` — home/tally-filler.nix's reasoning, not a second nix.
#
# `pi` IS THE STORE PACKAGE, NOT home/pi.nix's WRAPPER. The wrapper's whole
# work is to prepend the `-e` roster to interactive runs, and the roster is
# EMPTY (home/pi.nix `extensions = { }`; MEASURED: the installed wrapper execs
# the store `pi` with no flags). This script runs Pi with `--no-extensions`
# and a campaign-private PI_CODING_AGENT_DIR (the judge.sh precedent), so
# the wrapper would add nothing and the kit carries the package the wrapper
# wraps: `pkgs.llm-agents.pi`, the same derivation home/pi.nix names.
#
# python3 carries no packages: cubs-helpers.py is stdlib only (json, re).
writeShellApplication {
  name = "cubs-iteration";
  runtimeInputs = [
    bash
    coreutils
    curl
    findutils
    git
    gnugrep
    gnused
    jq
    python3
    util-linux # flock
    pi
  ];
  runtimeEnv = {
    CUBS_HELPERS = "${./cubs-helpers.py}";
  };
  # SC2016: the script's jq filters are single-quoted strings full of `$var`
  # jq bindings, which is jq's own syntax and not a shell expansion mistake.
  excludeShellChecks = [ "SC2016" ];
  text = builtins.readFile ./cubs-iteration.sh;
  meta = {
    description = "one bounded Halogen coding iteration on the CUBS tree under a tally lease (cubs-halogen-probe-1)";
    mainProgram = "cubs-iteration";
    platforms = lib.platforms.linux;
  };
}
