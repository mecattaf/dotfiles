{ pkgs, ... }:

let
  cliAnything = pkgs.cli-anything-hub;
  resources = "${cliAnything}/share/cli-anything";
in
{
  # cli-hub is built from a pinned upstream tree. Harnesses selected later by
  # `cli-hub install` are isolated with the already-declared uv tool manager;
  # the Nix-packaged interpreter is never mutated with pip.
  environment.systemPackages = [ cliAnything ];

  # cli-hub's own package is pure Nix. Its optional, user-selected harnesses
  # remain uv-managed by design, so give those environments the normal NixOS
  # compatibility seam for uv's prebuilt Python interpreters and native wheels.
  environment.localBinInPath = true;
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc.lib
      zlib
      openssl
      libffi
      glibc
    ];
  };

  # Upstream ships separate integrations for the three fleet agents. Link each
  # immutable store tree into its native discovery path, keeping agent-owned
  # settings and credentials writable alongside it.
  home-manager.users.tom.home.file = {
    ".codex/skills/cli-anything".source = "${resources}/codex-skill";
    ".codex/skills/cli-hub-meta-skill".source = "${resources}/cli-hub-meta-skill";
    ".claude/plugins/cli-anything".source = "${resources}/claude-plugin";
    ".pi/agent/extensions/cli-anything".source = "${resources}/pi-extension";
  };
}
