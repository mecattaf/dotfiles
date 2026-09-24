import { describe, expect, it } from "vitest";
import { join } from "node:path";
import { hostRunner } from "../src/host.ts";
import { sshArgv, sshRunner } from "../src/ssh.ts";
import { isRefusal, type RunOutcome } from "../src/job.ts";
import { fakeBin, tmp } from "./helpers.ts";

const outcome = (r: unknown) => {
  if (isRefusal(r as never)) throw new Error(`refused: ${(r as { refused: string }).refused}`);
  return r as RunOutcome;
};

describe("host runner", () => {
  const d = tmp();
  const host = hostRunner();
  it("propagates the exit code, keeps stdout and stderr apart, feeds stdin", async () => {
    const r = outcome(
      await host.run({ kind: "process", id: "h1", argv: ["sh", "-c", "cat; echo err >&2; exit 3"], stdin: "in-bytes", jobDir: join(d, "h1") }),
    );
    expect(r).toMatchObject({ exitCode: 3, stdout: "in-bytes", stderr: "err\n" });
  });
  it("runs in the job dir", async () => {
    const r = outcome(await host.run({ kind: "process", id: "h2", argv: ["pwd"], jobDir: join(d, "h2") }));
    expect(r.stdout.trim()).toBe(join(d, "h2"));
  });
  it("kills at the timeout with 124", async () => {
    const r = outcome(await host.run({ kind: "process", id: "h3", argv: ["sleep", "5"], jobDir: join(d, "h3"), timeoutMs: 200 }));
    expect(r.exitCode).toBe(124);
    expect(r.timedOut).toBe(true);
  });
  it("reports 127 when the binary does not exist", async () => {
    const r = outcome(await host.run({ kind: "process", id: "h4", argv: ["/nonexistent/bin"], jobDir: join(d, "h4") }));
    expect(r.exitCode).toBe(127);
  });
  it("refuses worker jobs, bad ids and non-identity mounts", async () => {
    expect(host.refuses({ kind: "worker", id: "w", module: "export default {}", jobDir: d })).toMatch(/workerd/);
    expect(host.refuses({ kind: "process", id: "../x", argv: ["true"], jobDir: d })).toMatch(/job id/);
    const r = await host.run({ kind: "process", id: "h5", argv: ["true"], jobDir: d, mounts: [{ source: "/a", target: "/b", mode: "ro" }] });
    expect(isRefusal(r)).toBe(true);
  });
});

describe("ssh runner", () => {
  const d = tmp();
  // A fake ssh: records its argv, then runs the remote string locally with sh, as sshd would.
  const log = join(d, "ssh.argv");
  const ssh = fakeBin(d, "ssh", `printf '%s\\n' "$@" > ${log}; for last; do :; done; cd ${d}; exec sh -c "$last"`);

  it("builds BatchMode argv with the remote command quoted element by element", () => {
    const a = sshArgv({ host: "worker" }, { argv: ["pi", "-p", "it's $HOME"], env: { A: "x y" } });
    expect(a.slice(0, 11)).toEqual(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=3", "-T", "worker"]);
    expect(a[12]).toBe(`env A='x y' pi -p 'it'\\''s $HOME'`);
  });

  it("round-trips hostile arguments and stdin exactly", async () => {
    const r = sshRunner("ssh:worker", { host: "worker", ssh });
    const hostile = [`a b`, `'q'`, `$(touch ${d}/pwned)`, "`x`", `\\n;`, ""];
    const res = outcome(
      await r.run({ kind: "process", id: "s1", argv: ["printf", "[%s]", ...hostile], stdin: "", jobDir: join(d, "s1") }),
    );
    expect(res.stdout).toBe(hostile.map((h) => `[${h}]`).join(""));
    const { existsSync } = await import("node:fs");
    expect(existsSync(join(d, "pwned"))).toBe(false);
  });

  it("passes stdin through and marks ssh's own exit 255 as transport", async () => {
    const r = sshRunner("ssh:worker", { host: "worker", ssh });
    expect(outcome(await r.run({ kind: "process", id: "s2", argv: ["cat"], stdin: "prompt", jobDir: d })).stdout).toBe("prompt");
    const f = outcome(await r.run({ kind: "process", id: "s3", argv: ["sh", "-c", "exit 255"], jobDir: d }));
    expect(f.detail?.transport).toMatch(/255/);
  });

  it("refuses host mounts: the remote uses its own seat", () => {
    const r = sshRunner("ssh:worker", { host: "worker", ssh });
    expect(r.refuses({ kind: "process", id: "s4", argv: ["claude"], jobDir: d, mounts: [{ source: "/c", target: "/c", mode: "rw" }] })).toMatch(
      /own seat/,
    );
  });
});
