import type { Displays } from "@domicile-desktop/sdk/desktop/displays";

/** The stable engine restores its global whitepoint on hotplug and modesets. */
export const maintainDisplayTemperature = (
  displays: Pick<Displays, "setColorTemperature">,
  kelvin: number,
  report: (error: unknown) => void,
): (() => void) => {
  let active = true;
  const failed = (error: unknown): void => { if (active) report(error); };
  // This engine's public API is global. Do not pass an ignored output name:
  // multiple per-output calls would overwrite the same native whitepoint.
  displays.setColorTemperature(kelvin)
    .then((result) => result.match({ Ok: () => undefined, Err: failed }))
    .catch(failed);
  return () => { active = false; };
};
