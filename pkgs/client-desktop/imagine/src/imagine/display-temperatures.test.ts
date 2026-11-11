import { expect, test } from "bun:test";
import { maintainDisplayTemperature } from "./display-temperatures";

test("one global whitepoint covers laptop and docked outputs without ignored targets", () => {
  const calls: unknown[][] = [];
  const displays = {
    setColorTemperature: async (...args: number[]) => {
      calls.push(args);
      return { match: ({ Ok }: { Ok: () => void }) => Ok() };
    },
  };
  maintainDisplayTemperature(displays, 3850, () => {});
  expect(calls).toEqual([[3850]]);
});

test("transport failure is surfaced", async () => {
  const errors: unknown[] = [];
  const failure = new Error("desktop connection closed");
  maintainDisplayTemperature({
    setColorTemperature: async () => { throw failure; },
  }, 3850, (error) => errors.push(error));
  await Bun.sleep(0);
  expect(errors).toEqual([failure]);
});

test("a refused native whitepoint request is surfaced", async () => {
  const errors: unknown[] = [];
  const failure = { code: "unavailable", message: "gamma is unavailable" };
  maintainDisplayTemperature({
    setColorTemperature: async () => ({
      match: ({ Err }: { Err: (error: unknown) => void }) => Err(failure),
    }),
  }, 3850, (error) => errors.push(error));
  await Bun.sleep(0);
  expect(errors).toEqual([failure]);
});

test("an unmounted shell does not report a late transport failure", async () => {
  const errors: unknown[] = [];
  let refuse!: (error: Error) => void;
  const stop = maintainDisplayTemperature({
    setColorTemperature: () => new Promise((_resolve, reject) => { refuse = reject; }),
  }, 3850, (error) => errors.push(error));
  stop();
  refuse(new Error("old shell closed"));
  await Bun.sleep(0);
  expect(errors).toEqual([]);
});
