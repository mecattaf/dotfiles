// The runtime-test runtime: the host runner behind the wrapper, refused when the wrapper is missing.
import { chmodSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { isRefusal, parseRuntimesToml, runnerFor, runtimeTestRunner } from "../src/index.ts";

const job = (dir: string) => ({ kind: "process" as const, id: "rt-1", jobDir: join(dir, "job"), argv: ["sh", "-c", "echo inner:$0 $1", "a", "b"] });

describe("runtime-test runner", () => {
  it("refuses when the wrapper is not an executable file", async () => {
    const dir = mkdtempSync(join(tmpdir(), "rt-"));
    const r = runtimeTestRunner("rt", { wrapper: join(dir, "absent") });
    expect(r.refuses(job(dir))).toMatch(/not an executable file; refusing rather than running against the live runtime/);
    const out = await r.run(job(dir));
    expect(isRefusal(out)).toBe(true);
  });

  it("runs the job's argv behind `wrapper --`", async () => {
    const dir = mkdtempSync(join(tmpdir(), "rt-"));
    const wrapper = join(dir, "runtime-test");
    writeFileSync(wrapper, `#!/bin/sh\n[ "$1" = "--" ] || exit 9\nshift\necho wrapped\nexec "$@"\n`);
    chmodSync(wrapper, 0o755);
    const cfg = parseRuntimesToml(`default = "rt"\n[runtime.rt]\ntype = "runtime-test"\nwrapper = "${wrapper}"\n`, "test");
    const r = runnerFor("rt", cfg.runtimes.rt!);
    expect(r.type).toBe("runtime-test");
    const out = await r.run(job(dir));
    if (isRefusal(out)) throw new Error(out.refused);
    expect(out.exitCode).toBe(0);
    expect(out.stdout).toBe("wrapped\ninner:a b\n");
    expect(out.runtime).toBe("rt");
  });
});
