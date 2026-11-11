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

test("laptop and external temperatures target their own outputs", () => {
  const f = fixture(["upper", "lower", "external", "unconfigured"]);
  maintainDisplayTemperatures(f.displays, { upper: 3850, lower: 3350, external: 3850 }, (e) => f.errors.push(e));
  expect(f.calls).toEqual([[3850, "upper"], [3350, "lower"], [3850, "external"]]);
});

test("wait for the display report, then restore the lower panel after undocking", () => {
  const f = fixture(undefined);
  maintainDisplayTemperatures(f.displays, { upper: 3850, lower: 3350 }, (e) => f.errors.push(e));
  expect(f.calls).toEqual([]);
  f.displays.list = [{ name: "upper" }];
  f.changed();
  f.displays.list.push({ name: "lower" });
  f.changed();
  expect(f.calls).toEqual([[3850, "upper"], [3350, "lower"]]);
});

test("hotplug bursts do not repeatedly submit temperatures for retained outputs", async () => {
  const f = fixture(["upper", "lower"]);
  maintainDisplayTemperatures(f.displays, { upper: 3850, lower: 3350, external: 3850 }, (e) => f.errors.push(e));
  for (let i = 0; i < 100; i++) f.changed();
  await Bun.sleep(0);
  f.displays.list!.push({ name: "external" });
  for (let i = 0; i < 100; i++) f.changed();
  expect(f.calls).toEqual([[3850, "upper"], [3350, "lower"], [3850, "external"]]);
});

test("undocking then redocking reapplies a returning output with the same name", () => {
  const f = fixture(["upper", "external"]);
  maintainDisplayTemperatures(f.displays, { upper: 3850, external: 3850 }, (e) => f.errors.push(e));
  f.displays.list = [{ name: "upper" }];
  f.changed();
  f.displays.list.push({ name: "external" });
  f.changed();
  expect(f.calls).toEqual([[3850, "upper"], [3850, "external"], [3850, "external"]]);
});

test("unmount removes the display subscription", () => {
  const f = fixture(["upper"]);
  const stop = maintainDisplayTemperatures(f.displays, { upper: 3850 }, (e) => f.errors.push(e));
  stop();
  expect(f.stopped()).toBe(true);
  f.displays.list!.push({ name: "lower" });
  f.changed();
  expect(f.calls).toEqual([[3850, "upper"]]);
});

test("transport failure is surfaced", async () => {
  const f = fixture(["upper"]);
  const failure = new Error("desktop connection closed");
  f.displays.setColorTemperature = async () => { throw failure; };
  maintainDisplayTemperatures(f.displays, { upper: 3850 }, (e) => f.errors.push(e));
  await Bun.sleep(0);
  expect(f.errors).toEqual([failure]);
});

test("a failed request can retry on the next display report", async () => {
  const f = fixture(["upper"]);
  const failure = new Error("desktop reconnecting");
  const send = f.displays.setColorTemperature;
  f.displays.setColorTemperature = async () => { throw failure; };
  maintainDisplayTemperatures(f.displays, { upper: 3850 }, (e) => f.errors.push(e));
  await Bun.sleep(0);
  f.displays.setColorTemperature = send;
  f.changed();
  expect(f.errors).toEqual([failure]);
  expect(f.calls).toEqual([[3850, "upper"]]);
});

test("a late failed request does not evict a redocked output's newer request", async () => {
  const f = fixture(["external"]);
  let refuse!: (error: Error) => void;
  let pending = true;
  const send = f.displays.setColorTemperature;
  f.displays.setColorTemperature = (kelvin, name) => {
    if (pending) {
      pending = false;
      return new Promise((_resolve, reject) => { refuse = reject; });
    }
    return send(kelvin, name);
  };
  maintainDisplayTemperatures(f.displays, { external: 3850 }, (e) => f.errors.push(e));
  f.displays.list = [];
  f.changed();
  f.displays.list = [{ name: "external" }];
  f.changed();
  refuse(new Error("old output disconnected"));
  await Bun.sleep(0);
  f.changed();
  expect(f.calls).toEqual([[3850, "external"]]);
  expect(f.errors).toHaveLength(1);
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
