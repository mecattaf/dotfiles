import type { Displays } from "@domicile-desktop/sdk/desktop/displays";

/** Fixed white temperatures, keyed by Domicile's public display name. */
export type DisplayTemperatures = Readonly<Record<string, number>>;

/** Apply device policy through Domicile; it owns gamma, resume and modesets. */
export const maintainDisplayTemperatures = (
  displays: Pick<Displays, "list" | "on" | "setColorTemperature">,
  temperatures: DisplayTemperatures,
  report: (error: unknown) => void,
): (() => void) => {
  // Domicile retains each output's requested ramp and restores it after
  // modesets/resume. Display reports can arrive in bursts while docking;
  // submit a policy once per connected output, including while it is pending.
  const applied = new Map<string, { kelvin: number }>();
  let active = true;
  const apply = (): void => {
    if (!active) return;
    const connected = displays.list;
    if (connected === undefined) return;
    const names = new Set(connected.map((display) => display.name));
    for (const name of applied.keys()) {
      if (!names.has(name)) applied.delete(name);
    }
    for (const display of connected) {
      const kelvin = temperatures[display.name];
      if (kelvin === undefined || applied.get(display.name)?.kelvin === kelvin) {
        continue;
      }
      const request = { kelvin };
      applied.set(display.name, request);
      const failed = (error: unknown): void => {
        // A late failure from an unplugged output must not clear a newer
        // request for that output after it returns.
        if (applied.get(display.name) === request) applied.delete(display.name);
        if (active) report(error);
      };
      displays.setColorTemperature(kelvin, display.name)
        .then((result) => result.match({ Ok: () => undefined, Err: failed }))
        .catch(failed);
    }
  };
  const stop = displays.on("change", apply);
  apply();
  return () => {
    active = false;
    applied.clear();
    stop();
  };
};
