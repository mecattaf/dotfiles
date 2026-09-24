/**
 * Guardrail 1 (AUDIT-transcripts TX1, TX3): the scratch probe of 2026-09-24,
 * flipped. A fake sandboxed runner plays Claude Code and writes its session
 * where Claude Code writes one (<CLAUDE_CONFIG_DIR>/projects/<slug>/<sid>.jsonl,
 * inside the seat shadow). The transcript now survives the job, outside the
 * run dir, and the receipt names the session and the archived files.
 */
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, statSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { RunnerBackend, seatShadowRoot, sweepSeatShadows } from "../src/backend.ts";
import { parseRuntimesToml } from "../src/config.ts";
import { archiveShadowTranscripts, copyCapped, findCodexRollout } from "../src/transcripts.ts";
import type { Job, Runner, RunResult } from "../src/index.ts";

const SESSION = "0b5e5510-aaaa-bbbb-cccc-000000000001";
const envelope = JSON.stringify({ type: "result", subtype: "success", is_error: false, session_id: SESSION, result: "ok", usage: { input_tokens: 1, output_tokens: 1 } });
const jsonlUnder = (dir: string, out: string[] = []): string[] => {
  if (!existsSync(dir)) return out;
  for (const f of readdirSync(dir)) {
    const p = join(dir, f);
    if (statSync(p).isDirectory()) jsonlUnder(p, out);
    else if (f.endsWith(".jsonl") && f !== "journal.jsonl") out.push(p);
  }
  return out;
};

const setup = (type: "gvisor" | "microvm" | "host") => {
  const root = mkdtempSync(join(tmpdir(), "tx-"));
  const seat = join(root, "fake-seat");
  mkdirSync(seat);
  writeFileSync(join(seat, ".credentials.json"), "FAKE\n", { mode: 0o600 });
  const config = parseRuntimesToml(`default = "box"\n[credentials]\nclaude = "${seat}"\n[runtime.box]\ntype = "${type}"\n${type === "gvisor" ? `runsc = "/nonexistent/runsc"\n` : ""}`, "t", "/home/u");
  return { root, seat, config, txRoot: join(root, "state", "transcripts") };
};

for (const type of ["gvisor", "microvm"] as const) {
  describe(`${type}: claude transcript retention`, () => {
    it("archives the session written into the seat shadow before the shadow is removed; the receipt names it", async () => {
      const { root, config, txRoot } = setup(type);
      let wrote = "";
      const box: Runner = {
        name: "box", type, refuses: () => undefined,
        run: async (j: Job) => {
          if (j.kind !== "process") throw new Error("not a process job");
          const proj = join(j.mounts![0]!.source, "projects", "-work");
          mkdirSync(proj, { recursive: true });
          wrote = join(proj, `${SESSION}.jsonl`);
          writeFileSync(wrote, JSON.stringify({ type: "user", message: "P" }) + "\n");
          // a hostile job plants a link to a host file and a FIFO-like non-file: neither is followed
          symlinkSync("/etc/passwd", join(proj, "evil.jsonl"));
          return { runtime: "box", jobId: j.id, exitCode: 0, stdout: envelope, stderr: "warn\n", durationMs: 1 } as RunResult;
        },
      };
      const jobsRoot = join(root, "run", "jobs");
      const b = new RunnerBackend(config, { jobsRoot, runId: "wf_probe", runners: { box }, transcriptRoot: txRoot });
      const out = await b.run({ index: 1, key: "k1", prompt: "P", opts: {}, phase: undefined, attempt: 1 } as never);
      expect((out as { agentId?: string }).agentId).toBe(SESSION);
      expect(wrote.startsWith(seatShadowRoot(config))).toBe(true);
      expect(existsSync(wrote)).toBe(false); // the shadow is still removed
      expect(jsonlUnder(join(root, "run"))).toEqual([]); // never into the run dir
      const kept = jsonlUnder(txRoot);
      expect(kept.length).toBe(1);
      expect(readFileSync(kept[0]!, "utf8")).toContain('"message":"P"');
      expect(statSync(join(txRoot, "wf_probe")).mode & 0o077).toBe(0);
      const r = JSON.parse(readFileSync(join(jobsRoot, "wf_probe-1-a1", "receipt.json"), "utf8")) as { sessionId: string; transcripts: Array<{ name: string; bytes: number; sha256: string; source: string }> };
      expect(r.sessionId).toBe(SESSION);
      const names = r.transcripts.map((t) => t.name).sort();
      expect(names).toEqual(["claude--work__0b5e5510-aaaa-bbbb-cccc-000000000001.jsonl", "harness.stderr", "harness.stdout"]);
      expect(r.transcripts.every((t) => /^[0-9a-f]{64}$/.test(t.sha256) && t.bytes > 0)).toBe(true);
    });
  });
}

describe("host: the session is found by id under CLAUDE_CONFIG_DIR", () => {
  it("copies <config>/projects/<slug>/<sid>.jsonl into the archive", async () => {
    const { root, seat, config, txRoot } = setup("host");
    const proj = join(seat, "projects", "-home-u-x");
    mkdirSync(proj, { recursive: true });
    writeFileSync(join(proj, `${SESSION}.jsonl`), '{"type":"assistant"}\n');
    const box: Runner = { name: "box", type: "host", refuses: () => undefined, run: async (j: Job) => ({ runtime: "box", jobId: j.id, exitCode: 0, stdout: envelope, stderr: "", durationMs: 1 } as RunResult) };
    const b = new RunnerBackend(config, { jobsRoot: join(root, "run", "jobs"), runId: "wf_h", runners: { box }, transcriptRoot: txRoot });
    await b.run({ index: 2, key: "k", prompt: "P", opts: {}, phase: undefined, attempt: 1 } as never);
    expect(readFileSync(join(txRoot, "wf_h", "wf_h-2-a1", `claude-${SESSION}.jsonl`), "utf8")).toContain("assistant");
    expect(existsSync(join(proj, `${SESSION}.jsonl`))).toBe(true); // the seat's own copy is untouched
  });
});

describe("the kill -9 sweep archives an orphan shadow before removing it", () => {
  it("keeps projects/**/*.jsonl under <transcripts>/swept/<shadow>", () => {
    const { root, config, txRoot } = setup("gvisor");
    const shadows = seatShadowRoot(config, join(root, "shadows"));
    const sh = join(shadows, "wf_dead-3-a1");
    mkdirSync(join(sh, "projects", "p"), { recursive: true });
    writeFileSync(join(sh, "projects", "p", "s.jsonl"), "{}\n");
    writeFileSync(`${sh}.owner.json`, JSON.stringify({ pid: 999999999, start: "1" }));
    const lines = sweepSeatShadows(config, "wf_other", join(root, "run", "jobs"), shadows, txRoot);
    expect(existsSync(sh)).toBe(false);
    expect(lines.join("\n")).toContain("1 transcript file(s) archived");
    expect(readFileSync(join(txRoot, "swept", "wf_dead-3-a1", "claude-p__s.jsonl"), "utf8")).toBe("{}\n");
  });
});

describe("copy rules", () => {
  it("caps a file with head plus tail and a marker", () => {
    const d = mkdtempSync(join(tmpdir(), "txc-"));
    writeFileSync(join(d, "big"), "A".repeat(5000) + "B".repeat(5000));
    const t = copyCapped(join(d, "big"), d, "out", "x", 2000)!;
    expect(t.truncated).toBe(true);
    const s = readFileSync(join(d, "out"), "utf8");
    expect(s.startsWith("A")).toBe(true);
    expect(s.endsWith("B")).toBe(true);
    expect(s).toContain("bytes elided");
  });
  it("never follows a symlinked directory or file, never copies the credential", () => {
    const d = mkdtempSync(join(tmpdir(), "txs-"));
    const sh = join(d, "shadow");
    mkdirSync(join(sh, "projects"), { recursive: true });
    writeFileSync(join(sh, ".credentials.json"), "SECRET");
    const outside = join(d, "outside");
    mkdirSync(outside);
    writeFileSync(join(outside, "x.jsonl"), "HOST");
    symlinkSync(outside, join(sh, "projects", "linked"));
    expect(archiveShadowTranscripts(sh, join(d, "dest"))).toEqual([]);
  });
  it("finds a codex rollout by thread id", () => {
    const d = mkdtempSync(join(tmpdir(), "txx-"));
    const day = join(d, "sessions", "2026", "09", "24");
    mkdirSync(day, { recursive: true });
    writeFileSync(join(day, "rollout-2026-09-24T07-00-00-0199aaaa-bbbb-cccc-dddd-eeeeffff0000.jsonl"), "{}\n");
    expect(findCodexRollout(d, "0199aaaa-bbbb-cccc-dddd-eeeeffff0000")).toMatch(/rollout-.*\.jsonl$/);
    expect(findCodexRollout(d, "../../etc")).toBeUndefined();
  });
});

describe("TX5: credentials.seat_dirs binds the claude config dir to the seat the call spends", () => {
  const mk = (seatLine: string) => {
    const root = mkdtempSync(join(tmpdir(), "tx5-"));
    for (const d of ["cc", "cc2"]) { mkdirSync(join(root, d)); writeFileSync(join(root, d, ".credentials.json"), "FAKE\n"); }
    const config = parseRuntimesToml(`default = "box"\n[credentials]\nclaude = "${root}/cc"\nseat_dirs = { cc = "${root}/cc", cc2 = "${root}/cc2" }\n[runtime.box]\ntype = "host"\n${seatLine}\n`, "t", "/home/u");
    const seen: string[] = [];
    const box: Runner = { name: "box", type: "host", refuses: () => undefined, run: async (j: Job) => { if (j.kind === "process") seen.push(String(j.env?.CLAUDE_CONFIG_DIR)); return { runtime: "box", jobId: j.id, exitCode: 0, stdout: envelope, stderr: "", durationMs: 1 } as RunResult; } };
    return { root, config, seen, box };
  };
  it("a runtime whose seat is cc2 runs on the cc2 dir, not credentials.claude", async () => {
    const { root, config, seen, box } = mk(`seat = "cc2"`);
    const b = new RunnerBackend(config, { jobsRoot: join(root, "run", "jobs"), runId: "wf_s", runners: { box }, transcriptRoot: join(root, "tx") });
    const out = await b.run({ index: 1, key: "k", prompt: "P", opts: {}, phase: undefined, attempt: 1 } as never);
    expect(out.error).toBeUndefined();
    expect(seen).toEqual([join(root, "cc2")]);
  });
  it("a seat with no declared dir is refused before anything runs (at load since RG-1 and TX5 share one map)", () => {
    expect(() => mk(`seat = "cc3"`)).toThrow(/seat cc3 has no Claude config dir in \[credentials.seats\]/);
  });
  it("seat_dirs and [credentials.seats] merge; the same seat with two dirs is a config error", () => {
    const c = parseRuntimesToml(`[credentials]\nseat_dirs = { cc = "/a" }\n[credentials.seats]\ncc2 = "/b"\n`, "t", "/home/u");
    expect(c.credentials.seats).toEqual({ cc: "/a", cc2: "/b" });
    expect(() => parseRuntimesToml(`[credentials]\nseat_dirs = { cc = "/a" }\n[credentials.seats]\ncc = "/b"\n`, "t", "/home/u")).toThrow(/seat cc has one dir in \[credentials.seats\] and another in seat_dirs/);
  });
  it("one dir claimed by two seats is a config error", () => {
    expect(() => parseRuntimesToml(`[credentials]\nseat_dirs = { cc = "/a", cc2 = "/a" }\n`, "t", "/home/u")).toThrow(/one config dir is one seat/);
  });
});
