/**
 * 2026-09-30: pi runtimes with a provider parameter. The pi harness used to
 * hard-code `--provider gufo`; a runtime table now names its provider and
 * the model resolves against that provider's allowlist.
 *
 * 2026-10-10: the pinned per-provider defaults (PI_DEFAULT_MODEL) are gone. The
 * model is the catalog's, and a provider with no entry is parked: refused at
 * the route, never dialled. The openrouter-free lane ships parked.
 */
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { piAgentModelsJson, RunnerBackend } from "../src/backend.ts";
import { parseRuntimesToml, seatOf } from "../src/config.ts";
import { invocationFor, isPiProvider, piInvocation, PI_PROVIDERS } from "../src/harness.ts";
import type { Job, ProcessJob, Runner } from "../src/job.ts";
import { DEFAULT_MODEL_ALLOWLIST, resolveModel } from "../src/models.ts";
import { tmp } from "./helpers.ts";

/** The runtimes the coordinator's dotfiles render for the overnight run (modules/substrate.nix). */
const TOML = `
default = "opus"
allow = ["opus", "gufo", "qwen", "openrouter", "openrouter-free"]
[seats]
claude = "cc2"
pi = "gufo"
[credentials]
claude = "/home/t/.claude-work"
[credentials.seats]
cc2 = "/home/t/.claude-work"
[runtime.opus]
type = "host"
harness = "claude"
seat = "cc2"
[runtime.gufo]
type = "host"
harness = "pi"
seat = "gufo"
[runtime.qwen]
type = "host"
harness = "pi"
provider = "qwen-token-plan"
seat = "pi-qwencloud"
[runtime.openrouter]
type = "host"
harness = "pi"
provider = "openrouter"
seat = "openrouter"
[runtime.openrouter-free]
type = "host"
harness = "pi"
provider = "openrouter-free"
seat = "openrouter-free"
`;

const argvTail = (argv: readonly string[]) => argv.slice(0, 8);

describe("pi harness argv per provider", () => {
  it("the retired provider is rejected instead of aliased onto Gufo", () => {
    expect(isPiProvider("gufo")).toBe(true);
    expect(isPiProvider("halogen")).toBe(false);
    expect(() => parseRuntimesToml(`default = "old"\n[runtime.old]\ntype = "host"\nharness = "pi"\nprovider = "halogen"\n`, "t")).toThrow();
  });
  it("gufo: --provider gufo --model <the catalog's id>; no session unless a dir is given", () => {
    expect(piInvocation({ prompt: "p", model: "qwen3.8-flash-next" }).argv).toEqual(["pi", "-p", "--no-session", "--provider", "gufo", "--model", "qwen3.8-flash-next", "--mode", "text"]);
  });

  it("qwen: pi -p --session-dir <job dir> --provider qwen-token-plan --model qwen3.8-max", () => {
    expect(piInvocation({ prompt: "p", piProvider: "qwen-token-plan", model: "qwen3.8-max", piSessionDir: "/s/pi-agent/sessions" }).argv.slice(0, 9)).toEqual(["pi", "-p", "--session-dir", "/s/pi-agent/sessions", "--provider", "qwen-token-plan", "--model", "qwen3.8-max", "--mode"]);
  });

  it("openrouter: --provider openrouter --model <catalog id>; the free lane is the same pi provider; no model is an error, never a pinned default", () => {
    expect(argvTail(piInvocation({ prompt: "p", piProvider: "openrouter", model: "minimax/minimax-m3" }).argv)).toEqual(["pi", "-p", "--no-session", "--provider", "openrouter", "--model", "minimax/minimax-m3", "--mode"]);
    const free = invocationFor("pi", { prompt: "p", piProvider: "openrouter-free", model: "stealth/new-one" });
    expect(argvTail(free.argv)).toEqual(["pi", "-p", "--no-session", "--provider", "openrouter", "--model", "stealth/new-one", "--mode"]);
    // The prompt goes on stdin, never in argv; no credential is in argv or env.
    expect(free.stdin).toBe("p");
    expect(free.env).toBeUndefined();
    expect(() => piInvocation({ prompt: "p", piProvider: "openrouter-free" })).toThrow(/no model for provider openrouter-free/);
    // A job-scoped agent dir rides in the env, nothing else.
    expect(piInvocation({ prompt: "p", model: "m", piAgentDir: "/s/pi-agent" }).env).toEqual({ PI_CODING_AGENT_DIR: "/s/pi-agent" });
  });

  it("each provider maps to its seat and the seat provider its reading carries", () => {
    expect(PI_PROVIDERS["qwen-token-plan"]).toMatchObject({ seat: "pi-qwencloud", seatProvider: "qwen" });
    expect(PI_PROVIDERS.openrouter).toMatchObject({ seat: "openrouter", seatProvider: "openrouter" });
    expect(PI_PROVIDERS["openrouter-free"]).toMatchObject({ pi: "openrouter", seat: "openrouter-free", seatProvider: "openrouter" });
  });
});

describe("the model allowlist is per pi provider", () => {
  it("an allowlisted id or alias runs; anything else runs the provider default, visibly", () => {
    expect(resolveModel(DEFAULT_MODEL_ALLOWLIST, "pi", "anthropic/claude-sonnet-5.5", "openrouter")).toEqual({ id: "anthropic/claude-sonnet-5.5" });
    expect(resolveModel(DEFAULT_MODEL_ALLOWLIST, "pi", "minimax", "openrouter")).toEqual({ id: "minimax/minimax-m3", requested: "minimax" });
    expect(resolveModel(DEFAULT_MODEL_ALLOWLIST, "pi", "openai/gpt-6.1-sol", "openrouter")).toEqual({ id: "deepseek/deepseek-v4-pro", requested: "openai/gpt-6.1-sol" });
    // A Gufo id never runs on OpenRouter, nor an OpenRouter id on Gufo.
    expect(resolveModel(DEFAULT_MODEL_ALLOWLIST, "pi", "qwen3.8-flash-next", "openrouter").id).toBe("deepseek/deepseek-v4-pro");
    expect(resolveModel(DEFAULT_MODEL_ALLOWLIST, "pi", "deepseek/deepseek-v4-pro", undefined).id).toBe("qwen3.8-flash-next");
    // The free lane ships PARKED (2026-10-10): no entry, so no id, whatever the call asks for.
    expect(resolveModel(DEFAULT_MODEL_ALLOWLIST, "pi", "anthropic/claude-sonnet-5.5", "openrouter-free").id).toBeUndefined();
    expect(resolveModel(DEFAULT_MODEL_ALLOWLIST, "pi", undefined, "openrouter-free").id).toBeUndefined();
  });

  it("one default per (pi, provider); provider only on pi entries", () => {
    expect(() => parseRuntimesToml(`[[models]]\nid = "a"\nharness = "pi"\nprovider = "openrouter"\ndefault = true\n[[models]]\nid = "b"\nharness = "pi"\nprovider = "openrouter"\ndefault = true\n`, "t")).toThrow(/2 defaults/);
    expect(() => parseRuntimesToml(`[[models]]\nid = "a"\nharness = "pi"\ndefault = true\n[[models]]\nid = "b"\nharness = "pi"\nprovider = "openrouter"\ndefault = true\n`, "t")).not.toThrow();
    expect(() => parseRuntimesToml(`[[models]]\nid = "a"\nharness = "claude"\nprovider = "openrouter"\n`, "t")).toThrow(/only a pi or dsh entry/);
  });
});

describe("runtime tables with a provider", () => {
  it("routes each runtime to its provider, model and seat", () => {
    const c = parseRuntimesToml(TOML, "t");
    const b = new RunnerBackend(c, { jobsRoot: tmp(), runId: "r" });
    expect(b.route({ opts: { runtime: "qwen" }, phase: undefined })).toMatchObject({ harness: "pi", provider: "qwen-token-plan", model: "qwen3.8-max", seat: "pi-qwencloud", seatProvider: "qwen" });
    expect(b.route({ opts: { runtime: "openrouter", model: "qwen/qwen3.8-max-0902" }, phase: undefined })).toMatchObject({ provider: "openrouter", model: "qwen/qwen3.8-max-0902", seat: "openrouter", seatProvider: "openrouter" });
    // Parked: refused at the route (the CONWIP turns a route throw into an immediate "conwip refused the route" null).
    expect(() => b.route({ opts: { runtime: "openrouter-free" }, phase: undefined })).toThrow(/runtime openrouter-free: no model configured for pi provider openrouter-free \(the lane is parked\)/);
    expect(b.route({ opts: { runtime: "gufo" }, phase: undefined })).toMatchObject({ provider: "gufo", model: "qwen3.8-flash-next", seat: "gufo", seatProvider: "gufo" });
    // A seat alone picks the one runtime that spends it (selection; the parked route itself is refused above).
    expect(b.select({ opts: { seat: "openrouter-free" }, phase: undefined }).name).toBe("openrouter-free");
  });

  it("a provider table with no seat spends its provider's own seat, never [seats].pi", () => {
    const c = parseRuntimesToml(`default = "q"\n[seats]\npi = "gufo"\n[runtime.q]\ntype = "host"\nharness = "pi"\nprovider = "qwen-token-plan"\n`, "t");
    expect(seatOf(c, c.runtimes["q"]!)).toBe("pi-qwencloud");
  });

  it("refuses a provider on another harness, and a cloud provider inside a sandbox", () => {
    expect(() => parseRuntimesToml(`default = "x"\n[runtime.x]\ntype = "host"\nharness = "claude"\nprovider = "openrouter"\n`, "t")).toThrow(/pi or dsh harness only/);
    expect(() => parseRuntimesToml(`default = "x"\n[runtime.x]\ntype = "gvisor"\nrunsc = "/bin/runsc"\nharness = "pi"\nprovider = "openrouter"\n`, "t")).toThrow(/host's pi models.json/);
    expect(() => parseRuntimesToml(`default = "x"\n[runtime.x]\ntype = "host"\nharness = "pi"\nprovider = "anthropic"\n`, "t")).toThrow();
  });

  it("the runner is reached with the provider's argv", async () => {
    const c = parseRuntimesToml(TOML, "t");
    const seen: Job[] = [];
    const runner: Runner = {
      name: "fake",
      refuses: () => undefined,
      run: async (job: Job) => {
        seen.push(job);
        return { exitCode: 0, stdout: "ok", stderr: "", durationMs: 1, timedOut: false };
      },
    } as unknown as Runner;
    const shadows = tmp();
    const b = new RunnerBackend(c, { jobsRoot: tmp(), runId: "r", runners: { openrouter: runner }, seatShadowRoot: shadows });
    const out = await b.run({ index: 0, attempt: 1, key: "k", prompt: "hi", opts: { runtime: "openrouter", model: "minimax/minimax-m3" }, phase: undefined } as never);
    expect(out.error).toBeUndefined();
    const job = seen[0] as ProcessJob;
    // The session is saved in the job's own shadow (CMP-2), a catalogued model gets no agent dir override.
    expect(job.argv.slice(0, 8)).toEqual(["pi", "-p", "--session-dir", join(shadows, "r-0-a1", "pi-agent", "sessions"), "--provider", "openrouter", "--model", "minimax/minimax-m3"]);
    expect(job.env?.["PI_CODING_AGENT_DIR"]).toBeUndefined();
    // The shadow is gone once the job is over.
    expect(existsSync(join(shadows, "r-0-a1"))).toBe(false);
  });
});

/** A runner that answers "ok" and records its jobs. */
const recorder = () => {
  const seen: ProcessJob[] = [];
  const r: Runner = {
    name: "fake",
    refuses: () => undefined,
    run: async (job: Job) => {
      seen.push(job as ProcessJob);
      // What pi would leave behind: a session file in --session-dir.
      const dir = (job as ProcessJob).argv[3]!;
      writeFileSync(join(dir, "s1.jsonl"), '{"type":"message","message":{"provider":"qwen-token-plan","usage":{"input":1,"output":2}}}\n');
      return { exitCode: 0, stdout: "ok", stderr: "", durationMs: 1, timedOut: false };
    },
  } as unknown as Runner;
  return { seen, r };
};

describe("the model catalog is runtime data (models_file, 2026-10-10)", () => {
  const withFile = (text: string) => {
    const d = tmp();
    const file = join(d, "models.toml");
    writeFileSync(file, text);
    const c = parseRuntimesToml(`models_file = "${file}"\n${TOML}`, "t");
    return { c, file, d };
  };
  const FREE = `[[models]]\nid = "qwen3.8-flash-next"\nharness = "pi"\ndefault = true\n[[models]]\nid = "stealth/new-bunny"\nharness = "pi"\nprovider = "openrouter-free"\ndefault = true\n[models.pi]\nname = "New Bunny (stealth, free)"\nreasoning = true\ninput = ["text", "image"]\ncontext_window = 1000000\nmax_tokens = 524288\n`;
  const PARKED = `[[models]]\nid = "qwen3.8-flash-next"\nharness = "pi"\ndefault = true\n`;

  it("a set models_file must exist and parse at load (the puller fails at start, not on its first call)", () => {
    expect(() => parseRuntimesToml(`models_file = "/nonexistent/models.toml"\n${TOML}`, "t")).toThrow(/models file \/nonexistent\/models.toml does not exist/);
    const d = tmp();
    writeFileSync(join(d, "m.toml"), `[[models]]\nid = "a"\nharness = "claude"\nceilings = { five_hour = 150 }\n`);
    expect(() => parseRuntimesToml(`models_file = "${join(d, "m.toml")}"\n${TOML}`, "t")).toThrow(/ceiling five_hour/);
    expect(() => parseRuntimesToml(`models_file = "relative.toml"\n${TOML}`, "t")).toThrow(/must be absolute/);
  });

  it("an edit is live on the next call: park, activate, park again, with no new backend", () => {
    const { c, file } = withFile(PARKED);
    const b = new RunnerBackend(c, { jobsRoot: tmp(), runId: "r", seatShadowRoot: tmp() });
    expect(() => b.route({ opts: { runtime: "openrouter-free" }, phase: undefined })).toThrow(new RegExp(`parked.*${file.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}`));
    writeFileSync(file, FREE);
    expect(b.route({ opts: { runtime: "openrouter-free" }, phase: undefined })).toMatchObject({ provider: "openrouter-free", model: "stealth/new-bunny", seat: "openrouter-free" });
    writeFileSync(file, PARKED + "\n# parked again\n");
    expect(() => b.route({ opts: { runtime: "openrouter-free" }, phase: undefined })).toThrow(/parked/);
  });

  it("a file that stops parsing refuses every call with its own error (fail closed, never a silent fallback)", async () => {
    const { c, file } = withFile(PARKED);
    const b = new RunnerBackend(c, { jobsRoot: tmp(), runId: "r", seatShadowRoot: tmp(), runners: { gufo: recorder().r } });
    writeFileSync(file, "[[models]\nid = ");
    expect(() => b.route({ opts: { runtime: "gufo" }, phase: undefined })).toThrow(/TOML/);
    const out = await b.run({ index: 0, attempt: 1, key: "k", prompt: "hi", opts: { runtime: "gufo" }, phase: undefined } as never);
    expect(out.error).toMatch(/runtime gufo refused: .*TOML/);
  });

  it("a parked provider is refused before dispatch in run() too, with the same reason", async () => {
    const { c } = withFile(PARKED);
    const rec = recorder();
    const b = new RunnerBackend(c, { jobsRoot: tmp(), runId: "r", seatShadowRoot: tmp(), runners: { "openrouter-free": rec.r } });
    const out = await b.run({ index: 0, attempt: 1, key: "k", prompt: "hi", opts: { runtime: "openrouter-free" }, phase: undefined } as never);
    expect(out.error).toMatch(/runtime openrouter-free refused: no model configured for pi provider openrouter-free \(the lane is parked\)/);
    expect(rec.seen).toHaveLength(0);
  });

  it("an uncatalogued model rides in a job-scoped agent dir: the host's models.json as data plus the one model; its session is archived", async () => {
    const { c } = withFile(FREE);
    const hostAgent = tmp();
    // The host file's key is a `!cat` REFERENCE; it must come through as the same string, never resolved.
    writeFileSync(join(hostAgent, "models.json"), JSON.stringify({ providers: { openrouter: { apiKey: "!cat /run/agenix/openrouter-token" }, gufo: { api: "openai-completions", apiKey: "gufo-no-auth", models: [{ id: "qwen3.8-flash-next" }] } } }));
    const rec = recorder();
    const shadows = tmp();
    const transcripts = tmp();
    let agentJson: string | undefined;
    const spy: Runner = { ...rec.r, run: async (job: Job) => { agentJson = readFileSync(join((job as ProcessJob).env!["PI_CODING_AGENT_DIR"]!, "models.json"), "utf8"); return rec.r.run(job, undefined as never); } } as unknown as Runner;
    const b = new RunnerBackend(c, { jobsRoot: tmp(), runId: "r", seatShadowRoot: shadows, transcriptRoot: transcripts, piHostAgentDir: hostAgent, runners: { "openrouter-free": spy } });
    const out = await b.run({ index: 0, attempt: 1, key: "k", prompt: "hi", opts: { runtime: "openrouter-free" }, phase: undefined } as never);
    expect(out.error).toBeUndefined();
    const job = rec.seen[0]!;
    expect(job.argv.slice(4, 8)).toEqual(["--provider", "openrouter", "--model", "stealth/new-bunny"]);
    expect(job.env!["PI_CODING_AGENT_DIR"]).toBe(join(shadows, "r-0-a1", "pi-agent"));
    const doc = JSON.parse(agentJson!) as { providers: Record<string, { apiKey?: string; models?: { id: string; name: string; baseUrl?: string; contextWindow?: number }[] }> };
    expect(doc.providers["openrouter"]!.apiKey).toBe("!cat /run/agenix/openrouter-token");
    expect(doc.providers["openrouter"]!.models).toEqual([expect.objectContaining({ id: "stealth/new-bunny", name: "New Bunny (stealth, free)", api: "openai-completions", baseUrl: "https://openrouter.ai/api/v1", reasoning: true, contextWindow: 1000000, maxTokens: 524288 })]);
    expect(doc.providers["gufo"]!.models).toEqual([{ id: "qwen3.8-flash-next" }]);
    // The session pi wrote into the job's shadow is archived under the transcripts root (what the seats oracle reads).
    const archived = join(transcripts, "r", "r-0-a1", "pi-s1.jsonl");
    expect(existsSync(archived)).toBe(true);
    expect(readFileSync(archived, "utf8")).toContain("qwen-token-plan");
    expect(existsSync(join(shadows, "r-0-a1"))).toBe(false);
  });

  it("piAgentModelsJson upserts by id and tolerates a missing or unparsable host file", () => {
    const entry = { id: "x/y", harness: "pi" as const, provider: "openrouter-free" as const, pi: { name: "Y" } };
    const fresh = JSON.parse(piAgentModelsJson(undefined, "openrouter-free", entry)) as { providers: Record<string, { models: { id: string }[] }> };
    expect(fresh.providers["openrouter"]!.models.map((m) => m.id)).toEqual(["x/y"]);
    const replaced = JSON.parse(piAgentModelsJson(JSON.stringify({ providers: { openrouter: { models: [{ id: "x/y", name: "old" }, { id: "keep" }] } } }), "openrouter-free", entry)) as typeof fresh;
    expect(replaced.providers["openrouter"]!.models.map((m) => m.id)).toEqual(["keep", "x/y"]);
    expect(JSON.parse(piAgentModelsJson("not json", "openrouter-free", entry)).providers.openrouter.models).toHaveLength(1);
    mkdirSync(tmp(), { recursive: true });
  });
});
