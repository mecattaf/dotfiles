// The key table for the first Domicile desk: stock Manganese with two chords
// changed, item per item from here on. Domicile reads this file directly from
// ~/.config/domicile/domicile.tsx, and an edit reloads the running desk. Deployed
// as one file link by modules/domicile.nix, after a check at build time. Sections
// of the config go here too, as exports beside Shell.

import { runManganese } from "@domicile-desktop/manganese";
import {
  DEFAULT_KEYBINDINGS,
  exec,
} from "@domicile-desktop/manganese-window-management/keyboard/commands";
import { ownedChords } from "@domicile-desktop/sdk/own-keybindings";

// Lock leaves the table here, so deleting the fish line below leaves the chord
// unbound and does not bring Lock back.
const { "Meta+Shift+Return": _lock, ...kept } = DEFAULT_KEYBINDINGS;

// What herdr-picker asks Sway to run, without the picker, which stops when
// SWAYSOCK is unset. `exec` takes an argv with no shell, and `~` needs one.
const projector =
  "exec env HERDR_PROJECTOR_TARGET=nas HERDR_PICKER_HOSTNAME=nas HERDR_SWAY_LOCAL=0 kitty --class herdr-projector -e ~/.local/bin/herdr-sway-projector";

const keybindings = {
  ...kept,
  // Kitty > Herdr to nas, as dot_config/sway/binds.conf reaches it.
  "Meta+Return": exec("sh", "-c", projector),
  // A local shell, as binds.conf has it. Needs no nas and no Herdr.
  "Meta+Shift+Return": exec("kitty", "-e", "fish"),
};

// Keep this line. The shell only checks chords when it draws, so a chord written
// two ways passes the build and replaces the whole desk with an error page with
// no keys. Checked here, the edit is refused and the desk stays as it was.
ownedChords({ keybindings });

export const Shell = runManganese({ keybindings: { keybindings } });
