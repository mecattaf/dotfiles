// Starter Domicile desk. Kept as one checked TSX config: Home Manager's
// upstream settings module stays off so it cannot add a second JSON config.
import { runManganese } from "@domicile-desktop/manganese";
import {
  DEFAULT_KEYBINDINGS,
  exec,
} from "@domicile-desktop/manganese-window-management/keyboard/commands";
import { ownedChords } from "@domicile-desktop/sdk/own-keybindings";

// Removing the rescue binding later must not restore the stock lock action.
const { "Meta+Shift+Return": _lock, ...kept } = DEFAULT_KEYBINDINGS;
const keybindings = {
  ...kept,
  "Meta+Return": exec("domicile-apps", "terminal"),
  "Meta+Shift+Return": exec("domicile-apps", "rescue"),
  // Keep the stock Meta+b split and Meta+e layout actions.
  "Meta+Control+b": exec("domicile-apps", "chrome"),
  "Meta+Control+e": exec("domicile-apps", "files"),
};
// Normalized duplicate chords must fail before replacing the running shell.
ownedChords({ keybindings });

const manganese = runManganese({
  keybindings: { keybindings },
  applications: {
    // These inherited desktop entries invoke Sway IPC or its Mako service.
    // Omit them only in this launcher, preserving Sway's rescue environment.
    omit: [
      "herdr-picker.desktop",
      "sway-workspace-new.desktop",
      "sway-workspace-rename.desktop",
      "sway-workspace-restore.desktop",
      "notifications-dismiss.desktop",
      "notifications-history.desktop",
    ],
  },
});

// The pinned upstream night-light-override.ts owns this versioned storage key.
// Every starter shell load explicitly turns global night light off: the panel
// baselines below are the only tint. This does not change panel brightness.
export const Shell: typeof manganese = (root, domicile) => {
  globalThis.localStorage.setItem("night-light:v1", JSON.stringify({ on: false }));
  return manganese(root, domicile);
};
export const shell_options = { nightLight: { schedule: "off" } };

// Connector names, mode and placement match the reviewed Zenbook candidate.
// A packaged native engine with the matching white-point ABI is required;
// these values are not physical panel qualification on their own.
export const output = {
  profiles: [
    {
      name: "zenbook-two-panels",
      displays: [
        {
          display: "eDP-1",
          mode: [2880, 1800],
          position: [0, 0],
          scale: 2,
          color_temperature: 3850,
        },
        {
          display: "eDP-2",
          mode: [2880, 1800],
          position: [0, 900],
          scale: 2,
          color_temperature: 3350,
        },
      ],
    },
  ],
};
