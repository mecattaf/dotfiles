import { describe, expect, it } from "vitest";
import { spawnSync } from "node:child_process";
import { join } from "node:path";

describe("fences", () => {
  it("tools/check-fences.mjs finds no hit", () => {
    const r = spawnSync(process.execPath, [join(__dirname, "../tools/check-fences.mjs")], { encoding: "utf8" });
    expect(r.stdout).toMatch(/0 hit\(s\)/);
    expect(r.status).toBe(0);
  });
});
