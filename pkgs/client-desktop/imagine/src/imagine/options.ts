// Forked from Manganese 67c29a9906905bd5e1679803232c2f510b3fed9e, MIT; see LICENSE.
import { defineOptions, option } from "@domicile-desktop/sdk/options";

/** Every half hour of the day, as `HH:MM`, for the night light's hours. */
const HALF_HOURS = Array.from(
  { length: 48 },
  (_, index) =>
    `${String(Math.floor(index / 2)).padStart(2, "0")}:${index % 2 === 0 ? "00" : "30"}`,
);

/**
 * Imagine's options, set under `shell_options` in the config or on the
 * Settings app's Shell page. See `docs/WRITING-A-SHELL.md#options`.
 */
export const options = defineOptions({
  brightness: {
    automatic: option.toggle("Adjust brightness automatically", true),
  },
  clock: {
    format: option.choice("Clock format", ["24h", "12h"], "24h"),
    seconds: option.toggle("Show seconds", true),
  },
  // A face installed on the computer, by name. Inter ships with manganese.
  font: option.text("Font", "Inter"),
  keymap: {
    hideDefault: option.toggle("Hide the keymap on the first one", false),
  },
  nightLight: {
    // A custom schedule's hours, and sunset to sunrise's where the sun
    // neither rises nor sets.
    from: option.choice("Custom start", HALF_HOURS, "22:00"),
    // Sunset in the time zone's principal city.
    schedule: option.choice(
      "Schedule",
      ["sunset to sunrise", "custom", "off"],
      "sunset to sunrise",
    ),
    to: option.choice("Custom end", HALF_HOURS, "07:00"),
    warmth: option.number("Warmth (0 to 100)", 50, { max: 100, min: 0 }),
  },
});
