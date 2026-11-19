{
  inputs,
  lib,
  ...
}:
# kitty-persist — persistent native Kitty terminals (flake input
# `kitty-persist`). The input provides one program, `kitty-persist`, and two
# modules:
#
#   homeManagerModules.laptop     (here, per user) programs.kitty-persist:
#       the program on PATH, the product's Kitty lines (the text of
#       `kitty-persist kitty-conf`) as a file, and kitty-persist.conf.
#   nixosModules.remote-host      (hosts/nas, whole host) services.kitty-persist:
#       the program on every user's ssh PATH, the resume unit, lingering.
#
# The laptop module is imported for every host and OFF; a host that shows
# persistent windows turns it on in its own file (hosts/client), the way
# agencyKitty is gated per host. Off, it writes nothing.
#
# KITTY LINES. ~/.config/kitty is a whole-directory raw link, so nothing
# generated can live inside it (the same constraint as
# kitty-scrollback-nix.conf and agency-kitty/kitty.conf). The module's default
# path (kitty/kitty-persist.conf) is therefore moved to the neutral
# ~/.config/kitty-persist/kitty.conf, which the raw kitty.conf includes; Kitty
# ignores that include on a host where the module is off. The file is the
# package's own share/kitty-persist/kitty-persist.conf, unedited: key mappings
# and comments only, every mapping limited to windows that carry the
# persist_id user variable. The personal lines (the program-status tab title
# and the same-directory key) are in the raw kitty.conf, after the include.
#
# KITTY-PERSIST.CONF (~/.config/kitty-persist/kitty-persist.conf, read on the
# laptop): the default remote host is the fleet's ssh name for the brain host
# (modules/fleet-hosts.nix), the microphone is forwarded (forward_audio), and
# each host whose block in
# home/dot_config/kitty/ssh.conf sets `login_shell fish` gets the same line,
# because the account shell is bash fleet-wide (modules/common.nix).
#
# DICTATION (O6 of the kitty-persist integration). No dictation tool exists in
# this tree (removed 2026-09-30; the flake asserts its absence) and none is
# added here. The call a dictation tool started outside Kitty makes is:
#
#   printf %s "$text" | kitty-persist paste-text --focused --to unix:@kitty-<pid>
#
# where <pid> is the Kitty instance that has OS focus: kitty.conf has
# `listen_on unix:@kitty-{kitty_pid}`, one socket per Kitty process, and the
# tool's environment carries no KITTY_LISTEN_ON. The text arrives in the
# focused persistent window unsent (no Enter). Without --to the command stops
# with exit code 78. tests/kitty-persist-kitty exercises that call with a
# stand-in for the tool.
{
  imports = [ inputs.kitty-persist.homeManagerModules.laptop ];

  programs.kitty-persist = {
    kittyLines = {
      file = lib.mkDefault "kitty-persist/kitty.conf";
      # kitty.conf is a raw file, not written by Home Manager: the include
      # line is in home/dot_config/kitty/kitty.conf.
      include = false;
    };
    settings = {
      host = lib.mkDefault "nas";
      # The laptop's microphone reaches an agent in a session that records
      # (Claude Code's voice mode on the brain host, which has the ALSA pulse
      # plugin compiled in: hosts/nas). Read when a session is created and at
      # each attach; the product's default is off.
      forward_audio = lib.mkDefault true;
    };
    hosts = {
      nas.login_shell = lib.mkDefault "fish";
      strix.login_shell = lib.mkDefault "fish";
    };
  };
}
