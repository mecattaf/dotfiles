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

// Lock leaves the table here, so deleting the rescue line below leaves the chord
// unbound and does not bring Lock back.
const { "Meta+Shift+Return": _lock, ...kept } = DEFAULT_KEYBINDINGS;

// Each desktop entry point has one name for keys, the launcher, and recovery.
// The terminal starts at a local control shell before an explicit NAS attach.
const keybindings = {
  ...kept,
  "Meta+Return": exec("domicile-apps", "terminal"),
  // A local shell that needs neither NAS nor Herdr. This chord never locks.
  "Meta+Shift+Return": exec("domicile-apps", "rescue"),
};

// Keep this line. The shell only checks chords when it draws, so a chord written
// two ways passes the build and replaces the whole desk with an error page with
// no keys. Checked here, the edit is refused and the desk stays as it was.
ownedChords({ keybindings });

export const Shell = runManganese({ keybindings: { keybindings } });
