import { describe, expect, it } from "vitest";
import { writeFileSync } from "node:fs";
import { join } from "node:path";
import { main } from "../src/cli.ts";
import { parseRuntimesToml } from "../src/config.ts";
import { tmp } from "./helpers.ts";

describe("cli", () => {
  it("the shipped example decodes", async () => {
    const ex = await main(["example"]);
    expect(ex.code).toBe(0);
    const c = parseRuntimesToml(ex.out, "example", "/home/u");
    expect(Object.keys(c.runtimes).sort()).toEqual(["ax", "edge", "gvisor", "herdr", "ssh:worker", "vm"]);
    expect(c.phases).toEqual({ Review: "gvisor", Scout: "ssh:worker" });
  });
  it("select explains the choice; run executes a host job and exits with its status", async () => {
    const d = tmp();
    const f = join(d, "r.toml");
    writeFileSync(f, 'default = "host"\n[phases]\nX = "ssh:worker"\n');
    expect(JSON.parse((await main(["select", "--config", f, "--phase", "X"])).out)).toMatchObject({ name: "ssh:worker", via: "phase" });
    const ok = await main(["run", "host", "--config", f, "--", "sh", "-c", "echo hi"]);
    expect(ok.code).toBe(0);
    expect(JSON.parse(ok.out)).toMatchObject({ exitCode: 0, stdout: "hi\n" });
    expect((await main(["run", "host", "--config", f, "--", "false"])).code).toBe(1);
    expect((await main(["select", "--config", f, "--runtime", "nope"])).code).toBe(2);
  });
});
