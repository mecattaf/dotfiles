// Immutable recovery shell, independent of the user's startup config.
// Loading this replaces only the shell; upstream keeps the desktop's windows.
import { runManganese } from "@domicile-desktop/manganese";
import {
  DEFAULT_KEYBINDINGS,
  exec,
} from "@domicile-desktop/manganese-window-management/keyboard/commands";
import { ownedChords } from "@domicile-desktop/sdk/own-keybindings";

const { "Meta+Shift+Return": _lock, ...kept } = DEFAULT_KEYBINDINGS;
const keybindings = {
  ...kept,
  "Meta+Shift+Return": exec("kitty", "-e", "fish"),
};
ownedChords({ keybindings });
export const Shell = runManganese({ keybindings: { keybindings } });
