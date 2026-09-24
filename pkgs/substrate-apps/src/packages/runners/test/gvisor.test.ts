import { describe, expect, it } from "vitest";
import { existsSync, readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import { gvisorRunner, ociConfig, resolveInStore, runscArgv, SANDBOX_HOME } from "../src/gvisor.ts";
import { isRefusal, type ProcessJob, type RunOutcome } from "../src/job.ts";
import { fakeBin, tmp } from "./helpers.ts";

const d = tmp();
const cred = join(d, "seat");
mkdirSync(cred);
const MARKER = "SECRET-MARKER-7f3a";
writeFileSync(join(cred, ".credentials.json"), `{"token":"${MARKER}"}`);
const sh = resolveInStore("sh") as string;

const job = (over: Partial<ProcessJob> = {}): ProcessJob => ({
  kind: "process",
  id: "g1",
  argv: ["sh", "-c", "exit 5"],
  jobDir: join(d, "job"),
  mounts: [{ source: cred, target: `${SANDBOX_HOME}/.claude`, mode: "rw", purpose: "credential" }],
  ...over,
});

describe("gvisor OCI bundle", () => {
  it("argv[0] resolves into /nix/store or is refused", () => {
    expect(sh.startsWith("/nix/store/")).toBe(true);
    expect(resolveInStore("/definitely/not/here")).toHaveProperty("error");
  });

  it("read-only root, store ro, job dir rw at /work, credential bound rw from its host path", () => {
    const c = ociConfig(job(), sh) as { root: unknown; mounts: { destination: string; source: string; options?: string[] }[]; process: { cwd: string; env: string[]; args: string[] } };
    expect(c.root).toEqual({ path: "rootfs", readonly: true });
    const m = (dest: string) => c.mounts.find((x) => x.destination === dest);
    expect(m("/nix/store")?.options).toEqual(["rbind", "ro"]);
    expect(m("/work")).toMatchObject({ source: join(d, "job"), options: ["rbind", "rw"] });
    expect(m(`${SANDBOX_HOME}/.claude`)).toMatchObject({ source: cred, options: ["rbind", "rw"] });
    expect(c.process.cwd).toBe("/work");
    expect(c.process.args).toEqual([sh, "-c", "exit 5"]);
    expect(c.process.env).toContain(`HOME=${SANDBOX_HOME}`);
    expect(c.process.env).toContain("IS_SANDBOX=1"); // claude refuses bypass mode as root otherwise
    expect(c.mounts.some((x) => x.destination === "/home/tom" || x.source === "/")).toBe(false);
  });

  it("PATH carries the caller's store-resolved dirs; /bin/sh and /usr/bin/env are bound from the store", () => {
    const c = ociConfig(job(), sh) as { mounts: { destination: string; source: string; options?: string[] }[]; process: { env: string[] } };
    const path = c.process.env.find((e) => e.startsWith("PATH="))!.slice(5).split(":");
    expect(path.every((p) => p.startsWith("/nix/store/"))).toBe(true);
    expect(path.length).toBeGreaterThan(1);
    const binSh = c.mounts.find((m) => m.destination === "/bin/sh");
    expect(binSh?.source.startsWith("/nix/store/")).toBe(true);
    expect(binSh?.options).toEqual(["rbind", "ro"]);
    expect(c.process.env.some((e) => e.startsWith("SHELL=/nix/store/"))).toBe(true);
  });

  it("never carries credential bytes: only the path", () => {
    expect(JSON.stringify(ociConfig(job(), sh))).not.toContain(MARKER);
  });

  it("network none adds a network namespace and no host resolv.conf", () => {
    const c = ociConfig(job(), sh, { network: "none" }) as { linux: { namespaces: { type: string }[] }; mounts: { destination: string }[] };
    expect(c.linux.namespaces).toContainEqual({ type: "network" });
    expect(c.mounts.some((m) => m.destination === "/etc/resolv.conf")).toBe(false);
  });

  it("runsc argv is rootless with --root under the given state dir", () => {
    expect(runscArgv({ runsc: "/r/runsc", network: "host" }, "/s", "/s/b", "c1")).toEqual([
      "/r/runsc", "--rootless", "--network=host", "--root=/s", "run", "--bundle", "/s/b", "c1",
    ]);
  });
  it("r4: the default network is isolated: runsc runs inside pasta with no gateway mapping and no port forwards", () => {
    const argv = runscArgv({ runsc: "/r/runsc", pasta: "/p/pasta" }, "/s", "/s/b", "c1");
    const dash = argv.indexOf("--");
    expect(argv[0]).toBe("/p/pasta");
    expect(argv.slice(0, dash)).toEqual(expect.arrayContaining(["--config-net", "--no-map-gw", "-T", "-U", "--dns-forward"]));
    for (const f of ["-t", "-u", "-T", "-U"]) expect(argv[argv.indexOf(f) + 1]).toBe("none");
    expect(argv.slice(dash + 1)).toEqual(["/r/runsc", "--rootless", "--network=host", "--root=/s", "run", "--bundle", "/s/b", "c1"]);
    expect(runscArgv({ runsc: "/r/runsc", network: "none" }, "/s", "/s/b", "c1")[0]).toBe("/r/runsc");
  });
});

describe("gvisor runner with a fake runsc", () => {
  const bin = tmp();
  const calls = join(bin, "calls");
  // Fake runsc: logs argv; on `run` checks the bundle has config.json, echoes stdin, exits 5.
  const runsc = fakeBin(
    bin,
    "runsc",
    `echo "$*" >> ${calls}
case "$*" in *" run "*) b="\${@: -2:1}"; test -f "$b/config.json" || exit 99; cat; echo fake-stderr >&2; exit 5;; esac; exit 0`,
  );
  const state = join(bin, "state");

  it("propagates the exit code and stdin, then force-deletes and removes the bundle", async () => {
    const r = gvisorRunner("gvisor", { runsc, state, network: "host" });
    const res = (await r.run(job({ stdin: "hello" }))) as RunOutcome;
    expect(isRefusal(res)).toBe(false);
    expect(res).toMatchObject({ exitCode: 5, stdout: "hello", stderr: "fake-stderr\n" });
    const log = readFileSync(calls, "utf8");
    expect(log).toMatch(/--root=.*state run --bundle/);
    expect(log).toMatch(/delete --force axc-g1-/);
    expect(existsSync(join(state, "bundles", res.detail!.containerId!))).toBe(false);
    expect(JSON.parse(readFileSync(res.detail!.config!, "utf8")).process.cwd).toBe("/work");
  });

  it("refuses a missing runsc, a missing mount source and a non-store binary", () => {
    expect(gvisorRunner("g", { runsc: "/no/runsc", state }).refuses(job())).toMatch(/runsc not found/);
    const r = gvisorRunner("g", { runsc, state, network: "host" });
    expect(r.refuses(job({ mounts: [{ source: "/no/such", target: "/x", mode: "ro" }] }))).toMatch(/does not exist/);
    expect(r.refuses(job({ argv: [runsc] }))).toMatch(/outside \/nix\/store/);
    expect(gvisorRunner("g", { runsc, state: "/run/user/1000/x" }).refuses(job())).toMatch(/\/run\/user/);
  });
  it("r4: isolated without pasta is refused, never silently the host network", () => {
    expect(gvisorRunner("g", { runsc, state, pasta: "/no/pasta" }).refuses(job())).toMatch(/network = "isolated" needs pasta/);
  });
  it("r4: isolated runs runsc through pasta and binds a resolv.conf naming pasta's DNS forwarder", async () => {
    const plog = join(bin, "pasta-calls");
    // Fake pasta: logs its own flags, then execs what follows "--".
    const pasta = fakeBin(bin, "pasta", `echo "$*" >> ${plog}\nwhile [ "$1" != "--" ]; do shift; done; shift; exec "$@"`);
    const r = gvisorRunner("gvisor", { runsc, state, pasta });
    const res = (await r.run(job({ stdin: "hi" }))) as RunOutcome;
    expect(res).toMatchObject({ exitCode: 5, stdout: "hi" });
    expect(readFileSync(plog, "utf8")).toMatch(/--no-map-gw.*-T none -U none/);
    const cfg = JSON.parse(readFileSync(res.detail!.config!, "utf8")) as { mounts: { destination: string; source: string }[] };
    const resolv = cfg.mounts.find((m) => m.destination === "/etc/resolv.conf");
    expect(resolv?.source).toMatch(/resolv\.conf$/);
    expect(res.detail).toMatchObject({ network: "isolated" });
  });
});
