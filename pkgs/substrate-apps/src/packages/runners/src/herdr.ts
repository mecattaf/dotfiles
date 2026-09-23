/**
 * `herdr`: the job runs under a herdr server, speaking its NDJSON socket.
 *
 * Two modes:
 *
 * - `action` (default). A plugin action. herdr runs the plugin's one command,
 *   `bin/herdr-job.mjs`, which reads the job spec path from the invocation
 *   context and exits with the job's code; herdr's plugin log then reports
 *   `exit_code`, `stdout` and `stderr` natively (finding H1, MEASURED by both
 *   verifiers). No pane is created and no pane is touched.
 * - `pane`. A visible pane in a workspace this runner creates unfocused and
 *   closes afterwards. A pane has no exit status, so the job prints a sentinel
 *   `AXC-DONE-<id>-rc=<n>` and the runner waits for it; stdout and stderr come
 *   from files in the job dir. This is the watched mode, not the default.
 *
 * Rules this adapter keeps, because the fleet's live herdr hosts Tom's agents:
 * it only ever addresses workspaces it created; it never restarts, stops or
 * reconfigures a server; and it links its plugin only when `autoLink` is set
 * (an isolated test server) or when the user runs the explicit link command.
 */
import { connect } from "node:net";
import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { refuseCommon, refusal, type Job, type ProcessJob, type Runner, type RunResult } from "./job.ts";
import { procStartTicks, sameProcess, shq } from "./proc.ts";
import { DEFAULT_TIMEOUT_MS } from "./host.ts";

export const DEFAULT_PLUGIN = "substrate-runner";
export const ENTRY = resolve(dirname(fileURLToPath(import.meta.url)), "../bin/herdr-job.mjs");

export interface HerdrOptions {
  readonly socket?: string;
  readonly mode?: "action" | "pane";
  readonly plugin?: string;
  readonly autoLink?: boolean;
  readonly timeoutMs?: number;
  /** Where the generated plugin lives. Default `~/.local/state/substrate/herdr-plugin`. */
  readonly pluginDir?: string;
  /** node binary the plugin command runs. Default this process's. */
  readonly node?: string;
  /** Poll interval for the plugin log. */
  readonly pollMs?: number;
  /** After a lost invoke answer, how long to look for the job's own trace before calling it a refusal. Default 3000 ms. */
  readonly startGraceMs?: number;
}

export const defaultSocket = (): string =>
  process.env.HERDR_SOCKET_PATH ?? join(process.env.XDG_CONFIG_HOME ?? join(homedir(), ".config"), "herdr/herdr.sock");

export class HerdrError extends Error {
  override readonly name = "HerdrError";
  constructor(
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

let seq = 0;
/** One request, one response line. herdr answers each request on its own connection. */
export function herdrRpc(socket: string, method: string, params: unknown, timeoutMs = 10000): Promise<Record<string, unknown>> {
  return new Promise((resolveP, reject) => {
    const id = `axc:${process.pid}:${++seq}`;
    const c = connect(socket);
    let buf = "";
    const t = setTimeout(() => {
      c.destroy();
      reject(new HerdrError("timeout", `${method}: no answer in ${timeoutMs} ms`));
    }, timeoutMs);
    c.on("error", (e) => {
      clearTimeout(t);
      reject(new HerdrError("socket", `${method}: ${e.message}`));
    });
    // A connection closed before its answer line is an error NOW, not after the
    // full timeout (successor review 2026-09-23). A settled promise ignores it.
    c.on("close", () => {
      clearTimeout(t);
      if (buf.indexOf("\n") < 0) reject(new HerdrError("closed", `${method}: connection closed before an answer`));
    });
    c.on("data", (d) => {
      buf += d.toString("utf8");
      const nl = buf.indexOf("\n");
      if (nl < 0) return;
      clearTimeout(t);
      c.end();
      let msg: { result?: Record<string, unknown>; error?: { code: string; message: string } };
      try {
        msg = JSON.parse(buf.slice(0, nl));
      } catch (e) {
        reject(new HerdrError("parse", `${method}: ${(e as Error).message}`));
        return;
      }
      if (msg.error) reject(new HerdrError(msg.error.code, `${method}: ${msg.error.message}`));
      else resolveP(msg.result ?? {});
    });
    c.write(JSON.stringify({ id, method, params }) + "\n");
  });
}

/** The plugin manifest: one action, one fixed command. The job arrives as context, never as argv. */
export function pluginManifest(pluginId: string, node: string, entry: string): string {
  const q = (s: string) => JSON.stringify(s);
  return [
    `id = ${q(pluginId)}`,
    `name = ${q(pluginId)}`,
    `version = "0.1.0"`,
    `min_herdr_version = "0.9.0"`,
    `description = "substrate runner: runs one job spec per invocation"`,
    `platforms = ["linux"]`,
    ``,
    `[[actions]]`,
    `id = "job"`,
    `title = "substrate job"`,
    `command = [${q(node)}, ${q(entry)}]`,
    `contexts = ["global", "selection"]`,
    ``,
  ].join("\n");
}

/** Write the plugin and link it into the server at `socket`. Explicit: this changes the server's plugin set. */
export async function linkPlugin(socket: string, o: Pick<HerdrOptions, "plugin" | "pluginDir" | "node"> = {}): Promise<string> {
  const pluginId = o.plugin ?? DEFAULT_PLUGIN;
  const dir = o.pluginDir ?? join(homedir(), ".local/state/substrate/herdr-plugin");
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, "herdr-plugin.toml"), pluginManifest(pluginId, o.node ?? process.execPath, ENTRY));
  await herdrRpc(socket, "plugin.link", { path: dir, enabled: true });
  return dir;
}

interface PluginLog {
  log_id: string;
  status: string;
  exit_code?: number;
  stdout?: string;
  stderr?: string;
}

/** Files herdr-job.mjs writes; a copy left by an earlier start of the same job id must never be read as this one's. */
const JOB_OUTPUTS = [".herdr-rc", ".herdr-pid", ".herdr-pstart", ".herdr-stdout", ".herdr-stderr"];

const specFor = (job: ProcessJob, timeoutMs: number) => {
  for (const f of JOB_OUTPUTS) rmSync(join(job.jobDir, f), { force: true });
  const stdinFile = join(job.jobDir, ".herdr-stdin");
  writeFileSync(stdinFile, job.stdin ?? "");
  // The herdr server's own environment (a systemd unit's) may not have the
  // caller's PATH, so the caller's PATH travels with the job.
  const env = { PATH: process.env.PATH ?? "/run/current-system/sw/bin", ...(job.env ?? {}) };
  const spec = { argv: job.argv, env, jobDir: job.jobDir, stdinFile, timeoutMs, runnerPid: process.pid, runnerStart: procStartTicks(process.pid) };
  const path = join(job.jobDir, ".herdr-job.json");
  writeFileSync(path, JSON.stringify(spec));
  return path;
};

const readIf = (p: string) => (existsSync(p) ? readFileSync(p, "utf8") : undefined);
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

export function herdrRunner(name: string, o: HerdrOptions = {}): Runner {
  const socket = o.socket ?? defaultSocket();
  const pluginId = o.plugin ?? DEFAULT_PLUGIN;
  const mode = o.mode ?? "action";
  const pollMs = o.pollMs ?? 200;
  const refuses = (job: Job): string | undefined => {
    const c = refuseCommon(job);
    if (c) return c;
    if (job.kind !== "process") return `${name} runs process jobs only`;
    for (const m of job.mounts ?? []) {
      if (m.source !== m.target) return `herdr runs on the host; it cannot mount ${m.source} at ${m.target}`;
    }
    if (!existsSync(socket)) return `no herdr socket at ${socket}`;
    return undefined;
  };

  const ensurePlugin = async (): Promise<string | undefined> => {
    try {
      const r = await herdrRpc(socket, "plugin.action.list", { plugin_id: pluginId });
      const actions = (r.actions as { action_id: string }[] | undefined) ?? [];
      if (actions.some((a) => a.action_id === "job")) return undefined;
    } catch (e) {
      if (!(e instanceof HerdrError) || e.code !== "plugin_not_found") return (e as Error).message;
    }
    if (!o.autoLink) {
      return `herdr plugin ${pluginId} is not linked on ${socket}; link it once with: substrate-runners herdr-link --socket ${socket}`;
    }
    try {
      await linkPlugin(socket, o);
      return undefined;
    } catch (e) {
      return `linking ${pluginId}: ${(e as Error).message}`;
    }
  };

  const runAction = async (job: ProcessJob, timeoutMs: number, signal?: AbortSignal): Promise<RunResult> => {
    const missing = await ensurePlugin();
    if (missing) return refusal(name, job, missing);
    const specPath = specFor(job, timeoutMs);
    const t0 = performance.now();
    const startedAtMs = Date.now();
    /** The rc file, only if written by THIS invocation (mtime after it began). */
    const freshRc = (): number | undefined => {
      const p = join(job.jobDir, ".herdr-rc");
      try {
        if (statSync(p).mtimeMs < startedAtMs - 1000) return undefined;
      } catch {
        return undefined;
      }
      const rc = (readIf(p) ?? "").trim();
      return /^\d+$/.test(rc) ? Number(rc) : undefined;
    };
    let inv: Record<string, unknown> | undefined;
    let invokeError: string | undefined;
    try {
      inv = await herdrRpc(socket, "plugin.action.invoke", {
        action_id: "job",
        plugin_id: pluginId,
        context: { selected_text: specPath, correlation_id: job.id, invocation_source: "api" },
      });
    } catch (e) {
      invokeError = (e as Error).message;
    }
    const logId = (inv?.log as { log_id?: string } | undefined)?.log_id;
    if (!logId) {
      // The invoke may have started the job before the answer was lost: outcome
      // unknown, not a refusal (successor review 2026-09-23). Look for the job's
      // own trace for a bounded window; only a job that provably never started
      // is a refusal.
      const why = invokeError ?? `plugin.action.invoke returned no log id: ${JSON.stringify(inv).slice(0, 300)}`;
      const lookUntil = Date.now() + (o.startGraceMs ?? 3000);
      let started = false;
      while (Date.now() < lookUntil && !signal?.aborted) {
        if (existsSync(join(job.jobDir, ".herdr-pid")) || freshRc() !== undefined) {
          started = true;
          break;
        }
        await sleep(pollMs);
      }
      if (!started) return refusal(name, job, `${why}; the job never started`);
      const deadline = Date.now() + timeoutMs + 10000;
      let rc = freshRc();
      while (rc === undefined && Date.now() < deadline && !signal?.aborted) {
        await sleep(pollMs);
        rc = freshRc();
      }
      const durationMs = Math.round(performance.now() - t0);
      if (rc === undefined) {
        const pid = Number(readIf(join(job.jobDir, ".herdr-pid")) ?? NaN);
        if (Number.isInteger(pid) && pid > 0) {
          try {
            process.kill(-pid, "SIGKILL");
          } catch {
            /* already gone */
          }
        }
        return { runtime: name, jobId: job.id, exitCode: 124, stdout: "", stderr: `[runner: ${why}; the job started and did not finish by the deadline]`, durationMs, timedOut: true, detail: { mode, invoke: "lost", outcome: "unknown" } };
      }
      return {
        runtime: name,
        jobId: job.id,
        exitCode: rc,
        stdout: readIf(join(job.jobDir, ".herdr-stdout")) ?? "",
        stderr: readIf(join(job.jobDir, ".herdr-stderr")) ?? "",
        durationMs,
        detail: { mode, invoke: "lost", followed: "job dir" },
      };
    }
    const deadline = Date.now() + timeoutMs + 10000;
    let entry: PluginLog | undefined;
    let lastError = "";
    // The job has started: from here a socket error is an outcome, never a refusal.
    while (Date.now() < deadline && !signal?.aborted) {
      try {
        const r = await herdrRpc(socket, "plugin.log.list", { plugin_id: pluginId, limit: 200 });
        entry = ((r.logs as PluginLog[] | undefined) ?? []).find((l) => l.log_id === logId);
        if (entry && entry.status !== "running") break;
        // herdr keeps a bounded log; under load our entry can scroll out. The
        // entry script's rc file is then the record.
        const rc = freshRc();
        if (!entry && rc !== undefined) {
          entry = { log_id: logId, status: "evicted", exit_code: rc };
          break;
        }
      } catch (e) {
        lastError = (e as Error).message;
      }
      await sleep(pollMs);
    }
    const durationMs = Math.round(performance.now() - t0);
    if (!entry || entry.status === "running") {
      const pid = Number(readIf(join(job.jobDir, ".herdr-pid")) ?? NaN);
      if (Number.isInteger(pid) && pid > 0) {
        try {
          process.kill(-pid, "SIGKILL");
        } catch {
          /* already gone */
        }
      }
      return { runtime: name, jobId: job.id, exitCode: 124, stdout: "", stderr: `[runner: herdr log ${logId} not finished at deadline${lastError ? `; last socket error: ${lastError}` : ""}]`, durationMs, timedOut: true, detail: { logId, mode } };
    }
    // herdr's log is the native channel; the job-dir copies are complete even if herdr caps its log.
    const fileOut = readIf(join(job.jobDir, ".herdr-stdout")) ?? "";
    const fileErr = readIf(join(job.jobDir, ".herdr-stderr")) ?? "";
    const stdout = (entry.stdout ?? "").length >= fileOut.length ? (entry.stdout ?? "") : fileOut;
    const stderr = (entry.stderr ?? "").length >= fileErr.length ? (entry.stderr ?? "") : fileErr;
    return {
      runtime: name,
      jobId: job.id,
      exitCode: typeof entry.exit_code === "number" ? entry.exit_code : 1,
      stdout,
      stderr,
      durationMs,
      ...(entry.exit_code === 124 ? { timedOut: true } : {}),
      detail: { logId, mode, status: entry.status },
    };
  };

  /**
   * Follow a job that may be running through its job dir alone (the socket
   * answer was lost): wait for a fresh .herdr-rc until the deadline, then kill
   * the job's group. Always an outcome, never a refusal: the job may have run.
   */
  const followJobDir = async (job: ProcessJob, startedAtMs: number, t0: number, timeoutMs: number, why: string, extra: Record<string, unknown>, signal?: AbortSignal): Promise<RunResult> => {
    const freshRc = (): number | undefined => {
      const p = join(job.jobDir, ".herdr-rc");
      try {
        if (statSync(p).mtimeMs < startedAtMs - 1000) return undefined;
      } catch {
        return undefined;
      }
      const rc = (readIf(p) ?? "").trim();
      return /^\d+$/.test(rc) ? Number(rc) : undefined;
    };
    const deadline = startedAtMs + timeoutMs + 10000;
    let rc = freshRc();
    while (rc === undefined && Date.now() < deadline && !signal?.aborted) {
      await sleep(pollMs);
      rc = freshRc();
    }
    const durationMs = Math.round(performance.now() - t0);
    if (rc === undefined) {
      killJobGroup(job.jobDir);
      return { runtime: name, jobId: job.id, exitCode: 124, stdout: "", stderr: `[runner: ${why}; the job did not finish by the deadline and was killed]`, durationMs, timedOut: true, detail: { mode, ...extra, outcome: "unknown" } };
    }
    return {
      runtime: name,
      jobId: job.id,
      exitCode: rc,
      stdout: readIf(join(job.jobDir, ".herdr-stdout")) ?? "",
      stderr: readIf(join(job.jobDir, ".herdr-stderr")) ?? "",
      durationMs,
      ...(rc === 124 ? { timedOut: true } : {}),
      detail: { mode, ...extra, followed: "job dir", socketError: why },
    };
  };

  /**
   * Pane mode. Only a failure before pane.send_input (workspace.create) may be
   * a refusal: once the input may have reached the pane, a socket error is an
   * outcome, followed through the job dir (successor review r2: a drop on
   * pane.wait_for_output was reported as "nothing ran" and the retry ran the
   * job a second time). A workspace that could not be closed stays in the
   * runner-side record for the restart to close.
   */
  const runPane = async (job: ProcessJob, timeoutMs: number, rec: HerdrRecord | undefined, signal?: AbortSignal): Promise<RunResult> => {
    const specPath = specFor(job, timeoutMs);
    const t0 = performance.now();
    const startedAtMs = Date.now();
    let ws: Record<string, unknown>;
    // The label goes on the record BEFORE create (successor review r4: a lost
    // create answer dropped the record, and the workspace herdr made was never
    // closed; every retry opened another).
    const label = `axc-${job.id}`;
    rec?.update({ label });
    try {
      ws = await herdrRpc(socket, "workspace.create", { cwd: job.jobDir, focus: false, label });
    } catch (e) {
      const swept = await closeByLabel(socket, label);
      if (swept.ok) rec?.done();
      return refusal(name, job, `herdr: ${(e as Error).message}; ${swept.note}`);
    }
    const wsId = (ws.workspace as { workspace_id?: string } | undefined)?.workspace_id;
    const paneId = (ws.root_pane as { pane_id?: string } | undefined)?.pane_id;
    if (!wsId || !paneId) {
      rec?.done();
      return refusal(name, job, `workspace.create returned no ids: ${JSON.stringify(ws).slice(0, 300)}`);
    }
    rec?.update({ workspace: wsId });
    const extra = { workspace: wsId, pane: paneId };
    try {
      const sentinel = `AXC-DONE-${job.id}-rc=`;
      const cmd = `${shq(o.node ?? process.execPath)} ${shq(ENTRY)} ${shq(specPath)}; echo ${sentinel}$?`;
      if (signal?.aborted) return refusal(name, job, "aborted before the input was sent; nothing ran");
      try {
        await herdrRpc(socket, "pane.send_input", { pane_id: paneId, text: cmd, keys: ["Enter"] });
      } catch (e) {
        // The input may have been typed before the answer was lost: a refusal
        // only when the job provably never started within the grace window.
        const why = `pane.send_input: ${(e as Error).message}`;
        const lookUntil = Date.now() + (o.startGraceMs ?? 3000);
        while (Date.now() < lookUntil && !existsSync(join(job.jobDir, ".herdr-pid"))) await sleep(pollMs);
        if (!existsSync(join(job.jobDir, ".herdr-pid"))) return refusal(name, job, `herdr: ${why}; the job never started`);
        return await followJobDir(job, startedAtMs, t0, timeoutMs, why, extra, signal);
      }
      const re = `${sentinel.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}[0-9]+`;
      // The abort is raced against the wait (successor review r3: an aborted
      // pane job ran to completion and held the run until it did). On abort
      // the job's group is killed (proved by .herdr-pstart) and the finally
      // closes the workspace.
      let onAbort: (() => void) | undefined;
      const aborted = new Promise<"aborted">((r) => {
        onAbort = () => r("aborted");
        if (signal?.aborted) r("aborted");
        else signal?.addEventListener("abort", onAbort, { once: true });
      });
      try {
        const won = await Promise.race([
          herdrRpc(
            socket,
            "pane.wait_for_output",
            { pane_id: paneId, source: "recent_unwrapped", match: { type: "regex", value: re }, timeout_ms: timeoutMs + 5000 },
            timeoutMs + 10000,
          ).then(() => "done" as const),
          aborted,
        ]);
        if (won === "aborted") {
          const deadline = Date.now() + (o.startGraceMs ?? 3000);
          // The job may not have written its pid yet: give it the start grace to appear, then kill.
          while (!killJobGroup(job.jobDir) && !existsSync(join(job.jobDir, ".herdr-rc")) && Date.now() < deadline) await sleep(pollMs);
          return { runtime: name, jobId: job.id, exitCode: 137, stdout: readIf(join(job.jobDir, ".herdr-stdout")) ?? "", stderr: "[runner: aborted; the pane job's group was killed]", durationMs: Math.round(performance.now() - t0), timedOut: false, detail: { mode, ...extra, aborted: "yes" } };
        }
      } catch (e) {
        return await followJobDir(job, startedAtMs, t0, timeoutMs, `pane.wait_for_output: ${(e as Error).message}`, extra, signal);
      } finally {
        if (onAbort) signal?.removeEventListener("abort", onAbort);
      }
      const rc = Number((readIf(join(job.jobDir, ".herdr-rc")) ?? "").trim());
      return {
        runtime: name,
        jobId: job.id,
        exitCode: Number.isInteger(rc) ? rc : 1,
        stdout: readIf(join(job.jobDir, ".herdr-stdout")) ?? "",
        stderr: readIf(join(job.jobDir, ".herdr-stderr")) ?? "",
        durationMs: Math.round(performance.now() - t0),
        ...(rc === 124 ? { timedOut: true } : {}),
        detail: { mode, ...extra },
      };
    } finally {
      // Only the workspace this call created; kept on record if it would not close.
      const closed = await herdrRpc(socket, "workspace.close", { workspace_id: wsId }).then(
        () => true,
        () => false,
      );
      if (closed) rec?.done();
    }
  };

  return {
    name,
    type: "herdr",
    refuses,
    async run(job, signal): Promise<RunResult> {
      const why = refuses(job);
      if (why || job.kind !== "process") return refusal(name, job, why ?? "unreachable");
      mkdirSync(job.jobDir, { recursive: true });
      const timeoutMs = job.timeoutMs ?? o.timeoutMs ?? DEFAULT_TIMEOUT_MS;
      const rec = job.procFile ? herdrRecord(job.procFile, { socket, jobDir: job.jobDir }) : undefined;
      if (mode === "pane") return await runPane(job, timeoutMs, rec, signal);
      try {
        const r = await runAction(job, timeoutMs, signal);
        rec?.done();
        return r;
      } catch (e) {
        // runAction turns every error after the invoke into an outcome; what is
        // left here happened before anything was sent.
        rec?.done();
        return refusal(name, job, `herdr: ${(e as Error).message}`);
      }
    },
  };
}

interface HerdrRecord {
  update(fields: Record<string, unknown>): void;
  done(): void;
}

/**
 * Close every workspace whose label is `label` (a create whose answer was
 * lost). ok when the list answered: the ones found are closed (none found:
 * herdr never made it). Not ok when herdr could not be asked; the caller then
 * keeps its record so the restart reaper tries again. The workspace.list
 * answer's shape (`workspaces[]` of {workspace_id, label}) is INFERRED from
 * the `workspace_list` type herdr-kitten's smoke test checks.
 */
export async function closeByLabel(socket: string, label: string): Promise<{ ok: boolean; note: string }> {
  let listed: Record<string, unknown>;
  try {
    listed = await herdrRpc(socket, "workspace.list", {});
  } catch (e) {
    return { ok: false, note: `workspace.list failed (${(e as Error).message}); the record keeps label ${label} for the restart reaper` };
  }
  // An answer of another shape proves nothing: keep the record rather than claim none was made.
  if (!Array.isArray(listed.workspaces)) {
    return { ok: false, note: `workspace.list answered without a workspaces[] list; the record keeps label ${label} for the restart reaper` };
  }
  const all = listed.workspaces as Record<string, unknown>[];
  const mine = all.filter((w) => w?.label === label && typeof w.workspace_id === "string");
  const failed: string[] = [];
  for (const w of mine) {
    await herdrRpc(socket, "workspace.close", { workspace_id: w.workspace_id }).catch((e: Error) => failed.push(`${String(w.workspace_id)}: ${e.message}`));
  }
  if (failed.length) return { ok: false, note: `workspace ${label} close failed: ${failed.join("; ")}` };
  return { ok: true, note: mine.length ? `closed ${mine.length} workspace(s) labelled ${label}` : `no workspace labelled ${label}` };
}

/** The runner-side record of a herdr job (socket, job dir, workspace, runner pid and start), beside its proc file. */
export const herdrRecordFile = (procFile: string) => procFile.replace(/\.proc\.json$/, "") + ".herdr.json";

function herdrRecord(procFile: string, base: { socket: string; jobDir: string }): HerdrRecord {
  const path = herdrRecordFile(procFile);
  let body: Record<string, unknown> = { ...base, runnerPid: process.pid, runnerStart: procStartTicks(process.pid) };
  const write = () => writeFileSync(path, JSON.stringify(body) + "\n");
  write();
  return {
    update(fields) {
      body = { ...body, ...fields };
      write();
    },
    done() {
      rmSync(path, { force: true });
    },
  };
}

/** Kill a herdr job's group from its job dir, only when .herdr-pstart proves the pid is still the job's. */
function killJobGroup(jobDir: string): boolean {
  const pid = Number((readIf(join(jobDir, ".herdr-pid")) ?? "").trim());
  const start = (readIf(join(jobDir, ".herdr-pstart")) ?? "").trim();
  if (!Number.isInteger(pid) || pid <= 0 || start === "" || !sameProcess(pid, start)) return false;
  try {
    process.kill(-pid, "SIGKILL");
    return true;
  } catch {
    return false;
  }
}

/**
 * The restart's half for herdr jobs (successor review r2: kill -9 of the
 * runner left the herdr job running and its pane workspace open). For every
 * record whose runner is gone: kill the job's group (proved by its start
 * time), close the workspace this run created, and forget the record.
 */
export async function reapHerdrRecords(jobsRoot: string, self = process.pid): Promise<string[]> {
  if (!existsSync(jobsRoot)) return [];
  const lines: string[] = [];
  for (const f of readdirSync(jobsRoot)) {
    if (!f.endsWith(".herdr.json")) continue;
    const path = join(jobsRoot, f);
    let rec: { socket?: string; jobDir?: string; workspace?: string; label?: string; runnerPid?: number; runnerStart?: string };
    try {
      rec = JSON.parse(readFileSync(path, "utf8")) as typeof rec;
    } catch {
      continue;
    }
    if (rec.runnerPid === self || sameProcess(rec.runnerPid, rec.runnerStart)) continue;
    const id = f.replace(/\.herdr\.json$/, "");
    const killed = typeof rec.jobDir === "string" && killJobGroup(rec.jobDir);
    let closed = "no workspace";
    if (typeof rec.workspace === "string" && typeof rec.socket === "string") {
      closed = await herdrRpc(rec.socket, "workspace.close", { workspace_id: rec.workspace }).then(
        () => `workspace ${rec.workspace} closed`,
        (e: Error) => `workspace ${rec.workspace} close failed: ${e.message}`,
      );
    } else if (typeof rec.label === "string" && typeof rec.socket === "string") {
      // The create answer was lost: close by label.
      const swept = await closeByLabel(rec.socket, rec.label);
      closed = swept.ok ? swept.note : `${swept.note} (close failed)`;
    }
    lines.push(`${id}: herdr job ${killed ? "killed" : "not running"}; ${closed}`);
    if (!closed.includes("failed")) rmSync(path, { force: true });
  }
  return lines;
}
