import type { Displays } from "@domicile-desktop/sdk/desktop/displays";

/** Fixed white temperatures, keyed by Domicile's public display name. */
export type DisplayTemperatures = Readonly<Record<string, number>>;

/** Apply device policy through Domicile; it owns gamma, resume and modesets. */
export const maintainDisplayTemperatures = (
  displays: Pick<Displays, "list" | "on" | "setColorTemperature">,
  temperatures: DisplayTemperatures,
  report: (error: unknown) => void,
): (() => void) => {
  const apply = (): void => {
    for (const display of displays.list ?? []) {
      const kelvin = temperatures[display.name];
      if (kelvin === undefined) {
        continue;
      }
      displays.setColorTemperature(kelvin, display.name)
        .then((result) => result.match({ Ok: () => undefined, Err: report }))
        .catch(report);
    }
  };
  const stop = displays.on("change", apply);
  apply();
  return stop;
};
