// Agency's client-side Domicile configuration. The config and local shell are
// checked together; the upstream settings module cannot add a second config.
import type { ThemeConfig } from "@domicile-desktop/sdk/config";
import { KeyAction } from "@domicile-desktop/sdk/key-action";
import { runImagine } from "./imagine/src/index";
import {
  DEFAULT_KEYBINDINGS,
  clearNotifications,
  clipboard,
  exec,
  floating,
  focus,
  fullscreen,
  layout,
  move,
  split,
  volume,
} from "@domicile-desktop/manganese-window-management/keyboard/commands";
import { ownedChords } from "@domicile-desktop/sdk/own-keybindings";

const upperPanel = "drm-21536134253248512";
const lowerPanel = "drm-21536134253248513";
const external5k = "drm-1886053529622275";
// Tom prefers 2x on the PA27JCV too: slightly larger physical text is welcome.
const external5kScale = 2;
const agency = (...args: string[]) => KeyAction.SendShell(["agency", ...args]);

// Reserve the chords owned by the client shell below.
const kept = Object.fromEntries(
  Object.entries(DEFAULT_KEYBINDINGS).filter(([chord]) => ![
    "Meta+Shift+Return", "Meta+w", "Meta+s", "Meta+minus",
    "Meta+Up", "Meta+Down", "Meta+Shift+Up", "Meta+Shift+Down",
  ].includes(chord)),
);
const keybindings = {
  ...kept,
  "Meta+Return": exec("domicile-apps", "terminal"),
  "Alt+space": agency("ambient-chat", "toggle"),
  "Meta+Shift+Return": exec("domicile-apps", "rescue"),
  "Control+n": exec("domicile-apps", "chrome"),
  "Control+Shift+n": exec("domicile-apps", "chrome", "--incognito"),
  "Meta+n": exec("domicile-apps", "chrome"),
  "Meta+Control+n": exec("domicile-apps", "chrome", "--incognito"),
  "Meta+e": exec("domicile-apps", "files"),
  // Jump directly between outputs, even with several windows on this one.
  "Meta+j": agency("output", "down"),
  "Meta+k": agency("output", "up"),
  "Meta+v": clipboard(),
  "Meta+Control+v": split("v"),
  "Meta+Tab": floating(),
  "Meta+Shift+Tab": focus("mode_toggle"),
  "Meta+Control+t": layout("tabbed"),
  "Meta+Control+Shift+s": layout("stacking"),
  "Meta+Control+e": layout("toggle split"),
  "Meta+equal": fullscreen(),
  "Meta+bracketleft": move("left"),
  "Meta+bracketright": move("right"),
  "Meta+o": clearNotifications(),
  // Glove80 volume keys use the shell's audio controls and integrated OSD.
  F6: volume("mute"),
  F7: volume("down"),
  F8: volume("up"),
  // Agency controls both DRM panels and the OSD directly through Domicile.
  F1: agency("brightness", "down"),
  F2: agency("brightness", "up"),
  "Shift+F2": agency("brightness", "max"),
  F10: agency("brightness", "toggle"),
  XF86MonBrightnessDown: agency("brightness", "down"),
  XF86MonBrightnessUp: agency("brightness", "up"),
  "Shift+XF86MonBrightnessDown": agency("brightness", "down", "fine"),
  "Shift+XF86MonBrightnessUp": agency("brightness", "up", "fine"),
  F3: agency("media", "play-pause"),
  F4: agency("media", "previous"),
  F5: agency("media", "next"),
  XF86AudioPlay: agency("media", "play-pause"),
  XF86AudioPrev: agency("media", "previous"),
  XF86AudioNext: agency("media", "next"),
};
// Normalized duplicate chords must fail before replacing the running shell.
ownedChords({ keybindings });

const imagineShell = runImagine({
  // Duo / DuoDocked panel temperatures, through Domicile's display API.
  displayTemperatures: { [upperPanel]: 3850, [lowerPanel]: 3350, [external5k]: 3850 },
  ambientChat: { launcher: "agency-chat-ambient-bootstrap" },
  chatWindow: { launcher: "agency-chat-window", bindAltEnter: true },
  sessionCatalogue: { relay: "agency-chat-catalogue", server: "agency-web", terminalLauncher: "agency-chat-terminal" },
  layoutPersistence: { identity: "agency-layout-identity", restartRecovery: true },
  webBrowser: { command: ["domicile-apps", "chrome"] },
  policy: {
    upperDisplay: upperPanel,
    lowerDisplay: lowerPanel,
    workspaceDisplays: { "6": external5k, "7": external5k, "8": external5k, "9": external5k },
  },
  keybindings: { keybindings },

});

// Per-display policy above replaces the global scheduled night light.
export const Shell = imagineShell;
export const shell_options = {
  nightLight: { schedule: "off" },
  brightness: { automatic: false },
  font: "Anthropic Sans",
};

// Match the seat's cursor, icons and fonts, with a neutral shared accent.
export const theme: ThemeConfig = {
  mode: "dark",
  accent_color: "#555451",
  icon_theme: "MacTahoe-dark",
  cursor_theme: "Bibata-Modern-Classic",
  cursor_size: 48,
  font_name: "Anthropic Sans 11",
  monospace_font_name: "AnthropicMono Nerd Font 11",
};

// More specific external-monitor profiles precede the laptop-only fallbacks.
// Keep the Duo's original 2x scale and vertical stack on monitor hotplug.
// The PA27JCV sits to the right of the upper panel, with their tops aligned.
export const output = {
  profiles: [
    {
      name: "Duo5k",
      displays: [
        { display: upperPanel, mode: [2880, 1800], scale: 2, position: [0, 0] },
        { display: lowerPanel, mode: [2880, 1800], scale: 2, position: [0, 900] },
        { display: external5k, mode: [5120, 2880], scale: external5kScale, position: [1440, 0] },
      ],
    },
    {
      name: "DuoDocked5k",
      displays: [
        { display: upperPanel, mode: [2880, 1800], scale: 2, position: [0, 0] },
        { display: external5k, mode: [5120, 2880], scale: external5kScale, position: [1440, 0] },
      ],
    },
    {
      name: "Duo",
      displays: [
        { display: upperPanel, scale: 2, position: [0, 0] },
        { display: lowerPanel, scale: 2, position: [0, 900] },
      ],
    },
    {
      name: "DuoDocked",
      displays: [{ display: upperPanel, scale: 2, position: [0, 0] }],
    },
  ],
};
export const input = {
  // Keep the quick held-key response in native clients and browser pages.
  keyboard: { repeat: { delay_ms: 200, rate: 25 } },
  "touchpad": {
    "tap": true,
    "tap_button_map": "lrm",
    "tap_drag": true,
    "drag_lock": false,
    "natural_scroll": true,
    "accel_profile": "adaptive",
    "speed": 0,
    "click_method": "clickfinger",
    "middle_emulation": false,
    "scroll_method": "two_finger",
    "scroll_factor": 1,
    "scroll_acceleration": false,
    "disable_while_typing": "libinput",
    "typing_pause_ms": 200,
    "typing_repeat_pause_ms": 500
  },
  "mouse": {
    "accel_profile": "flat",
    "speed": 0,
    "natural_scroll": false,
    "middle_emulation": false,
    "scroll_factor": 1
  },
  pointers: [
    { device: "ELAN9008:00 04F3:425B", display: upperPanel },
    { device: "ELAN9008:00 04F3:425B Stylus", display: upperPanel },
    { device: "ELAN9009:00 04F3:425A", display: lowerPanel },
    { device: "ELAN9009:00 04F3:425A Stylus", display: lowerPanel },
  ],
};

// Upstream runs these once per compositor, not on shell reload or engine rejoin.
// The terminal connects directly to the NAS Herdr server.
export const startup = {
  commands: [
    ["domicile-apps", "chrome"],
    ["domicile-apps", "terminal"],
    ["domicile-apps", "files"],
  ],
};
