import { describe, expect, it } from "vitest";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { guestFlake, guestScript, microvmRunner } from "../src/microvm.ts";
import { AGENT_REFUSAL, workerdConfig, workerdRunner } from "../src/workerd.ts";
import { axRunner, axTaskSpec, INLINE_ENV_BUDGET, type AxCall } from "../src/ax.ts";
import { isRefusal, type ProcessJob, type RunOutcome } from "../src/job.ts";
import { fakeBin, tmp } from "./helpers.ts";

const d = tmp();
const cred = join(d, "seat");
mkdirSync(cred);
writeFileSync(join(cred, ".credentials.json"), "SECRET-MARKER-91c2");
const pjob = (over: Partial<ProcessJob> = {}): ProcessJob => ({
  kind: "process",
  id: "m1",
  argv: ["sh", "-c", "echo hi"],
  stdin: "PROMPT-MARKER-55",
  jobDir: join(d, "job"),
  mounts: [{ source: cred, target: "/root/.claude", mode: "rw", purpose: "credential" }],
  ...over,
});

describe("microvm guest", () => {
  it("the flake holds paths and sizes only: no credential bytes, no prompt", () => {
    const f = guestFlake(pjob(), { vcpu: 3, memMiB: 3072 });
    expect(f).toContain(`source = ${JSON.stringify(cred)}; mountPoint = "/root/.claude"; readOnly = false;`);
    expect(f).toContain(`readOnly = true; }`); // the store share
    expect(f).toContain("vcpu = 3;");
    expect(f).toContain("mem = 3072;");
    expect(f).not.toContain("SECRET-MARKER");
    expect(f).not.toContain("PROMPT-MARKER");
    expect(f).toContain("microvm.declaredRunner");
  });

  it("G1: never generates exactly 2048 MiB, which hangs the guest at ACPI (microvm.nix issue 171)", () => {
    expect(guestFlake(pjob(), {})).toContain("mem = 2047;");
    expect(guestFlake(pjob(), { memMiB: 2048 })).toContain("mem = 2047;");
    expect(guestFlake(pjob(), { memMiB: 2048 })).not.toContain("mem = 2048;");
    expect(guestFlake(pjob(), { memMiB: 4096 })).toContain("mem = 4096;");
  });

  it("G1: a failing run.sh still writes /job/exit and powers off (the unit script runs under bash -e)", () => {
    const f = guestFlake(pjob(), {});
    expect(f).toContain("/job/run.sh || rc=$?; echo $rc > /job/exit;");
    expect(f).toContain("systemctl poweroff");
  });

  it("G1: the guest resolves fleet short names from the host's hosts file, loopback dropped", () => {
    const f = guestFlake(pjob(), { hosts: "127.0.0.1 localhost\n::1 localhost\n10.42.0.5 worker # lan\n# 10.0.0.9 gone\nbad$ name\n" });
    expect(f).toContain(`networking.extraHosts = "10.42.0.5 worker\\n";`);
    expect(f).not.toContain("localhost");
    expect(f).not.toContain("gone");
    expect(guestFlake(pjob(), {})).not.toContain("extraHosts");
  });

  it("run.sh runs argv exactly, stdin from the share, streams apart", () => {
    const s = guestScript(pjob({ argv: ["claude", "-p", "it's"], env: { K: "v w" } }), "/nix/store/c/bin/claude");
    expect(s).toContain(`export K='v w'`);
    expect(s).toContain("export IS_SANDBOX=1");
    expect(s).toContain(`/nix/store/c/bin/claude -p 'it'\\''s' < /job/.stdin > /job/stdout 2> /job/stderr`);
  });

  it("builds, then refuses the boot clearly when the gate says no, keeping the runner path", async () => {
    const bin = tmp();
    const nix = fakeBin(bin, "nix", `echo "$*" > ${bin}/nix.argv; echo /nix/store/fake-microvm-runner`);
    const r = microvmRunner("microvm", { nix, state: join(bin, "state"), gate: () => "/dev/kvm is not reachable here" });
    const res = await r.run(pjob());
    expect(isRefusal(res)).toBe(true);
    if (!isRefusal(res)) return;
    expect(res.refused).toBe("built /nix/store/fake-microvm-runner; not booted: /dev/kvm is not reachable here");
    expect(res.detail?.runner).toBe("/nix/store/fake-microvm-runner");
    expect(readFileSync(join(bin, "nix.argv"), "utf8")).toMatch(/^build --no-link --print-out-paths path:.*#default/);
    expect(readFileSync(join(d, "job/.stdin"), "utf8")).toBe("PROMPT-MARKER-55"); // in the job dir, not the flake
  });

  it("a failed build is a refusal carrying nix's stderr", async () => {
    const bin = tmp();
    const nix = fakeBin(bin, "nix", "echo 'error: attribute missing' >&2; exit 1");
    const res = await microvmRunner("microvm", { nix, state: join(bin, "state"), gate: () => undefined }).run(pjob());
    expect(isRefusal(res) && res.refused).toMatch(/nix build failed \(rc 1\).*attribute missing/s);
  });
});

describe("workerd", () => {
  const w = workerdRunner("workerd", { workerd: "/bin/true" });
  it("refuses every agent() job, and any process job, by design", () => {
    expect(w.refuses(pjob({ agent: true }))).toBe(AGENT_REFUSAL);
    expect(w.refuses(pjob())).toBe(AGENT_REFUSAL);
  });
  it("config embeds the module and bindings as files and closes egress by default", () => {
    const c = workerdConfig({ kind: "worker", id: "w1", module: "export default {}", bindings: { INPUT: 'a "b" \\ c' }, jobDir: d });
    expect(c.files).toEqual({ "job.js": "export default {}", "binding-INPUT.txt": 'a "b" \\ c' });
    expect(c.capnp).toContain('(name = "INPUT", text = embed "binding-INPUT.txt")');
    expect(c.capnp).toContain('globalOutbound = "egress"');
    expect(c.capnp).toContain("network = (allow = [  ])");
    expect(workerdConfig({ kind: "worker", id: "w", module: "", jobDir: d }, { allow: ["private"] }).capnp).toContain('allow = [ "private" ]');
  });
  it("refuses bad binding names and modules without a default export", () => {
    expect(w.refuses({ kind: "worker", id: "w2", module: "export const x = 1", jobDir: d })).toMatch(/default export/);
    expect(w.refuses({ kind: "worker", id: "w3", module: "export default {}", bindings: { "a-b": "" }, jobDir: d })).toMatch(/identifier/);
  });

  // The real binary, when this box has it (built from workerd.nix main by the 2026-09-23 runners track).
  const real = process.env.AXC_WORKERD ?? "/nix/store/4ffm95hsqvrsvwxyjvc64wwbnsi7rp1k-workerd-1.20260722.1/bin/workerd";
  it.skipIf(!existsSync(real))("runs a Worker job one-shot with the real workerd: pass is 0, fail is 1", async () => {
    const mod = (want: number) => `export default { async test(ctrl, env) {
      const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(env.INPUT));
      const hex = [...new Uint8Array(d)].map(b => b.toString(16).padStart(2, "0")).join("");
      console.log(JSON.stringify({ hex }));
      if (hex.length !== ${want}) throw new Error("bad length " + hex.length);
    } };`;
    const r = workerdRunner("workerd", { workerd: real });
    const pass = (await r.run({ kind: "worker", id: "wp", module: mod(64), bindings: { INPUT: "hello tom" }, jobDir: join(d, "wp") })) as RunOutcome;
    expect(pass.exitCode).toBe(0);
    expect(pass.stdout + pass.stderr).toContain("c3ce9d9c");
    const fail = (await r.run({ kind: "worker", id: "wf", module: mod(65), bindings: { INPUT: "hello tom" }, jobDir: join(d, "wf") })) as RunOutcome;
    expect(fail.exitCode).toBe(1);
  });
});

describe("ax seam", () => {
  const call: AxCall = {
    runId: "wf_12695394-85A",
    index: 7,
    label: "review: x",
    prompt: "do the thing",
    model: "claude-opus-5-5",
    journalKey: "abcdef0123456789".repeat(4),
    workflow: "Substrate Thread",
    phaseIndex: 2,
    phaseTitle: "Review",
    seat: "cc",
    attempt: 1,
    schema: { type: "object" },
    isolation: "worktree",
  };
  it("emits the FIELD-MAP 5a keys and the name <fold(runId)>-<index>-<key8>", () => {
    const t = axTaskSpec(call);
    if ("refused" in t) throw new Error(t.refused);
    expect(t.name).toBe("wf_12695394-85a".replace("_", "-") + "-7-abcdef01");
    expect(t.atespace).toBe("ultracode");
    const env = Object.fromEntries(t.spec.env.map((e) => [e.name, e.value]));
    expect(Object.keys(env)).toEqual(
      expect.arrayContaining([
        "AX_CONWIP_RUN_ID", "AX_CONWIP_LABEL", "AX_CONWIP_MODEL", "AX_CONWIP_ITEM_KEY", "AX_CONWIP_JOURNAL_KEY",
        "AX_CONWIP_WORKFLOW", "AX_CONWIP_PHASE_INDEX", "AX_CONWIP_PHASE_TITLE", "AX_CONWIP_SEAT", "AX_CONWIP_ATTEMPT",
        "AX_CONWIP_SCHEMA_JSON", "AX_CONWIP_PROMPT", "AX_CONWIP_PROMPT_SHA256", "AX_CONWIP_RESULT_PATH",
        "AX_CONWIP_USAGE_PATH", "AX_CONWIP_ISOLATION", "AX_CONWIP_BRANCH",
      ]),
    );
    expect(env.AX_CONWIP_ITEM_KEY).toBe("wf_12695394-85A#7");
    expect(env.AX_CONWIP_BRANCH).toBe("uc/wf-12695394-85a/7");
    expect(t.spec.gateway).toEqual({ name: "ultracode-egress" });
    expect(t.labels["app.kubernetes.io/managed-by"]).toBe("substrate");
  });
  it("moves a large prompt to the file route and refuses when the rest is still over budget", () => {
    const big = axTaskSpec({ ...call, prompt: "x".repeat(INLINE_ENV_BUDGET) });
    if ("refused" in big) throw new Error(big.refused);
    expect(big.spec.env.some((e) => e.name === "AX_CONWIP_PROMPT")).toBe(false);
    expect(big.promptFile?.path).toBe("/workspace/.ultracode/abcdef01/prompt.md");
    expect(big.envBytes).toBeLessThanOrEqual(INLINE_ENV_BUDGET);
    const huge = axTaskSpec({ ...call, schema: { d: "y".repeat(INLINE_ENV_BUDGET) } });
    expect("refused" in huge && huge.refused).toMatch(/over the 16384 byte budget/);
  });
  it("the runner never dispatches", async () => {
    const r = await axRunner("ax").run({ kind: "process", id: "x", argv: ["a"], jobDir: d });
    expect(isRefusal(r) && r.refused).toMatch(/spec-only/);
  });
});
