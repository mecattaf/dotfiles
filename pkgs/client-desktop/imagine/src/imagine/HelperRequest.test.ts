import { expect, test } from "bun:test";
import { runHelperRequest } from "./HelperRequest";
import type { Domicile } from "@domicile-desktop/sdk/desktop/desktop";
const ok = (value: unknown) => ({ match: ({ Ok }: { Ok: (x: unknown) => unknown }) => Ok(value) });
const closed = (value = "") => new ReadableStream<Uint8Array>({ start(c) { c.enqueue(new TextEncoder().encode(value)); c.close(); } });
const never = () => new ReadableStream<Uint8Array>({ start() {} });
const fixture = (hang = false) => {
  let killed = 0;
  const writes: string[] = [];
  const child = { stdout: hang ? never() : closed('{"ready":true}'), stderr: hang ? never() : closed(),
    write: (value: string) => { writes.push(value); }, closeStdin: () => {}, kill: () => { killed++; },
    exited: hang ? new Promise(() => {}) : Promise.resolve(ok({ code: 0 })) };
  const domicile = { processes: { spawn: async () => ok(child) } } as unknown as Domicile;
  return { domicile, child, writes, killed: () => killed };
};
test("deadline rejects even when killing a helper does not settle exit or streams", async () => {
  const f = fixture(true);
  await expect(runHelperRequest(f.domicile, ["fixture"], { requestId: "stable" }, 15)).rejects.toThrow("deadline");
  expect(f.killed()).toBeGreaterThan(0);
});
test("deadline covers spawn acknowledgement; a late process is disposed", async () => {
  const f = fixture();
  let finish: (x: unknown) => void = () => {};
  const domicile = { processes: { spawn: () => new Promise(resolve => { finish = resolve; }) } } as unknown as Domicile;
  await expect(runHelperRequest(domicile, ["fixture"], {}, 15)).rejects.toThrow("deadline");
  finish(ok(f.child));
  await new Promise(resolve => setTimeout(resolve, 0));
  expect(f.killed()).toBeGreaterThan(0);
  expect(f.writes).toHaveLength(0);
});
test("successful helper receives only structured stdin and returns bounded JSON", async () => {
  const f = fixture();
  expect(await runHelperRequest(f.domicile, ["fixture"], { prompt: "$HOME `literal`\n" }, 100)).toEqual({ ready: true });
  expect(f.writes.map(JSON.parse)).toEqual([{ prompt: "$HOME `literal`\n" }]);
  expect(f.killed()).toBe(0);
});
test("oversized output fails without waiting for a stuck helper exit", async () => {
  const f = fixture(true); f.child.stdout = closed("x".repeat(16385));
  await expect(runHelperRequest(f.domicile, ["fixture"], {}, 100)).rejects.toThrow("limit");
  expect(f.killed()).toBeGreaterThan(0);
});
