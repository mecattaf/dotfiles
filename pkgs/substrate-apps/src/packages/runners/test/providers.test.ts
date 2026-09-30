/**
 * 2026-09-30: pi runtimes with a provider parameter. The pi harness used to
 * hard-code `--provider halogen`; a runtime table now names its provider and
 * the model resolves against that provider's allowlist.
 */
import { describe, expect, it } from "vitest";
import { RunnerBackend } from "../src/backend.ts";
import { parseRuntimesToml, seatOf } from "../src/config.ts";
import { invocationFor, piInvocation, PI_PROVIDERS } from "../src/harness.ts";
import type { Job, ProcessJob, Runner } from "../src/job.ts";
import { DEFAULT_MODEL_ALLOWLIST, resolveModel } from "../src/models.ts";
import { tmp } from "./helpers.ts";

/** The runtimes the coordinator's dotfiles render for the overnight run (modules/substrate.nix). */
const TOML = `
default = "opus"
allow = ["opus", "halogen", "qwen", "openrouter", "openrouter-free"]
[seats]
claude = "cc2"
pi = "halogen"
[credentials]
claude = "/home/t/.claude-work"
[credentials.seats]
cc2 = "/home/t/.claude-work"
[runtime.opus]
type = "host"
harness = "claude"
seat = "cc2"
[runtime.halogen]
type = "host"
harness = "pi"
seat = "halogen"
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
  it("halogen is unchanged: --provider halogen --model halogen-qwen3.8-flash-next", () => {
    expect(piInvocation({ prompt: "p" }).argv).toEqual(["pi", "-p", "--no-session", "--provider", "halogen", "--model", "halogen-qwen3.8-flash-next", "--mode", "text"]);
  });

  it("qwen: pi -p --no-session --provider qwen-token-plan --model qwen3.8-max", () => {
    expect(argvTail(piInvocation({ prompt: "p", piProvider: "qwen-token-plan" }).argv)).toEqual(["pi", "-p", "--no-session", "--provider", "qwen-token-plan", "--model", "qwen3.8-max", "--mode"]);
  });

  it("openrouter: --provider openrouter --model <allowlisted id>; openrouter-free pins the stealth model", () => {
    expect(argvTail(piInvocation({ prompt: "p", piProvider: "openrouter", model: "minimax/minimax-m3" }).argv)).toEqual(["pi", "-p", "--no-session", "--provider", "openrouter", "--model", "minimax/minimax-m3", "--mode"]);
    expect(argvTail(piInvocation({ prompt: "p", piProvider: "openrouter" }).argv)).toContain("deepseek/deepseek-v4-pro");
    const free = invocationFor("pi", { prompt: "p", piProvider: "openrouter-free" });
    expect(argvTail(free.argv)).toEqual(["pi", "-p", "--no-session", "--provider", "openrouter", "--model", "stealth/space-bunny-alpha", "--mode"]);
    // The prompt goes on stdin, never in argv; no credential is in argv or env.
    expect(free.stdin).toBe("p");
    expect(free.env).toBeUndefined();
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
    // A Halogen id never runs on OpenRouter, nor an OpenRouter id on Halogen.
    expect(resolveModel(DEFAULT_MODEL_ALLOWLIST, "pi", "halogen-qwen3.8-flash-next", "openrouter").id).toBe("deepseek/deepseek-v4-pro");
    expect(resolveModel(DEFAULT_MODEL_ALLOWLIST, "pi", "deepseek/deepseek-v4-pro", undefined).id).toBe("halogen-qwen3.8-flash-next");
    // The free runtime cannot be talked into a paid model.
    expect(resolveModel(DEFAULT_MODEL_ALLOWLIST, "pi", "anthropic/claude-sonnet-5.5", "openrouter-free").id).toBe("stealth/space-bunny-alpha");
  });

  it("one default per (pi, provider); provider only on pi entries", () => {
    expect(() => parseRuntimesToml(`[[models]]\nid = "a"\nharness = "pi"\nprovider = "openrouter"\ndefault = true\n[[models]]\nid = "b"\nharness = "pi"\nprovider = "openrouter"\ndefault = true\n`, "t")).toThrow(/2 defaults/);
    expect(() => parseRuntimesToml(`[[models]]\nid = "a"\nharness = "pi"\ndefault = true\n[[models]]\nid = "b"\nharness = "pi"\nprovider = "openrouter"\ndefault = true\n`, "t")).not.toThrow();
    expect(() => parseRuntimesToml(`[[models]]\nid = "a"\nharness = "claude"\nprovider = "openrouter"\n`, "t")).toThrow(/only a pi entry/);
  });
});

describe("runtime tables with a provider", () => {
  it("routes each runtime to its provider, model and seat", () => {
    const c = parseRuntimesToml(TOML, "t");
    const b = new RunnerBackend(c, { jobsRoot: tmp(), runId: "r" });
    expect(b.route({ opts: { runtime: "qwen" }, phase: undefined })).toMatchObject({ harness: "pi", provider: "qwen-token-plan", model: "qwen3.8-max", seat: "pi-qwencloud", seatProvider: "qwen" });
    expect(b.route({ opts: { runtime: "openrouter", model: "qwen/qwen3.8-max-0902" }, phase: undefined })).toMatchObject({ provider: "openrouter", model: "qwen/qwen3.8-max-0902", seat: "openrouter", seatProvider: "openrouter" });
    expect(b.route({ opts: { runtime: "openrouter-free" }, phase: undefined })).toMatchObject({ provider: "openrouter-free", model: "stealth/space-bunny-alpha", seat: "openrouter-free" });
    expect(b.route({ opts: { runtime: "halogen" }, phase: undefined })).toMatchObject({ provider: "halogen", model: "halogen-qwen3.8-flash-next", seat: "halogen", seatProvider: "halogen" });
    // A seat alone picks the one runtime that spends it.
    expect(b.route({ opts: { seat: "openrouter-free" }, phase: undefined }).selection.name).toBe("openrouter-free");
  });

  it("a provider table with no seat spends its provider's own seat, never [seats].pi", () => {
    const c = parseRuntimesToml(`default = "q"\n[seats]\npi = "halogen"\n[runtime.q]\ntype = "host"\nharness = "pi"\nprovider = "qwen-token-plan"\n`, "t");
    expect(seatOf(c, c.runtimes["q"]!)).toBe("pi-qwencloud");
  });

  it("refuses a provider on another harness, and a cloud provider inside a sandbox", () => {
    expect(() => parseRuntimesToml(`default = "x"\n[runtime.x]\ntype = "host"\nharness = "claude"\nprovider = "openrouter"\n`, "t")).toThrow(/pi harness only/);
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
    const b = new RunnerBackend(c, { jobsRoot: tmp(), runId: "r", runners: { openrouter: runner } });
    const out = await b.run({ index: 0, attempt: 1, key: "k", prompt: "hi", opts: { runtime: "openrouter", model: "minimax/minimax-m3" }, phase: undefined } as never);
    expect(out.error).toBeUndefined();
    const argv = (seen[0] as ProcessJob).argv;
    expect(argv.slice(0, 7)).toEqual(["pi", "-p", "--no-session", "--provider", "openrouter", "--model", "minimax/minimax-m3"]);
  });
});
