import { describe, expect, it } from "vitest";
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { loadRuntimes, lookupRuntime, parseRuntimesToml, RuntimesConfigError, selectRuntime } from "../src/config.ts";
import { tmp } from "./helpers.ts";

const HOME = "/home/u";

export const EXAMPLE = `
# ~/.config/substrate/runtimes.toml
default = "gvisor"

[phases]
"Review" = "herdr"
"Scout" = "ssh:worker"

[credentials]
claude = "~/.claude"
mode = "rw"

[runtime.gvisor]
type = "gvisor"
runsc = "/nix/store/x-gvisor/bin/runsc"
state = "~/.local/state/substrate/runsc"

[runtime.herdr]
type = "herdr"
mode = "action"

[runtime."ssh:worker"]
type = "ssh"
host = "worker"
harness = "pi"

[runtime.vm]
type = "microvm"
memMiB = 4096

[runtime.edge]
type = "workerd"
workerd = "/nix/store/y-workerd/bin/workerd"

[runtime.ax]
type = "ax"
sandboxClass = "microvm"
`;

describe("runtimes.toml", () => {
  it("decodes the documented example, expanding ~ in path fields", () => {
    const c = parseRuntimesToml(EXAMPLE, "example", HOME);
    expect(c.default).toBe("gvisor");
    expect(c.credentials).toEqual({ claude: "/home/u/.claude", mode: "rw", scope: "credential", claudeExplicit: true });
    const g = c.runtimes.gvisor!;
    expect(g.type === "gvisor" && g.state).toBe("/home/u/.local/state/substrate/runsc");
    expect(c.runtimes["ssh:worker"]).toMatchObject({ type: "ssh", host: "worker", harness: "pi" });
  });

  it("an empty file means everything on host, credential rw at ~/.claude", () => {
    const c = parseRuntimesToml("", "empty", HOME);
    expect(c.default).toBe("host");
    expect(c.credentials).toEqual({ claude: "/home/u/.claude", mode: "rw", scope: "credential" });
    expect(selectRuntime(c, {}).runtime).toEqual({ type: "host" });
  });

  it("a missing default-path file is host; a missing explicit file is an error", () => {
    const home = tmp();
    expect(loadRuntimes(undefined, home).default).toBe("host");
    expect(() => loadRuntimes(join(home, "nope.toml"), home)).toThrow(RuntimesConfigError);
    mkdirSync(join(home, ".config/substrate"), { recursive: true });
    writeFileSync(join(home, ".config/substrate/runtimes.toml"), 'default = "ssh:worker"\n');
    expect(loadRuntimes(undefined, home).default).toBe("ssh:worker");
  });

  it("names every problem at once: unknown default, unknown phase target, relative path, state under /run/user", () => {
    const bad = `
default = "nowhere"
[phases]
Build = "missing"
[runtime.g]
type = "gvisor"
runsc = "bin/runsc"
state = "/run/user/1000/runsc"
`;
    let msg = "";
    try {
      parseRuntimesToml(bad, "bad", HOME);
    } catch (e) {
      msg = (e as Error).message;
    }
    expect(msg).toContain('default = "nowhere" names no runtime');
    expect(msg).toContain('phases."Build" = "missing" names no runtime');
    expect(msg).toContain("runtime.g.runsc must be absolute");
    expect(msg).toContain("must not live under /run/user");
  });

  it("rejects an unknown runtime type and a missing required field", () => {
    expect(() => parseRuntimesToml('[runtime.x]\ntype = "docker"\n', "t", HOME)).toThrow(RuntimesConfigError);
    expect(() => parseRuntimesToml('[runtime.x]\ntype = "gvisor"\n', "t", HOME)).toThrow(/runsc/);
    expect(() => parseRuntimesToml("default = [", "t", HOME)).toThrow(/TOML/);
  });

  it("selects call > phase > default > host", () => {
    const c = parseRuntimesToml(EXAMPLE, "example", HOME);
    expect(selectRuntime(c, { runtime: "vm", phase: "Review" })).toMatchObject({ name: "vm", via: "call" });
    // Successor review r4: the phase map is a floor. Review maps to herdr, an
    // escape from the sandboxed default gvisor, so it is refused unless the
    // file's allow list names herdr.
    expect(() => selectRuntime(c, { phase: "Review" })).toThrow(/phase "Review" refused.*sandboxed default gvisor/);
    expect(selectRuntime({ ...c, allow: ["herdr", "vm"] }, { phase: "Review" })).toMatchObject({ name: "herdr", via: "phase" });
    expect(selectRuntime(c, { phase: "Unlisted" })).toMatchObject({ name: "gvisor", via: "default" });
    expect(selectRuntime(parseRuntimesToml("", "e", HOME), { phase: "Review" })).toMatchObject({ name: "host", via: "default" });
  });

  it("ssh:<host> works without a table; a table of that name overrides it", () => {
    const c = parseRuntimesToml(EXAMPLE, "example", HOME);
    expect(lookupRuntime(c, "ssh:nas")).toEqual({ type: "ssh", host: "nas" });
    expect(lookupRuntime(c, "ssh:worker")).toMatchObject({ harness: "pi" });
    expect(lookupRuntime(c, "ssh:")).toBeUndefined();
  });

  it("an agent() call naming an unknown runtime is an error, not a silent fallback", () => {
    const c = parseRuntimesToml(EXAMPLE, "example", HOME);
    expect(() => selectRuntime(c, { runtime: "gvisr" })).toThrow(/names no runtime/);
    expect(() => selectRuntime(c, { runtime: 3 })).toThrow(/must be a string/);
  });
});
