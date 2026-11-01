{
  callPackage,
  llm-agents,
  # The flake's herdr (inputs.herdr, the one home/herdr.nix installs).
  herdr,
}:
# The dsh plugins selected for hand-run profiles (pkgs/dsh, T-31/#676). Each is a
# plain package directory with a `dsh.bundle` manifest; the dsh wrapper links
# them into $DSH_HOME/profiles/<name>/node_modules and lists them in that
# profile's bundles. None is ever mounted in the stock headless profile that
# substrate drives. checks.dsh-plugins and checks.dsh-mnemon boot the profiles.
let
  # The dsh-tools of the dsh this fleet runs. The plugins import it as a peer
  # at runtime; dsh-herdr's tests import it at build time.
  dshTools = "${llm-agents.dsh}/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-tools";
  dshModules = "${llm-agents.dsh}/lib/node_modules/@deepseek-ai/dsh/node_modules";
in
{
  # wenhao4126/dsh-herdr behind ./dsh-herdr/tom.patch.
  dsh-herdr = callPackage ./dsh-herdr { inherit dshTools herdr; };
  # Owned here: the gate dsh-herdr cannot load without.
  herdr-guard = callPackage ./herdr-guard { };
  # PerryLink/jevcore's dsh plugin, offline (mock provider, no SDK).
  jevcore = callPackage ./jevcore { };
  # Owned here: prints the plugins' ctx.logger lines (jevcore's ready line,
  # warnings) to stderr, which dsh itself never does.
  stderr-log = callPackage ./stderr-log { };
  # Mnemon's published JS plus its pinned runtime dependency closure.
  mnemon = callPackage ./mnemon { inherit dshModules; };
}
