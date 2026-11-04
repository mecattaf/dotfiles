// The key table for the first Domicile desk: stock Manganese with two chords
// changed, item per item from here on. Built through
// programs.domicile.configDirectory (modules/domicile.nix). Set neither
// programs.domicile.shell nor programs.domicile.settings.shell: either one
// beats the Shell built from this file, and the desk runs without this table.
//
// Nothing imports `ms`. The Home Manager build copies "$bunDeps/share/bun-cache",
// and a bun.nix with no package makes no such directory. bun.lock comes from
// bun 1.3.13, the one in Domicile's locked nixpkgs: bun 1.4.4 writes lockfile
// version 2, which bun2nix 2.1.2 refuses. bun.nix comes from that bun2nix.

import { runManganese } from "@domicile-desktop/manganese";
import {
  DEFAULT_KEYBINDINGS,
  exec,
} from "@domicile-desktop/manganese-window-management/keyboard/commands";

// Lock leaves the table here, so deleting the fish line below leaves the chord
// unbound and does not bring Lock back.
const { "Meta+Shift+Return": _lock, ...kept } = DEFAULT_KEYBINDINGS;

// What herdr-picker asks Sway to run, without the picker, which stops when
// SWAYSOCK is unset. `exec` takes an argv with no shell, and `~` needs one.
const projector =
  "exec env HERDR_PROJECTOR_TARGET=nas HERDR_PICKER_HOSTNAME=nas HERDR_SWAY_LOCAL=0 kitty --class herdr-projector -e ~/.local/bin/herdr-sway-projector";

export const Shell = runManganese({
  keybindings: {
    keybindings: {
      ...kept,
      // Kitty > Herdr to nas, as dot_config/sway/binds.conf reaches it.
      "Meta+Return": exec("sh", "-c", projector),
      // A local shell, as binds.conf has it. Needs no nas and no Herdr.
      "Meta+Shift+Return": exec("kitty", "-e", "fish"),
    },
  },
});
