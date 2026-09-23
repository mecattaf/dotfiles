/**
 * Seat adapters.
 *
 * A seat adapter turns one admitted WorkItem into one process invocation, and
 * nothing else. The scheduler never originates a command line: the item
 * carries a name and a prompt, the adapter carries the command. Everything a
 * seat needs that is not in the item is baked into its factory at declaration
 * time, so no call site anywhere assembles argv by hand.
 */
import { deployConfig } from "./deploy-config.ts";
import { spawnSync } from "node:child_process";
import { accessSync, constants as fsc } from "node:fs";
import { delimiter, join } from "node:path";
import { PDEATHSIG_WRAPPER } from "@substrate/runners";

/** True when `file` (a path, or a name on PATH) is an executable. */
function executable(file: string): boolean {
  const candidates = file.includes("/") ? [file] : (process.env["PATH"] ?? "").split(delimiter).filter(Boolean).map((d) => join(d, file));
  return candidates.some((c) => {
    try {
      accessSync(c, fsc.X_OK);
      return true;
    } catch {
      return false;
    }
  });
}
import type { WorkItem } from "./schema.ts";

/** What one adapter produces: the argv to exec, and the bytes for its stdin. */
export interface SeatDispatch {
  readonly argv: readonly string[];
  readonly stdin: string;
}

/**
 * The interface, three members exactly: the seat id, the meter path this seat
 * is gated on, and the function from a WorkItem to an invocation.
 *
 * The staleness bound and the cap are NOT members. They are data the scheduler
 * holds beside the adapter (see `SeatDeclaration`), so that striking a cap
 * never means editing an adapter.
 */
export interface SeatAdapter {
  readonly seatId: string;
  readonly meterPath: string;
  readonly render: (item: WorkItem) => SeatDispatch;
  /**
   * Optional, and the only member added by item 26. Three members are still
   * REQUIRED; this fourth one is how a seat says what part of its stdout is the
   * model's answer, so that a spawn ledger line carries a reply rather than a
   * transport envelope. A seat that does not declare it simply has no reply
   * column, and the raw stdout excerpt is all the ledger gets.
   */
  readonly replyOf?: (stdout: string) => string;
}

/**
 * The local meter directory is configuration, not a constant (successor
 * FINAL-2026-09-23 section 8). `AX_CONWIP_METERS` (the name the unit already
 * set, DESIGN.md) chooses it; unset or empty, it is the directory it always
 * was, so behaviour is unchanged. `--meters` still overrides both.
 */
export const DEFAULT_METERS_DIR: string = deployConfig().metersDir;
export const METERS_DIR_ENV = "AX_CONWIP_METERS";

export function metersDirFrom(env: Readonly<Record<string, string | undefined>> = process.env): string {
  const v = env[METERS_DIR_ENV];
  return v !== undefined && v.length > 0 ? v : DEFAULT_METERS_DIR;
}

export const METERS_DIR = metersDirFrom();

/**
 * Seat `cc`: Claude on the primary account.
 *
 * `env -u CLAUDE_CONFIG_DIR` is load-bearing and is part of the command, not a
 * convenience: it selects ~/.claude, the primary seat, rather than whatever
 * CLAUDE_CONFIG_DIR happens to hold in the scheduler's own environment. The
 * prompt goes on stdin, so no prompt text ever appears in a process listing.
 */
export function ccAdapter(meterPath: string = `${METERS_DIR}/cc.json`): SeatAdapter {
  return {
    seatId: "cc",
    meterPath,
    render: (item: WorkItem): SeatDispatch => ({
      argv: [
        "env",
        "-u",
        "CLAUDE_CONFIG_DIR",
        "TALLY_SEAT=cc",
        "claude",
        "-p",
        "--model",
        "opus",
        "--dangerously-skip-permissions",
        "--output-format",
        "text",
      ],
      stdin: item.prompt,
    }),
  };
}

/**
 * Seat `codex`.
 *
 * The working directory is configured here, at declaration time, rather than
 * taken from the item: an item is a unit of work, not a statement about where
 * a seat runs. The trailing "-" means the prompt arrives on stdin; output is
 * JSON lines.
 */
export function codexAdapter(dir: string, meterPath: string = `${METERS_DIR}/codex.json`): SeatAdapter {
  return {
    seatId: "codex",
    meterPath,
    render: (item: WorkItem): SeatDispatch => ({
      argv: [
        "codex",
        "exec",
        "--dangerously-bypass-approvals-and-sandbox",
        "--dangerously-bypass-hook-trust",
        "--json",
        "-C",
        dir,
        "-",
      ],
      stdin: item.prompt,
    }),
  };
}

/**
 * Seat `halogen`, through the utility-model wrapper.
 *
 * The wrapper takes only -h and --timeout TIMEOUT. It supplies the endpoint,
 * the concrete model and the context size itself, so this factory passes none
 * of them: a factory holding a host:port string would have duplicated a fact
 * that Nix already owns, and would go stale the day the endpoint moves.
 *
 * It reads ONE chat-completions JSON request on stdin and writes the response
 * on stdout, so the stdin payload here is that request object and nothing more.
 *
 * Its meter row is `gpu-worker.json`: a slot row of capacity one with NO budget
 * row. The seat is not metered for spend, so its declaration passes
 * `utilizationField: "none"` and the cap check is skipped for it. A missing
 * budget figure is not a refusal for this seat, and that is a property of the
 * declaration, not an exception inside the rule.
 */
export function halogenAdapter(
  meterPath: string = `${METERS_DIR}/gpu-worker.json`,
  timeoutSeconds?: number,
): SeatAdapter {
  const argv =
    timeoutSeconds === undefined
      ? ["/run/current-system/sw/bin/utility-model"]
      : ["/run/current-system/sw/bin/utility-model", "--timeout", String(timeoutSeconds)];
  return {
    seatId: "halogen",
    meterPath,
    render: (item: WorkItem): SeatDispatch => ({
      argv,
      stdin: JSON.stringify({
        // MEASURED 2026-09-23 by reading the wrapper itself: it refuses any
        // request whose `model` is not the stable id "utility", and it rewrites
        // that id to the concrete served model on the way out and back. Item 12
        // omitted the field, so the rendered request would have been refused by
        // the wrapper with rc 1 before it ever reached the server. The stable id
        // is not an endpoint, a host:port or a concrete model name: the point of
        // DESIGN section 12 stands unchanged.
        model: UTILITY_MODEL_ID,
        messages: [{ role: "user", content: item.prompt }],
        // Also MEASURED from the wrapper: it translates a top-level `think:
        // false` into Halogen's `enable_thinking: false`. Halogen reasons by
        // default and its token budget covers the reasoning, so without this the
        // budget is spent on reasoning_content and the answer comes back empty.
        // An empty reply is indistinguishable from a failed dispatch, and this
        // seat exists to produce a checkable one.
        think: false,
      }),
    }),
    /**
     * The wrapper writes one chat-completions response object on stdout. The
     * reply is `choices[0].message.content`; anything else is transport.
     */
    replyOf: (stdout: string): string => {
      const parsed: unknown = JSON.parse(stdout);
      const content = (parsed as { choices?: { message?: { content?: unknown } }[] })
        ?.choices?.[0]?.message?.content;
      if (typeof content !== "string") {
        throw new Error("halogen stdout carries no choices[0].message.content string");
      }
      return content;
    },
  };
}

/**
 * The stable model id the wrapper accepts, and the only one it accepts. Nix
 * owns the concrete served model behind it; this repository never names that.
 */
export const UTILITY_MODEL_ID = "utility";

/** How many characters of the stdin payload a dry run shows. */
export const DRY_RUN_STDIN_CHARS = 200;

/** Shell-quote one argv element for display only. Never fed to a shell. */
function show(arg: string): string {
  return /^[A-Za-z0-9_@%+=:,./-]+$/.test(arg) ? arg : JSON.stringify(arg);
}

/** The argv exactly as it would be executed, one space between elements. */
export function renderArgv(d: SeatDispatch): string {
  return d.argv.map(show).join(" ");
}

/**
 * Dry run: print the argv that would be executed and the first 200 characters
 * of the stdin payload, and execute nothing. Newlines in the excerpt are
 * escaped so that one dispatch is always one line.
 */
export function dryRunLines(seatId: string, d: SeatDispatch): readonly string[] {
  const head = d.stdin.slice(0, DRY_RUN_STDIN_CHARS);
  const truncated = d.stdin.length > DRY_RUN_STDIN_CHARS;
  return [
    `DRYRUN seat=${seatId} argv: ${renderArgv(d)}`,
    `DRYRUN seat=${seatId} stdin[0:${DRY_RUN_STDIN_CHARS}] (${d.stdin.length} chars${
      truncated ? ", truncated" : ""
    }): ${JSON.stringify(head)}`,
  ];
}

export type SeatMode = "dry-run" | "spawn";

/**
 * The live-spawn allow list, and the whole safety boundary of item 26.
 *
 * `halogen` and nothing else. This is a default in code rather than a
 * convention in a brief, so that a caller who passes `mode: "spawn"` and
 * `allowSpawn: true` still cannot spend a seat by forgetting a rule.
 *
 * Why halogen and only halogen:
 *
 *  - `halogen` runs through /run/current-system/sw/bin/utility-model, which
 *    forwards one request to the Halogen server on the worker. It is local
 *    compute on Tom's own hardware, it spends no metered allocation, and its
 *    meter row (gpu-worker.json) is a slot row of capacity one carrying no cap.
 *    One short prompt through it costs nothing anybody has to decide about.
 *
 *  - `cc` spends Tom's Claude weekly allocation. Spending a seat from inside a
 *    test is a live dispatch nobody ruled on. Nothing authorizes a test harness
 *    to consume the allocation the run itself is budgeted against, and the
 *    orchestrator's own stop rule watches that same meter.
 *
 *  - `codex` is worse. The one Codex login on this box is not Tom's:
 *    codex.json carries "owner": "third-party". That is a third party's login.
 *    It is not Tom's to spend and it is certainly not a test harness's.
 */
/**
 * FROZEN. The review of 2026-09-23 (A-01) demonstrated that an unfrozen array
 * typed `readonly` is a compile-time promise and nothing more: one
 * `(DEFAULT_LIVE_SPAWN_SEATS as string[]).push("cc")` anywhere in the process
 * widened the gate for every caller, without passing `allowSpawnSeats` and
 * without editing this file. The contents are unchanged: halogen, and nothing else.
 */
export const DEFAULT_LIVE_SPAWN_SEATS: readonly string[] = Object.freeze(["halogen"]);

/**
 * Prose for a refusal, per seat. The GATE is the allow list above and nothing
 * else; this table only supplies the sentence, so that a refusal reads as a
 * decision with a reason rather than as an omission. A seat absent from the
 * table is still refused, with the generic sentence.
 */
export const LIVE_SPAWN_DENIAL_REASON: Readonly<Record<string, string>> = {
  cc: 'the cc seat spends Tom\'s Claude weekly allocation, and spending a seat from inside a test is a live dispatch nobody ruled on',
  codex: 'the one Codex login on this box is not Tom\'s (codex.json carries "owner": "third-party"), so it is not a test harness\'s to spend',
};

/** Default child timeout. Data, overridable at every call site. */
export const DEFAULT_SPAWN_TIMEOUT_MS = 60_000;

/** How many characters of captured child output a ledger line carries. */
export const SPAWN_CAPTURE_CHARS = 2000;

/** What one child process did. Everything the ledger needs, and nothing else. */
export interface SpawnOutcome {
  readonly stdout: string;
  readonly stderr: string;
  /** null when the child was killed by a signal or never started. */
  readonly exitCode: number | null;
  readonly signal: string | null;
  readonly timedOut: boolean;
  readonly timeoutMs: number;
  /** Set when the child could not be started at all. */
  readonly error: string | undefined;
}

/**
 * The one impure call, injectable so that a test exercises the spawn PATH
 * without exercising a seat. Deliberately shaped like `spawnSync`.
 */
export type SpawnFn = (
  file: string,
  args: readonly string[],
  opts: { readonly input: string; readonly timeoutMs: number },
) => SpawnOutcome;

/**
 * The real spawner: one synchronous child, stdin fed the payload the adapter
 * rendered, stdout and stderr captured, a mandatory timeout.
 *
 * `spawnSync` is used rather than an async child on purpose. It keeps
 * `executeDispatch` synchronous, so item 12's signature and every call site
 * survive unchanged, and it matches the rest of this repository, which reads
 * files synchronously and holds no Fiber, Queue or Scope anywhere.
 *
 * On timeout `spawnSync` kills the child with `killSignal` and still returns
 * what it captured before the kill. That capture is kept: a timed-out dispatch
 * that produced 40 characters of stderr is more useful than one that produced
 * a thrown exception.
 *
 * The ledger is NOT a secret store. This function copies a child's stdout and
 * stderr into a ledger line, so anything a seat's command prints lands there.
 * No adapter in this repository passes a credential on its argv or its stdin:
 * `cc` passes an env unset, `codex` a working directory, `halogen` a stable
 * model id, and all three carry the prompt on stdin. A seat that ever needed a
 * credential would have to take it from the environment, and its ledger lines
 * would have to be reviewed before they were persisted anywhere shared.
 */
function spawnSyncAdapter(
  file: string,
  args: readonly string[],
  opts: { readonly input: string; readonly timeoutMs: number },
): SpawnOutcome {
  // The child dies with this process (setpriv --pdeathsig KILL; successor
  // review r4: after kill -9 of the watcher the dispatch ran on, and the
  // restart ran it again beside it).
  // The wrapper would turn a missing command into its own exit 127, so the
  // command is resolved first and a missing one is the ENOENT it always was.
  if (!executable(file)) {
    return { stdout: "", stderr: "", exitCode: null, signal: null, timedOut: false, timeoutMs: opts.timeoutMs, error: `spawnSync ${file} ENOENT` };
  }
  const [cmd, ...rest] = [...PDEATHSIG_WRAPPER, file, ...args] as [string, ...string[]];
  const r = spawnSync(cmd, rest, {
    input: opts.input,
    timeout: opts.timeoutMs,
    killSignal: "SIGKILL",
    encoding: "utf8",
    maxBuffer: 8 * 1024 * 1024,
    // No shell. The argv the adapter rendered is executed unchanged.
    shell: false,
  });
  const timedOut =
    r.error !== undefined && r.error !== null && (r.error as NodeJS.ErrnoException).code === "ETIMEDOUT";
  return {
    stdout: typeof r.stdout === "string" ? r.stdout : "",
    stderr: typeof r.stderr === "string" ? r.stderr : "",
    exitCode: r.status,
    signal: r.signal,
    timedOut,
    timeoutMs: opts.timeoutMs,
    error: timedOut ? undefined : r.error ? String((r.error as Error).message) : undefined,
  };
}

export interface ExecuteOptions {
  readonly mode: SeatMode;
  /** Where dry-run output goes. Injected so tests capture it. */
  readonly print?: (line: string) => void;
  /**
   * Gate two. Spawning is refused unless this is explicitly true. Dry run is
   * the default everywhere. It is set in exactly two places: the one live test,
   * and `makeHalogenOutcomeOf` in `src/live.ts`, which is the live end-to-end
   * path and is itself gated on AX_CONWIP_LIVE_HALOGEN=1.
   */
  readonly allowSpawn?: boolean;
  /**
   * Gate three. The seats a live spawn may touch. Defaults to
   * DEFAULT_LIVE_SPAWN_SEATS, which is ["halogen"].
   */
  readonly allowSpawnSeats?: readonly string[];
  /** Mandatory in effect: unset means DEFAULT_SPAWN_TIMEOUT_MS, never unbounded. */
  readonly timeoutMs?: number;
  /** Injected spawner, so a test drives the spawn path without a seat. */
  readonly spawn?: SpawnFn;
}

export interface ExecuteResult {
  readonly seatId: string;
  readonly spawned: boolean;
  readonly lines: readonly string[];
  /** Present exactly when `spawned` is true. */
  readonly outcome?: SpawnOutcome;
  /** The seat's own reading of its stdout, when it declares one. */
  readonly reply?: string;
  /** Why `replyOf` produced nothing, when it did not. */
  readonly replyError?: string;
}

/**
 * Carry out one dispatch.
 *
 * Dry run is the default: it prints and returns `spawned: false`, and nothing
 * is executed. A live spawn is opt in THREE times, and every gate refuses by
 * throwing with the reason named:
 *
 *   1. `mode: "spawn"`.
 *   2. `allowSpawn: true`.
 *   3. the seat is on `allowSpawnSeats`, which defaults to ["halogen"].
 *
 * The spawner does not originate a command line. It executes the argv the
 * adapter rendered, unchanged and element for element, exactly as `renderArgv`
 * displays it, with no shell between the two.
 */
export function executeDispatch(
  adapter: SeatAdapter,
  d: SeatDispatch,
  opts: ExecuteOptions = { mode: "dry-run" },
): ExecuteResult {
  if (opts.mode === "dry-run") {
    const lines = dryRunLines(adapter.seatId, d);
    const print = opts.print ?? ((l: string) => console.log(l));
    for (const l of lines) print(l);
    return { seatId: adapter.seatId, spawned: false, lines };
  }

  // Gate two.
  if (opts.allowSpawn !== true) {
    throw new Error(
      `refusing to spawn on seat ${adapter.seatId}: mode "spawn" requires allowSpawn: true`,
    );
  }

  // Gate three: the seat rule. Live dispatch is permitted on halogen only.
  const allowed = opts.allowSpawnSeats ?? DEFAULT_LIVE_SPAWN_SEATS;
  // A-01/A-02 of the 2026-09-23 review. `Array.isArray` is the gate, not a type
  // annotation: a caller who passed the STRING "halogen,cc" turned the
  // membership test into `"halogen,cc".includes("cc")`, which is a substring
  // match and was true. A list of seats is a list, and anything else is refused.
  if (!Array.isArray(allowed)) {
    throw new Error(
      `refusing to spawn on seat ${adapter.seatId}: allowSpawnSeats must be an array of seat ids, got ${typeof allowed}`,
    );
  }
  if (!allowed.includes(adapter.seatId)) {
    const why =
      LIVE_SPAWN_DENIAL_REASON[adapter.seatId] ??
      "the seat is not on the live-spawn allow list, and an absent seat is a refusal rather than a default";
    throw new Error(
      `refusing to spawn on seat ${adapter.seatId}: not on the live-spawn allow list [${allowed.join(", ")}]: ${why}`,
    );
  }

  const timeoutMs = opts.timeoutMs ?? DEFAULT_SPAWN_TIMEOUT_MS;
  if (!Number.isFinite(timeoutMs) || timeoutMs <= 0) {
    throw new Error(
      `refusing to spawn on seat ${adapter.seatId}: timeoutMs must be a positive finite number, got ${String(timeoutMs)}`,
    );
  }

  const file = d.argv[0];
  if (file === undefined) {
    throw new Error(`refusing to spawn on seat ${adapter.seatId}: the adapter rendered an empty argv`);
  }

  const spawn = opts.spawn ?? spawnSyncAdapter;
  const outcome = spawn(file, d.argv.slice(1), { input: d.stdin, timeoutMs });

  let reply: string | undefined;
  let replyError: string | undefined;
  if (adapter.replyOf !== undefined && outcome.exitCode === 0 && !outcome.timedOut) {
    try {
      reply = adapter.replyOf(outcome.stdout);
    } catch (e) {
      replyError = (e as Error).message;
    }
  }

  const lines = [
    `SPAWN seat=${adapter.seatId} argv: ${renderArgv(d)}`,
    `SPAWN seat=${adapter.seatId} exit=${String(outcome.exitCode)} signal=${String(outcome.signal)} timedOut=${outcome.timedOut} timeoutMs=${outcome.timeoutMs} stdout=${outcome.stdout.length}ch stderr=${outcome.stderr.length}ch`,
  ];
  const print = opts.print ?? ((l: string) => console.log(l));
  for (const l of lines) print(l);

  return { seatId: adapter.seatId, spawned: true, lines, outcome, reply, replyError };
}
