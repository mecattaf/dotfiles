{
  callPackage,
  llm-agents,
}:
# The dsh plugins selected for the hand-run profiles mnemon, zen and native
# (pkgs/dsh, T-31/#676). Each is a plain package directory with a `dsh.bundle`
# manifest; the dsh wrapper links them into $DSH_HOME/profiles/<name>/node_modules
# and lists them in that profile's bundles. None is ever mounted in the stock headless profile that
# substrate drives. checks.dsh-plugins, checks.dsh-mnemon and checks.dsh-zen
# boot the profiles.
let
  dshModules = "${llm-agents.dsh}/lib/node_modules/@deepseek-ai/dsh/node_modules";
in
{
  # Owned native terminal catalogue, no input or process-allocation authority.
  kitty-native = callPackage ../agency-kitty/source/integration/dsh { };
  # PerryLink/jevcore's dsh plugin, offline (mock provider, no SDK). Selected
  # by no profile since the hand-run `herdr` profile left with Herdr v1;
  # checks.dsh-plugins still pins its build.
  jevcore = callPackage ./jevcore { };
  # Owned here: prints the plugins' ctx.logger lines (jevcore's ready line,
  # warnings) to stderr, which dsh itself never does.
  stderr-log = callPackage ./stderr-log { };
  # Mnemon's published JS plus its pinned runtime dependency closure.
  mnemon = callPackage ./mnemon { inherit dshModules; };
  # jiesou's OpenCode Zen free-model provider, committed lib/ as published.
  # Only the hand-run `zen` profile mounts it (Tom, 2026-11-03).
  opencode-zen-free = callPackage ./opencode-zen-free { };
}
