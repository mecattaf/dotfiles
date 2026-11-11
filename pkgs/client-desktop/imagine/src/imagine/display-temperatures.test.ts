import { expect, test } from "bun:test";
import { maintainDisplayTemperatures } from "./display-temperatures";

const fixture = (names: string[] | undefined) => {
  const calls: [number, string | undefined][] = [];
  const errors: unknown[] = [];
  let changed = () => {};
  let stopped = false;
  const displays = {
    list: names?.map((name) => ({ name })),
    on: (_event: string, callback: () => void) => {
      changed = callback;
      return () => { stopped = true; };
    },
    setColorTemperature: async (kelvin: number, display?: string) => {
      calls.push([kelvin, display]);
      return { match: ({ Ok }: { Ok: () => void }) => Ok() };
    },
  };
  return { displays, calls, errors, changed: () => changed(), stopped: () => stopped };
};

test("Duo temperatures target their own outputs and leave other outputs alone", () => {
  const f = fixture(["upper", "lower", "external"]);
  maintainDisplayTemperatures(f.displays, { upper: 3850, lower: 3350 }, (e) => f.errors.push(e));
  expect(f.calls).toEqual([[3850, "upper"], [3350, "lower"]]);
});

test("wait for the display report, then restore the lower panel after undocking", () => {
  const f = fixture(undefined);
  maintainDisplayTemperatures(f.displays, { upper: 3850, lower: 3350 }, (e) => f.errors.push(e));
  expect(f.calls).toEqual([]);
  f.displays.list = [{ name: "upper" }];
  f.changed();
  f.displays.list.push({ name: "lower" });
  f.changed();
  expect(f.calls).toEqual([[3850, "upper"], [3850, "upper"], [3350, "lower"]]);
});

test("unmount removes the display subscription", () => {
  const f = fixture(["upper"]);
  const stop = maintainDisplayTemperatures(f.displays, { upper: 3850 }, (e) => f.errors.push(e));
  stop();
  expect(f.stopped()).toBe(true);
});

test("transport failure is surfaced", async () => {
  const f = fixture(["upper"]);
  const failure = new Error("desktop connection closed");
  f.displays.setColorTemperature = async () => { throw failure; };
  maintainDisplayTemperatures(f.displays, { upper: 3850 }, (e) => f.errors.push(e));
  await Bun.sleep(0);
  expect(f.errors).toEqual([failure]);
});

test("a refused native temperature request is surfaced", async () => {
  const errors: unknown[] = [];
  const failure = { code: "unavailable", message: "gamma is unavailable" };
  const displays = {
    list: [{ name: "upper" }],
    on: () => () => {},
    setColorTemperature: async () => ({
      match: ({ Err }: { Err: (error: unknown) => void }) => Err(failure),
    }),
  };
  maintainDisplayTemperatures(displays, { upper: 3850 }, (error) => errors.push(error));
  await Bun.sleep(0);
  expect(errors).toEqual([failure]);
});
