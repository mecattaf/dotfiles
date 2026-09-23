/**
 * RunnerBackend: the interpreter's Backend seam, backed by runtimes.
 *
 * It is structurally the interpreter's `Backend` (`name`, `run(call)` returning
 * `{text|object|usage|error|agentId}`), so the interpreter plugs it in with no
 * import either way. For each agent() call it:
 *
 *   1. selects the runtime: `opts.runtime`, else the phase default, else the
 *      file default, else `host` (config.ts `selectRuntime`);
 *   2. builds the harness invocation (claude pinned to claude-opus-5-5, or pi on
 *      Halogen) with the prompt on stdin;
 *   3. mounts the seat credential where that runtime's harness looks for it,
 *      as a mount (never a copy), and points CLAUDE_CONFIG_DIR at it so the
 *      seat is chosen explicitly rather than inherited;
 *   4. runs one attempt and parses the reply. A refusal, a non-zero exit or an
 *      unparseable reply is an `error`; the interpreter owns retries.
 *
 * Every call leaves `receipt.json` in its job dir: runtime, how it was chosen,
 * exit code, duration and the runner's own evidence.
 */
import { accessSync, closeSync, constants as fsc, existsSync, linkSync, mkdirSync, openSync, readdirSync, readFileSync, realpathSync, rmSync, writeFileSync, writeSync } from "node:fs";
import { basename, dirname, join } from "node:path";
import { selectRuntime, type RuntimesConfig, type Runtime, type Selection } from "./config.ts";
import { isRefusal, type Mount, type ProcessJob, type Runner } from "./job.ts";
import { runnerFor } from "./registry.ts";
import { DEFAULT_MODEL_ALLOWLIST, resolveModel, type ModelCeilings } from "./models.ts";
import { CLAUDE_MODEL, HALOGEN_MODEL, HALOGEN_PROVIDER, HARNESS_OPTIONS, invocationFor, parseFor, type HarnessName } from "./harness.ts";
import { spawnSync } from "node:child_process";
import { axTaskSpec } from "./ax.ts";
import { SANDBOX_HOME } from "./gvisor.ts";
import { createHash } from "node:crypto";
import { procStartTicks, sameProcess } from "./proc.ts";

/**
 * The test guard: set only by a test (fake binaries) run. Without it the
 * codex harness is never dispatched (a third party's login; successor review
 * r4: the ban lived only in the capacity gate, so --no-capacity ran it).
 */
export const TEST_SEAT_ENV = "AX_CONWIP_TEST_SEAT";
export const testSeatGuard = (): boolean => process.env[TEST_SEAT_ENV] === "1";

/**
 * Under the test guard, the codex harness still runs only a FAKE it can vouch
 * for (final verification 2026-09-23): the first `codex` on the caller's PATH
 * must resolve outside /nix/store (an installed codex is a store path), and
 * never over ssh, where the remote PATH holds the real codex and this process
 * cannot see what `codex` resolves to. Returns the refusal, or undefined.
 */
export function fakeCodexProblem(runtimeType: string, pathEnv = process.env.PATH ?? ""): string | undefined {
  if (runtimeType === "ssh") return "the codex harness never runs over ssh: the remote PATH holds the real codex (a third party's login) and a fake there cannot be vouched for";
  for (const d of pathEnv.split(":").filter(Boolean)) {
    const c = join(d, "codex");
    try {
      accessSync(c, fsc.X_OK);
    } catch {
      continue;
    }
    let real: string;
    try {
      real = realpathSync(c);
    } catch {
      continue;
    }
    return real.startsWith("/nix/store/") ? `the first codex on PATH resolves to ${real}, an installed codex; the test guard runs a fake only` : undefined;
  }
  return "no codex on PATH (the test guard runs a fake only)";
}

/** The subset of the interpreter's AgentCall this backend reads. */
export interface RunnerCall {
  readonly index: number;
  readonly key: string;
  readonly prompt: string;
  readonly opts: { readonly label?: string; readonly schema?: Record<string, unknown>; readonly runtime?: unknown; readonly [k: string]: unknown };
  readonly phase: string | undefined;
  readonly attempt: number;
  readonly previousErrors?: readonly string[];
  readonly signal?: AbortSignal;
}

export interface RunnerAgentOutcome {
  readonly text?: string;
  readonly object?: unknown;
  readonly usage?: { readonly inputTokens: number; readonly outputTokens: number };
  readonly error?: string;
  readonly agentId?: string;
}

export interface RunnerBackendOptions {
  /** Job dirs land under `<jobsRoot>/<runId>[-s<start>]-<index>-a<attempt>`. */
  readonly jobsRoot: string;
  readonly runId: string;
  /**
   * The 1-based start ordinal of this process on the run (run.json `starts`).
   * Above 1 it enters the job id, so a resumed attempt never shares a job dir
   * with an orphan of an earlier start (successor review 2026-09-23).
   */
  readonly start?: number;
  /** The seat a claude harness spends when `[seats]` names none (the run's --seat). */
  readonly defaultSeat?: string;
  readonly workflow?: string;
  /** Override runners by runtime name (tests). */
  readonly runners?: Readonly<Record<string, Runner>>;
  /** The git repository an isolation:'worktree' call gets a fresh worktree of. Default: the process cwd. */
  readonly repoDir?: string;
  /** Where per-job seat shadows live (never a run dir). Default: see seatShadowRoot. */
  readonly seatShadowRoot?: string;
  /** The script's meta phase index for a phase title (1-based), for a Task this backend builds itself. */
  readonly phaseIndexOf?: (title: string) => number | undefined;
}

/** Where a runtime's harness finds the seat config, or undefined when it brings its own. */
export function credentialMount(config: RuntimesConfig, runtime: Runtime, harness: HarnessName): Mount | undefined {
  if (harness !== "claude") return undefined;
  const source = config.credentials.claude;
  const mode = config.credentials.mode;
  switch (runtime.type) {
    case "host":
    case "runtime-test":
    case "herdr":
      return { source, target: source, mode, purpose: "credential" };
    case "gvisor":
      return { source, target: `${SANDBOX_HOME}/.claude`, mode, purpose: "credential" };
    case "microvm":
      return { source, target: "/root/.claude", mode, purpose: "credential" };
    default:
      return undefined; // ssh: the remote's own seat; workerd, ax: no harness runs there
  }
}

/**
 * The narrowed seat mounts for a sandboxed runtime (successor review
 * 2026-09-23): the whole config dir rw let a job rewrite settings.json hooks,
 * skills or CLAUDE.md that the next HOST session runs. The job now gets a
 * fresh scratch config dir (`shadow`, outside its job dir) with only the seat
 * credential file bound in, in the configured mode (Tom's 2026-09-21 ruling:
 * rw, for token refresh). `credentials.scope = "dir"` restores the whole-dir
 * mount. gVisor binds the file; microvm's 9p shares directories only, so there
 * the shadow holds a hard link to the credential (same inode: an in-place
 * refresh reaches the seat; a rename-replace stays in the shadow, INFERRED).
 */
/**
 * The Halogen provider a sandboxed pi needs (final verification 2026-09-23:
 * pi in gVisor exited 1 "Unknown provider halogen", because the sandbox HOME
 * is empty). It is generated from constants, never copied from the host's
 * models.json (which also names cloud providers and their keys). Halogen has
 * no auth; the apiKey is a placeholder. Only the worker serves it (ruling:
 * Halogen is never resident on the coordinator).
 */
export const HALOGEN_BASE_URL = "http://worker:8731/v1";
export function piHalogenModels(): string {
  return JSON.stringify({
    providers: {
      [HALOGEN_PROVIDER]: {
        api: "openai-completions",
        apiKey: "no-auth",
        authHeader: true,
        baseUrl: HALOGEN_BASE_URL,
        compat: { supportsDeveloperRole: false, supportsReasoningEffort: false, supportsStore: false },
        models: [{ id: HALOGEN_MODEL, name: "Halogen (worker)", reasoning: true, input: ["text"], contextWindow: 262144, maxTokens: 32768 }],
      },
    },
  }, null, 1) + "\n";
}

export function credentialMounts(config: RuntimesConfig, runtime: Runtime, harness: HarnessName, shadow: string): Mount[] | { refused: string } {
  if (harness === "pi" && (runtime.type === "gvisor" || runtime.type === "microvm")) {
    const agentDir = join(shadow, "pi-agent");
    mkdirSync(agentDir, { recursive: true, mode: 0o700 });
    writeFileSync(join(agentDir, "models.json"), piHalogenModels(), { mode: 0o600 });
    const home = runtime.type === "gvisor" ? SANDBOX_HOME : "/root";
    return [{ source: agentDir, target: `${home}/.pi/agent`, mode: "rw", purpose: "other" }];
  }
  const dir = credentialMount(config, runtime, harness);
  if (!dir) return [];
  if (config.credentials.scope === "dir" || (runtime.type !== "gvisor" && runtime.type !== "microvm")) return [dir];
  const cred = join(config.credentials.claude, ".credentials.json"); // fence-ok: bound by path, never read
  if (!existsSync(cred)) return { refused: `no seat credential at ${cred} (credentials.scope = "credential")` };
  mkdirSync(shadow, { recursive: true, mode: 0o700 });
  // Who owns this shadow (successor review r4): any later start on any run
  // sweeps a shadow whose owner is gone, so a kill -9 never leaves a live
  // link to the credential behind for longer than the next start.
  writeFileSync(`${shadow}.owner.json`, JSON.stringify({ pid: process.pid, start: procStartTicks(process.pid) }) + "\n", { mode: 0o600 });
  if (runtime.type === "gvisor") {
    return [
      { source: shadow, target: dir.target, mode: "rw", purpose: "credential" },
      { source: cred, target: join(dir.target, basename(cred)), mode: dir.mode, purpose: "credential" },
    ];
  }
  try {
    linkSync(cred, join(shadow, basename(cred)));
  } catch (e) {
    return { refused: `cannot link the seat credential into the microvm share: ${(e as Error).message}` };
  }
  return [{ source: shadow, target: dir.target, mode: dir.mode, purpose: "credential" }];
}

/**
 * Where per-job seat shadows (the microvm credential share) live: never in a
 * run dir. Default: <parent of the credential dir>/.local/state/substrate/seat-shadows
 * (~/.local/state/... for ~/.claude), on the credential's filesystem so the
 * hard link can be made; mode 0700.
 */
export function seatShadowRoot(config: RuntimesConfig, override?: string): string {
  // Created (0700, recursively) only when a job needs a shadow (credentialMounts).
  return override ?? join(dirname(config.credentials.claude), ".local", "state", "substrate", "seat-shadows");
}

/**
 * Remove seat shadows a killed start left behind: every shadow of this run
 * id under the shadow root, and any legacy `<jobsRoot>/*.seat` dir. Run
 * before a restart dispatches anything.
 */
export function sweepSeatShadows(config: RuntimesConfig, runId: string, jobsRoot: string, override?: string): string[] {
  const lines: string[] = [];
  const root = seatShadowRoot(config, override);
  const prefix = jobIdFor(runId, 0, 0).replace(/-0-a0$/, "");
  const entries = existsSync(root) ? readdirSync(root) : [];
  for (const f of entries) {
    if (f.endsWith(".owner.json")) {
      // An owner file whose shadow is gone is removed with it below or here.
      if (!entries.includes(f.slice(0, -".owner.json".length))) rmSync(join(root, f), { force: true });
      continue;
    }
    let owner: { pid?: number; start?: string } | undefined;
    try {
      owner = JSON.parse(readFileSync(join(root, `${f}.owner.json`), "utf8")) as typeof owner;
    } catch {
      owner = undefined;
    }
    const ours = f === prefix || f.startsWith(`${prefix}-`);
    // Any run's shadow whose owning runner is gone (kill -9, SIGTERM) is swept,
    // not only this run id's (successor review r4).
    const orphan = owner !== undefined && owner.pid !== process.pid && !sameProcess(owner.pid, owner.start);
    if (ours || orphan) {
      rmSync(join(root, f), { recursive: true, force: true });
      rmSync(join(root, `${f}.owner.json`), { force: true });
      lines.push(`seat shadow ${f} removed${ours ? "" : ` (owner pid ${owner?.pid} is gone)`}`);
    }
  }
  if (existsSync(jobsRoot)) {
    for (const f of readdirSync(jobsRoot)) {
      if (!f.endsWith(".seat")) continue;
      rmSync(join(jobsRoot, f), { recursive: true, force: true });
      lines.push(`legacy seat shadow ${f} removed from the run dir`);
    }
  }
  return lines;
}

const jobIdFor = (runId: string, index: number, attempt: number, start = 1) =>
  `${runId}${start > 1 ? `-s${start}` : ""}-${index}-a${attempt}`.replace(/[^A-Za-z0-9_.-]/g, "_").slice(0, 128);

/**
 * Write a runner file into a job dir that a job may already have written to:
 * never through a symlink and never over an existing file (O_CREAT|O_EXCL|
 * O_NOFOLLOW). False when something is already there.
 */
export function writeFresh(path: string, data: string): boolean {
  let fd: number;
  try {
    fd = openSync(path, fsc.O_WRONLY | fsc.O_CREAT | fsc.O_EXCL | fsc.O_NOFOLLOW, 0o600);
  } catch (e) {
    const code = (e as NodeJS.ErrnoException).code;
    if (code === "EEXIST" || code === "ELOOP") return false;
    throw e;
  }
  try {
    writeSync(fd, data);
  } finally {
    closeSync(fd);
  }
  return true;
}

/** Where one call runs and what it spends: the runtime, the harness, the model that runs and its seat. */
export interface Route {
  readonly selection: Selection;
  readonly harness: HarnessName | "ax";
  /** The full id that runs; `codex` when codex runs its own configured default. */
  readonly model: string;
  /** What the call asked for, when the allowlist ran something else. */
  readonly requestedModel?: string;
  /** The allowlist's per-window ceilings for this model, for the capacity gate. */
  readonly ceilings?: ModelCeilings;
  /** The capacity seat this harness spends, or undefined when `[seats]` binds none. */
  readonly seat: string | undefined;
}

export class RunnerBackend {
  readonly name = "runners";
  private readonly cache = new Map<string, Runner>();
  constructor(
    readonly config: RuntimesConfig,
    readonly options: RunnerBackendOptions,
  ) {}

  runnerOf(sel: Selection): Runner {
    const given = this.options.runners?.[sel.name];
    if (given) return given;
    let r = this.cache.get(sel.name);
    if (!r) {
      r = runnerFor(sel.name, sel.runtime);
      this.cache.set(sel.name, r);
    }
    return r;
  }

  /**
   * The route one call will take, before it is admitted: the CONWIP gates the
   * model that RUNS on the seat that PAYS (successor review 2026-09-23: the
   * gate used to judge the script's declared model on the run's --seat while
   * the runner ran claude-opus-5-5, or codex, elsewhere). Throws on a runtime
   * the file refuses.
   */
  route(call: { readonly opts: { readonly runtime?: unknown; readonly model?: unknown }; readonly phase: string | undefined }): Route {
    const sel = selectRuntime(this.config, { runtime: call.opts.runtime, phase: call.phase });
    const declared = typeof call.opts.model === "string" ? call.opts.model : undefined;
    const pick = (h: HarnessName, fallback: string) => {
      const r = resolveModel(this.config.models ?? DEFAULT_MODEL_ALLOWLIST, h, declared);
      return {
        model: r.id ?? fallback,
        ...(r.requested !== undefined ? { requestedModel: r.requested } : {}),
        ...(r.ceilings !== undefined ? { ceilings: r.ceilings } : {}),
      };
    };
    if (sel.runtime.type === "ax") {
      // The ax seam renders the Task for the harness the table names (final
      // verification 2026-09-23: it ignored `harness`, so a pi table rendered
      // an Opus Task on the halogen seat and a codex table an Opus Task). pi
      // renders a Halogen Task on the halogen seat, as serve's taskRouteForSeat.
      const h = sel.runtime.harness ?? "claude";
      if (h === "pi") return { selection: sel, harness: "pi", ...pick("pi", HALOGEN_MODEL), seat: sel.runtime.seat ?? this.config.seats["pi"] };
      if (h === "codex") return { selection: sel, harness: "codex", ...pick("codex", "codex"), seat: undefined };
      return { selection: sel, harness: "ax", ...pick("claude", CLAUDE_MODEL), seat: sel.runtime.seat ?? this.config.seats["claude"] ?? this.options.defaultSeat };
    }
    const harness: HarnessName = sel.runtime.harness ?? "claude";
    const picked = pick(harness, harness === "claude" ? CLAUDE_MODEL : harness === "pi" ? HALOGEN_MODEL : "codex");
    const model = picked.model;
    // The seat is a property of (runtime, harness): a runtime table's own
    // `seat` wins. On ssh a claude call spends the REMOTE login, so without a
    // declared seat it is bound to none, and a gate refuses it (successor
    // review r2: ssh:worker was gated and ledgered against the local cc).
    if (sel.runtime.seat !== undefined) return { selection: sel, harness, ...picked, seat: sel.runtime.seat };
    if (sel.runtime.type === "ssh" && harness === "claude") return { selection: sel, harness, ...picked, seat: undefined };
    const seat = this.config.seats[harness] ?? (harness === "claude" ? this.options.defaultSeat : undefined);
    return { selection: sel, harness, ...picked, seat };
  }

  /**
   * Run one call. `admitted` is the Task the CONWIP admitted and size-checked
   * (FIELD-MAP 5a); the ax runtime writes exactly that Task, so there is one
   * Task builder on the integrated path (successor review r2).
   */
  async run(call: RunnerCall, admitted?: unknown): Promise<RunnerAgentOutcome> {
    // An already-aborted call is never started (successor review r3).
    if (call.signal?.aborted) return { error: "aborted before dispatch; nothing ran" };
    let sel: Selection;
    try {
      sel = selectRuntime(this.config, { runtime: call.opts.runtime, phase: call.phase });
    } catch (e) {
      return { error: (e as Error).message };
    }
    const id = jobIdFor(this.options.runId, call.index, call.attempt, this.options.start);
    const jobDir = join(this.options.jobsRoot, id);
    mkdirSync(this.options.jobsRoot, { recursive: true });
    // A fresh dir per job: a dir that already exists may hold links planted by
    // an earlier job with the same id, so it is refused, never reused.
    try {
      mkdirSync(jobDir, { mode: 0o700 });
    } catch (e) {
      return { error: `runtime ${sel.name}: job dir ${jobDir} already exists (${(e as NodeJS.ErrnoException).code}); refusing to reuse it` };
    }
    const receiptBody = (o: Record<string, unknown>) => JSON.stringify({ jobId: id, runtime: sel.name, type: sel.runtime.type, via: sel.via, ...o }, null, 1);
    /** The receipt goes into the job dir only if nothing is there (never through a planted link); else beside it. */
    const receipt = (o: Record<string, unknown>): boolean => {
      if (writeFresh(join(jobDir, "receipt.json"), receiptBody(o))) return true;
      writeFileSync(join(this.options.jobsRoot, `${id}.receipt.json`), receiptBody({ ...o, hostile: "receipt.json already existed in the job dir (planted by the job?)" }));
      return false;
    };

    if (sel.runtime.type === "ax") {
      const route = this.route(call);
      if (route.harness === "codex") {
        const why = "the ax seam renders Claude and Halogen Tasks only; a codex Task would spend a third party's login";
        receipt({ refused: why });
        return { error: `runtime ${sel.name} refused: ${why}` };
      }
      if (admitted === undefined && route.seat === undefined) {
        receipt({ refused: "no capacity seat for the ax runtime (seat = ... on the runtime table, or [seats].claude)" });
        return { error: `runtime ${sel.name} refused: bound to no capacity seat` };
      }
      const task = admitted !== undefined ? (admitted as ReturnType<typeof axTaskSpec>) : axTaskSpec(
        {
          runId: this.options.runId,
          index: call.index,
          label: call.opts.label ?? `#${call.index}`,
          prompt: call.prompt,
          model: route.model,
          journalKey: createHash("sha256").update(call.key).digest("hex"),
          workflow: this.options.workflow ?? "",
          phaseIndex: (call.phase !== undefined ? this.options.phaseIndexOf?.(call.phase) : undefined) ?? 0,
          phaseTitle: call.phase ?? "",
          seat: route.seat!,
          attempt: call.attempt,
          ...(call.opts.schema ? { schema: call.opts.schema } : {}),
        },
        {
          ...(sel.runtime.atespace ? { atespace: sel.runtime.atespace } : {}),
          ...(sel.runtime.sandboxClass ? { sandboxClass: sel.runtime.sandboxClass } : {}),
          ...(sel.runtime.image ? { image: sel.runtime.image } : {}),
        },
      );
      writeFileSync(join(jobDir, "ax-task.json"), JSON.stringify(task, null, 1));
      const why = "refused" in task ? task.refused : this.runnerOf(sel).refuses({ kind: "process", id, argv: ["ultracode-agent"], jobDir })!;
      receipt({ refused: why, axTask: join(jobDir, "ax-task.json") });
      return { error: `runtime ${sel.name} refused: ${why}` };
    }

    const harness: HarnessName = sel.runtime.harness ?? "claude";
    // A real codex runs only when the operator bound the codex harness to a
    // capacity seat (`[seats] codex = ...`, or the runtime table's `seat`), so
    // the gate judges it like any other seat. Under the test guard only a fake
    // it can vouch for runs, as before.
    if (harness === "codex" && !testSeatGuard() && (sel.runtime.seat ?? this.config.seats["codex"]) === undefined) {
      receipt({ refused: "the codex harness is bound to no capacity seat" });
      return { error: `runtime ${sel.name} refused: the codex harness is bound to no capacity seat (declare [seats] codex = "<seat>"; ${TEST_SEAT_ENV}=1 is for fake binaries under test only)` };
    }
    if (harness === "codex" && testSeatGuard()) {
      const why = fakeCodexProblem(sel.runtime.type);
      if (why) {
        receipt({ refused: why });
        return { error: `runtime ${sel.name} refused: ${why}` };
      }
    }
    // agent() options are honoured or refused, never dropped (successor review
    // r2: isolation, effort and agentType were keyed but never reached the harness).
    const o = call.opts as { effort?: unknown; agentType?: unknown; isolation?: unknown };
    const refuse = (why: string) => {
      receipt({ refused: why });
      return { error: `runtime ${sel.name} refused: ${why}` };
    };
    for (const k of ["effort", "agentType"] as const) {
      if (o[k] === undefined) continue;
      if (typeof o[k] !== "string") return refuse(`agent({${k}}) must be a string`);
      if (!HARNESS_OPTIONS[harness].includes(k)) return refuse(`harness ${harness} cannot honour agent({${k}: ${JSON.stringify(o[k])}})`);
    }
    let worktree: { top: string; path: string; base: string } | undefined;
    if (o.isolation !== undefined) {
      if (o.isolation !== "worktree") return refuse(`agent({isolation: ${JSON.stringify(o.isolation)}}) is not supported (only "worktree")`);
      if (sel.runtime.type !== "host") return refuse(`runtime ${sel.name} (${sel.runtime.type}) cannot honour isolation:'worktree'; only host runs a job in a host git worktree`);
      const wt = addWorktree(this.options.repoDir ?? process.cwd(), join(jobDir, "worktree"));
      if ("refused" in wt) return refuse(wt.refused);
      worktree = wt;
      // The worktree is recorded beside the proc file, so a restart after a
      // kill -9 settles it (successor review r4: it stayed registered, dirty).
      writeFileSync(worktreeRecordFile(this.options.jobsRoot, id), JSON.stringify({ ...wt, runnerPid: process.pid, runnerStart: procStartTicks(process.pid) }) + "\n");
    }
    const declaredModel = typeof (call.opts as { model?: unknown }).model === "string" ? (call.opts as { model: string }).model : undefined;
    const resolved = resolveModel(this.config.models ?? DEFAULT_MODEL_ALLOWLIST, harness, declaredModel);
    const inv = invocationFor(harness, {
      prompt: call.prompt,
      ...(resolved.id !== undefined ? { model: resolved.id } : {}),
      ...(call.opts.schema ? { schema: call.opts.schema } : {}),
      ...(typeof o.effort === "string" ? { effort: o.effort } : {}),
      ...(typeof o.agentType === "string" ? { agentType: o.agentType } : {}),
      ...(call.previousErrors && call.previousErrors.length ? { previousErrors: call.previousErrors } : {}),
    });
    // The seat shadow lives OUTSIDE the run dir and is removed when the job
    // is over, refused or not (successor review r3: a hard link to the seat
    // credential was left in <run dir>/jobs/<id>.seat/, and run dirs under
    // ~/today are landed into notes and pushed every night).
    const shadow = join(seatShadowRoot(this.config, this.options.seatShadowRoot), id);
    const mounts = credentialMounts(this.config, sel.runtime, harness, shadow);
    if ("refused" in mounts) {
      rmSync(shadow, { recursive: true, force: true });
      rmSync(`${shadow}.owner.json`, { force: true });
      receipt({ refused: mounts.refused });
      return { error: `runtime ${sel.name} refused: ${mounts.refused}` };
    }
    try {
      return await this.#runJob(call, sel, id, jobDir, harness, inv, mounts, worktree, receipt);
    } finally {
      rmSync(shadow, { recursive: true, force: true });
      rmSync(`${shadow}.owner.json`, { force: true });
    }
  }

  async #runJob(
    call: RunnerCall,
    sel: Selection,
    id: string,
    jobDir: string,
    harness: HarnessName,
    inv: ReturnType<typeof invocationFor>,
    mounts: Mount[],
    worktree: { top: string; path: string; base: string } | undefined,
    receipt: (o: Record<string, unknown>) => boolean,
  ): Promise<RunnerAgentOutcome> {
    const env = { ...(inv.env ?? {}), ...(mounts.length && harness === "claude" ? { CLAUDE_CONFIG_DIR: mounts[0]!.target } : {}) };
    const job: ProcessJob = {
      kind: "process",
      id,
      ...(Object.keys(env).length ? { env } : {}),
      argv: inv.argv,
      stdin: inv.stdin,
      jobDir,
      agent: true,
      procFile: join(this.options.jobsRoot, `${id}.proc.json`),
      ...(worktree ? { cwd: worktree.path } : {}),
      ...(mounts.length ? { mounts } : {}),
    };

    const runner = this.runnerOf(sel);
    let res: Awaited<ReturnType<Runner["run"]>>;
    let wtNote: { path: string; kept: boolean } | undefined;
    try {
      res = await runner.run(job, call.signal);
    } finally {
      // Settled even when the runner throws or the call was aborted.
      wtNote = worktree ? settleWorktree(worktree) : undefined;
      if (worktree) rmSync(worktreeRecordFile(this.options.jobsRoot, id), { force: true });
    }
    if (isRefusal(res)) {
      receipt({ refused: res.refused, detail: res.detail ?? {} });
      return { error: `runtime ${sel.name} refused: ${res.refused}` };
    }
    // argv carries no prompt (it rides on stdin) and no credential (mounted by path).
    const clean = receipt({ exitCode: res.exitCode, durationMs: res.durationMs, timedOut: res.timedOut ?? false, harness, argv: inv.argv, ...(wtNote ? { worktree: wtNote } : {}), detail: res.detail ?? {} });
    if (!clean) return { error: `runtime ${sel.name}: the job planted receipt.json in its job dir; its outcome is not trusted` };
    if (res.exitCode !== 0) {
      // A failed harness still spent tokens: its envelope's usage (and session
      // id) is kept, so the budget charges it (successor review r4: D10
      // undercounted every failed call; a real error_max_turns exit 1 carried
      // output tokens).
      const spent = parseFor(harness, res.stdout, false);
      return {
        ...(spent.usage ? { usage: spent.usage } : {}),
        ...(spent.agentId ? { agentId: spent.agentId } : {}),
        error: `runtime ${sel.name}: ${harness} exited ${res.exitCode}${res.timedOut ? " (timeout)" : ""}: ${res.stderr.slice(-500) || res.stdout.slice(-500)}`,
      };
    }
    const parsed = parseFor(harness, res.stdout, call.opts.schema !== undefined);
    return parsed;
  }
}

const git = (args: string[]) => spawnSync("git", args, { encoding: "utf8" });

/** A fresh detached worktree of the repo holding `repoDir`, at its HEAD. */
function addWorktree(repoDir: string, path: string): { top: string; path: string; base: string } | { refused: string } {
  const top = git(["-C", repoDir, "rev-parse", "--show-toplevel"]);
  if (top.status !== 0) return { refused: `isolation:'worktree' needs a git repository; ${repoDir} is not in one` };
  const root = top.stdout.trim();
  const base = git(["-C", root, "rev-parse", "HEAD"]);
  if (base.status !== 0) return { refused: `isolation:'worktree': ${root} has no HEAD commit` };
  const add = git(["-C", root, "worktree", "add", "--detach", path, "HEAD"]);
  if (add.status !== 0) return { refused: `isolation:'worktree': git worktree add failed: ${add.stderr.slice(-300)}` };
  return { top: root, path, base: base.stdout.trim() };
}

/** Remove the worktree when the job left it unchanged; keep it (and say where) otherwise. */
function settleWorktree(w: { top: string; path: string; base: string }): { path: string; kept: boolean } {
  const dirty = git(["-C", w.path, "status", "--porcelain"]).stdout.trim() !== "";
  const head = git(["-C", w.path, "rev-parse", "HEAD"]).stdout.trim();
  if (!dirty && head === w.base) {
    git(["-C", w.top, "worktree", "remove", "--force", w.path]);
    return { path: w.path, kept: false };
  }
  return { path: w.path, kept: true };
}

/** The runner-side record of an isolation:'worktree' job's git worktree, beside its proc file. */
export const worktreeRecordFile = (jobsRoot: string, id: string) => join(jobsRoot, `${id}.worktree.json`);

/**
 * Settle the worktrees of jobs whose runner died (kill -9): a clean one is
 * removed from the repo; a dirty one is kept and reported as killed mid-edit
 * (successor review r4). Run before a restart dispatches anything.
 */
export function reapWorktreeRecords(jobsRoot: string, self = process.pid): string[] {
  if (!existsSync(jobsRoot)) return [];
  const lines: string[] = [];
  for (const f of readdirSync(jobsRoot)) {
    if (!f.endsWith(".worktree.json")) continue;
    const path = join(jobsRoot, f);
    let rec: { top?: string; path?: string; base?: string; runnerPid?: number; runnerStart?: string };
    try {
      rec = JSON.parse(readFileSync(path, "utf8")) as typeof rec;
    } catch {
      continue;
    }
    if (rec.runnerPid === self || sameProcess(rec.runnerPid, rec.runnerStart)) continue;
    if (typeof rec.top !== "string" || typeof rec.path !== "string" || typeof rec.base !== "string") {
      rmSync(path, { force: true });
      continue;
    }
    if (!existsSync(rec.path)) {
      git(["-C", rec.top, "worktree", "prune"]);
      rmSync(path, { force: true });
      lines.push(`worktree ${rec.path}: already gone, pruned`);
      continue;
    }
    const w = settleWorktree({ top: rec.top, path: rec.path, base: rec.base });
    lines.push(w.kept ? `worktree ${w.path}: killed mid-edit, kept (dirty or moved HEAD)` : `worktree ${w.path}: clean, removed`);
    rmSync(path, { force: true });
  }
  return lines;
}
