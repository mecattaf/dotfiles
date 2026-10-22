{
  callPackage,
  llm-agents,
}:
# The dsh plugins of the hand-run `herdr` profile (pkgs/dsh, T-31). Each is a
# plain package directory with a `dsh.bundle` manifest; the dsh wrapper links
# them into $DSH_HOME/profiles/herdr/node_modules and lists them in that
# profile's bundles. None is ever mounted in the stock headless profile that
# substrate drives. checks.dsh-plugins (flake.nix) boots the profile.
let
  # The dsh-tools of the dsh this fleet runs. The plugins import it as a peer
  # at runtime; dsh-herdr's tests import it at build time.
  dshTools = "${llm-agents.dsh}/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-tools";
in
{
  # wenhao4126/dsh-herdr behind ./dsh-herdr/tom.patch.
  dsh-herdr = callPackage ./dsh-herdr { inherit dshTools; };
  # Owned here: the gate dsh-herdr cannot load without.
  herdr-guard = callPackage ./herdr-guard { };
  # PerryLink/jevcore's dsh plugin, offline (mock provider, no SDK).
  jevcore = callPackage ./jevcore { };
}
