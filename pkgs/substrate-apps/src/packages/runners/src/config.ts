/**
 * The runtimes file: the whole user-facing configuration of where agent() calls
 * run. One TOML file, default path `~/.config/substrate/runtimes.toml`
 * (override with `AX_CONWIP_RUNTIMES`). A missing file is not an error: every
 * call then runs on `host`, which is what a workflow did before runtimes existed.
 *
 * The smallest useful file is one line:
 *
 *     default = "gvisor"
 *
 * plus the `[runtime.gvisor]` table naming the runsc binary. Everything else has
 * a default. Selection for one call, first match wins:
 *
 *     agent(prompt, { runtime: "gvisor" })   // the call names it
 *     [phases] "Review" = "gvisor"           // the phase in force names it
 *     default = "gvisor"                     // the file names it
 *     "host"                                 // nothing names it
 *
 * `ssh:<host>` is available without a table (harness claude) to the file's own
 * `default` and `[phases]`; a table named `"ssh:worker"` overrides it, for
 * example to pick the pi harness.
 *
 * A call's own `runtime` is CONFINED (successor review 2026-09-23: a script's
 * agent({runtime:'host'}) escaped a gvisor default). It must name a runtime
 * on the file's `allow` list when the file has one; without a list it must be
 * a declared `[runtime.<name>]` table (the built-ins `host` and `ssh:<host>`
 * are open to a call only when the default is itself host), and it may never
 * leave a sandboxed default or phase runtime (gvisor, microvm) for host,
 * herdr or ssh. `allow = [...]` is the one way to permit that.
 *
 * `[seats]` binds each harness to the capacity seat it spends, e.g.
 * `claude = "cc"`, `pi = "halogen"`. The CONWIP gates a call on the seat of the
 * harness that will actually run it.
 */
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { Schema } from "effect";
import { parse as parseToml } from "smol-toml";
import { modelAllowlistProblems, type ModelAllowlist } from "./models.ts";

const Harness = Schema.Literals(["claude", "pi", "codex"]);

/** Fields every runtime table may carry. */
const common = {
  /** Which harness CLI an agent() call runs as. Default `claude`. */
  harness: Schema.optionalKey(Harness),
  /** Per-job wall clock ceiling in ms. Default 30 minutes. */
  timeoutMs: Schema.optionalKey(Schema.Int),
  /**
   * The capacity seat a call on this runtime spends, preferred over `[seats]`.
   * An ssh runtime spends the REMOTE login, so a claude call on ssh with no
   * seat here is bound to no seat (never the local [seats].claude).
   */
  seat: Schema.optionalKey(Schema.String),
  /**
   * codex's own sandbox for its tool calls. Default `read-only`; an
   * implementation node that must write in its job dir names
   * `workspace-write`. Only on a codex-harness table.
   */
  codexSandbox: Schema.optionalKey(Schema.Literals(["read-only", "workspace-write"])),
};

export const HostRuntime = Schema.Struct({ type: Schema.Literal("host"), ...common });

export const HerdrRuntime = Schema.Struct({
  type: Schema.Literal("herdr"),
  ...common,
  /** herdr's NDJSON socket. Default `$HERDR_SOCKET_PATH`, else `~/.config/herdr/herdr.sock`. */
  socket: Schema.optionalKey(Schema.String),
  /** `action`: a plugin action, herdr reports exit_code/stdout/stderr natively (default). `pane`: a visible pane, sentinel capture. */
  mode: Schema.optionalKey(Schema.Literals(["action", "pane"])),
  /** Plugin id the action lives in. Default `substrate-runner`. */
  plugin: Schema.optionalKey(Schema.String),
  /** Link the plugin on first use. Default false: linking changes the server's plugin set, so it is an explicit act. */
  autoLink: Schema.optionalKey(Schema.Boolean),
});

export const GvisorRuntime = Schema.Struct({
  type: Schema.Literal("gvisor"),
  ...common,
  /** Absolute path of the runsc binary (a nix-built gvisor until a dotfiles module declares one). */
  runsc: Schema.String,
  /** runsc `--root`. Never under $XDG_RUNTIME_DIR. Default `~/.local/state/substrate/runsc`. */
  state: Schema.optionalKey(Schema.String),
  /**
   * `isolated` (default): its own network namespace through pasta, egress
   * only, the host's loopback unreachable. `none`: loopback only. `host`: the
   * host's namespace, loopback services included; only when named here.
   */
  network: Schema.optionalKey(Schema.Literals(["isolated", "host", "none"])),
  /** The pasta binary for `isolated`. Default: `pasta` on PATH. */
  pasta: Schema.optionalKey(Schema.String),
  /**
   * false: no seat credential is mounted (default true); desk context, being
   * read-only, still is.
   * A claude harness is refused on such a table; the reserved runtime name
   * `locked` must be a gVisor table with credential = false and a network
   * other than `host` (guardrail: untrusted input never sees a seat).
   */
  credential: Schema.optionalKey(Schema.Boolean),
});

export const MicrovmRuntime = Schema.Struct({
  type: Schema.Literal("microvm"),
  ...common,
  /** microvm.nix flake ref. Default the dotfiles pin. */
  microvm: Schema.optionalKey(Schema.String),
  /** nixpkgs flake ref. Default the dotfiles pin. */
  nixpkgs: Schema.optionalKey(Schema.String),
  vcpu: Schema.optionalKey(Schema.Int),
  memMiB: Schema.optionalKey(Schema.Int),
  /** false: no seat credential is mounted (see the gVisor table). */
  credential: Schema.optionalKey(Schema.Boolean),
});

export const SshRuntime = Schema.Struct({
  type: Schema.Literal("ssh"),
  ...common,
  /** ssh destination (an ssh_config Host). */
  host: Schema.String,
});

export const WorkerdRuntime = Schema.Struct({
  type: Schema.Literal("workerd"),
  ...common,
  /** Absolute workerd binary. When absent, built from `flake`. */
  workerd: Schema.optionalKey(Schema.String),
  /** Flake installable for workerd. Default `github:mecattaf/workerd.nix#workerd`. */
  flake: Schema.optionalKey(Schema.String),
  compatibilityDate: Schema.optionalKey(Schema.String),
});

export const AxRuntime = Schema.Struct({
  type: Schema.Literal("ax"),
  ...common,
  /** Default `ultracode` (FIELD-MAP 5a). */
  atespace: Schema.optionalKey(Schema.String),
  /** Carried patch `sandbox_class`: empty means gvisor. */
  sandboxClass: Schema.optionalKey(Schema.Literals(["gvisor", "microvm"])),
  image: Schema.optionalKey(Schema.String),
});

/**
 * The host runtime inside `~/.local/bin/runtime-test`: a private /run/user tree and PID/IPC namespaces, the
 * checkout still writable. For jobs that source shell fragments, clean runtime directories or start test
 * compositors. When the wrapper is missing the job is refused, never run against the live runtime.
 */
export const RuntimeTestRuntime = Schema.Struct({
  type: Schema.Literal("runtime-test"),
  ...common,
  /** The wrapper. Default `~/.local/bin/runtime-test`. */
  wrapper: Schema.optionalKey(Schema.String),
});

export const Runtime = Schema.Union([
  HostRuntime,
  RuntimeTestRuntime,
  HerdrRuntime,
  GvisorRuntime,
  MicrovmRuntime,
  SshRuntime,
  WorkerdRuntime,
  AxRuntime,
]);
export type Runtime = typeof Runtime.Type;

export const Credentials = Schema.Struct({
  /** The Claude seat config dir, mounted (never copied) into runtimes that need it. Default `~/.claude`. */
  claude: Schema.optionalKey(Schema.String),
  /**
   * AUDIT-transcripts TX5: capacity seat id -> the Claude config dir that IS that seat, e.g.
   * `seat_dirs = { cc = "~/.claude", cc2 = "~/.claude-work" }`. When present, a claude call runs with the dir of the
   * seat its route spends (a runtime's `seat`, else `[seats].claude`, else the run's --seat), and a call whose seat
   * has no entry is refused: the gate must never admit on one seat while another seat's window is spent.
   */
  seat_dirs: Schema.optionalKey(Schema.Record(Schema.String, Schema.String)),
  /** Default `rw` (Tom, 2026-09-21: a rw seat config mount). */
  mode: Schema.optionalKey(Schema.Literals(["ro", "rw"])),
  /**
   * What a sandboxed runtime (gvisor, microvm) sees of the seat config: only
   * the credential file in a scratch config dir (`credential`, default since
   * the 2026-09-23 successor review), or the whole dir (`dir`, the literal
   * 09-21 form, which lets a job rewrite host hooks). A ruling question for Tom.
   */
  scope: Schema.optionalKey(Schema.Literals(["credential", "dir"])),
  /**
   * Seat id -> that seat's Claude config dir, e.g. `cc = "~/.claude"`,
   * `cc2 = "~/.claude-work"` (critique pass 2026-09-24, RG-1: one global
   * `claude` dir let a job gated and ledgered as cc2 spend cc). A claude job
   * mounts the dir of the seat it is gated on, never another. With this map
   * present every claude runtime with a local credential must name a seat in
   * it; without it `claude` serves only when it is set explicitly and at most
   * one claude seat is bound in the file.
   */
  seats: Schema.optionalKey(Schema.Record(Schema.String, Schema.String)),
  /**
   * Desk context bound READ-ONLY into a sandboxed (gVisor) job's config dir,
   * e.g. `["~/today/CLAUDE.md", "~/.claude/skills",
   * "~/mecattaf/dotfiles/home/agent-runtime-rules.md"]` (guardrail 5): the job
   * reads the rules, and cannot rewrite what the next host session runs.
   */
  context: Schema.optionalKey(Schema.Array(Schema.String)),
});

const Ceilings = Schema.Struct({
  five_hour: Schema.optionalKey(Schema.Number),
  seven_day: Schema.optionalKey(Schema.Number),
  model_scoped: Schema.optionalKey(Schema.Number),
});
const ModelEntrySchema = Schema.Struct({
  id: Schema.String,
  harness: Harness,
  aliases: Schema.optionalKey(Schema.Array(Schema.String)),
  default: Schema.optionalKey(Schema.Boolean),
  ceilings: Schema.optionalKey(Ceilings),
});

export const RuntimesFile = Schema.Struct({
  /** The model allowlist (models.ts). Absent: DEFAULT_MODEL_ALLOWLIST. */
  models: Schema.optionalKey(Schema.Array(ModelEntrySchema)),
  default: Schema.optionalKey(Schema.String),
  /** Runtimes a call may name with agent({runtime}). Absent: declared tables only, never an escalation. */
  allow: Schema.optionalKey(Schema.Array(Schema.String)),
  /** harness -> capacity seat id (claude, pi, codex). */
  seats: Schema.optionalKey(Schema.Record(Schema.String, Schema.String)),
  phases: Schema.optionalKey(Schema.Record(Schema.String, Schema.String)),
  credentials: Schema.optionalKey(Credentials),
  runtime: Schema.optionalKey(Schema.Record(Schema.String, Runtime)),
  /** G-BK1: SIGTERM-then-SIGKILL grace on cancel, stop, supersede or a lost lease. Default 10000; 0 kills at once. */
  cancel_grace_ms: Schema.optionalKey(Schema.Number),
  /**
   * G-BK8, Buildkite's agent lifecycle hooks. Operator-owned argv run on the
   * host around every agent() call; a job never supplies hooks. pre_start
   * exiting non-zero vetoes the call (its stderr is the reason); pre_exit runs
   * after the harness ends, even on cancel, to upload or preserve artifacts.
   * Each hook gets SUBSTRATE_JOB_ID, SUBSTRATE_JOB_DIR, SUBSTRATE_RUNTIME and,
   * for pre_exit, SUBSTRATE_EXIT_CODE and SUBSTRATE_ABORTED.
   */
  hooks: Schema.optionalKey(Schema.Struct({
    pre_start: Schema.optionalKey(Schema.Array(Schema.String)),
    pre_exit: Schema.optionalKey(Schema.Array(Schema.String)),
    timeout_ms: Schema.optionalKey(Schema.Number),
  })),
});
export type RuntimesFile = typeof RuntimesFile.Type;

/** The decoded, checked, path-expanded configuration. */
export interface RuntimesConfig {
  readonly default: string;
  readonly phases: Readonly<Record<string, string>>;
  readonly credentials: {
    readonly claude: string;
    readonly mode: "ro" | "rw";
    readonly scope: "credential" | "dir";
    /** Seat id -> Claude config dir (absolute): `[credentials.seats]` merged with the TX5 spelling `seat_dirs`. */
    readonly seats?: Readonly<Record<string, string>>;
    /** Whether `claude` was set by the file (true) or is the `~/.claude` default (false or absent). */
    readonly claudeExplicit?: boolean;
    /** Desk context paths (absolute) bound read-only into gVisor jobs. */
    readonly context?: readonly string[];
    /** Seats that `seat_dirs` and `[credentials.seats]` both name with different dirs (a load error). */
    readonly seatSpellingConflicts?: readonly string[];
  };
  readonly runtimes: Readonly<Record<string, Runtime>>;
  /** The call-override allow list, when the file has one. */
  readonly allow?: readonly string[];
  /** harness -> seat, from `[seats]`. */
  readonly seats: Readonly<Record<string, string>>;
  /** Where it came from, for receipts. */
  readonly source: string;
  /** The model allowlist; absent means DEFAULT_MODEL_ALLOWLIST. */
  readonly models?: ModelAllowlist;
  /** G-BK1: cancel grace for every runtime's harness (ms). Absent: DEFAULT_CANCEL_GRACE_MS. */
  readonly cancelGraceMs?: number;
  /** G-BK8: operator lifecycle hooks. */
  readonly hooks?: { readonly preStart?: readonly string[]; readonly preExit?: readonly string[]; readonly timeoutMs?: number };
}

export const DEFAULT_PATH = "~/.config/substrate/runtimes.toml";

export const expandHome = (p: string, home = homedir()): string =>
  p === "~" ? home : p.startsWith("~/") ? `${home}${p.slice(1)}` : p;

const SSH_SHORTHAND = /^ssh:([A-Za-z0-9][A-Za-z0-9_.@-]*)$/;

/** Look up a runtime by name: a table first, then the built-ins `host` and `ssh:<host>`. */
export function lookupRuntime(config: Pick<RuntimesConfig, "runtimes">, name: string): Runtime | undefined {
  const t = config.runtimes[name];
  if (t) return t;
  if (name === "host") return { type: "host" };
  const m = SSH_SHORTHAND.exec(name);
  if (m) return { type: "ssh", host: m[1]! };
  return undefined;
}

export class RuntimesConfigError extends Error {
  override readonly name = "RuntimesConfigError";
}

const PATH_KEYS = ["socket", "runsc", "state", "workerd"] as const;

/**
 * `[credentials.seats]` (RG-1) and `seat_dirs` (TX5) are two spellings of one map, merged at the 2026-09-24
 * integrate. A seat both name with different dirs is recorded and refused at load.
 */
function seatMaps(seats: Readonly<Record<string, string>> | undefined, seatDirs: Readonly<Record<string, string>> | undefined, home: string) {
  if (seats === undefined && seatDirs === undefined) return {};
  const a = Object.fromEntries(Object.entries(seats ?? {}).map(([k, v]) => [k, expandHome(v, home)]));
  const b = Object.fromEntries(Object.entries(seatDirs ?? {}).map(([k, v]) => [k, expandHome(v, home)]));
  const conflicts = Object.keys(b).filter((k) => a[k] !== undefined && a[k] !== b[k]);
  return { seats: { ...b, ...a }, ...(conflicts.length ? { seatSpellingConflicts: conflicts } : {}) };
}

/** Decode and check a parsed document. Throws RuntimesConfigError with every problem found. */
export function decodeRuntimes(doc: unknown, source: string, home = homedir()): RuntimesConfig {
  let file: RuntimesFile;
  try {
    file = Schema.decodeUnknownSync(RuntimesFile)(doc);
  } catch (e) {
    throw new RuntimesConfigError(`${source}: ${(e as Error).message}`);
  }
  const runtimes: Record<string, Runtime> = {};
  for (const [name, r] of Object.entries(file.runtime ?? {})) {
    const expanded: Record<string, unknown> = { ...r };
    for (const k of PATH_KEYS) {
      if (typeof expanded[k] === "string") expanded[k] = expandHome(expanded[k] as string, home);
    }
    runtimes[name] = expanded as Runtime;
  }
  const config: RuntimesConfig = {
    default: file.default ?? "host",
    phases: file.phases ?? {},
    credentials: {
      claude: expandHome(file.credentials?.claude ?? "~/.claude", home),
      mode: file.credentials?.mode ?? "rw",
      scope: file.credentials?.scope ?? "credential",
      ...seatMaps(file.credentials?.seats, file.credentials?.seat_dirs, home),
      ...(file.credentials?.claude !== undefined ? { claudeExplicit: true } : {}),
      ...(file.credentials?.context !== undefined ? { context: file.credentials.context.map((p) => expandHome(p, home)) } : {}),
    },
    runtimes,
    ...(file.allow !== undefined ? { allow: file.allow } : {}),
    seats: file.seats ?? {},
    source,
    ...(file.models !== undefined ? { models: file.models } : {}),
    ...(file.cancel_grace_ms !== undefined ? { cancelGraceMs: file.cancel_grace_ms } : {}),
    ...(file.hooks !== undefined ? { hooks: {
      ...(file.hooks.pre_start?.length ? { preStart: file.hooks.pre_start } : {}),
      ...(file.hooks.pre_exit?.length ? { preExit: file.hooks.pre_exit } : {}),
      ...(file.hooks.timeout_ms !== undefined ? { timeoutMs: file.hooks.timeout_ms } : {}),
    } } : {}),
  };
  const problems: string[] = [...(file.models !== undefined ? modelAllowlistProblems(file.models) : [])];
  if (file.cancel_grace_ms !== undefined && !(Number.isFinite(file.cancel_grace_ms) && file.cancel_grace_ms >= 0 && file.cancel_grace_ms <= 600_000))
    problems.push("cancel_grace_ms must be a number of milliseconds from 0 to 600000");
  if (file.hooks?.timeout_ms !== undefined && !(Number.isFinite(file.hooks.timeout_ms) && file.hooks.timeout_ms > 0 && file.hooks.timeout_ms <= 600_000))
    problems.push("hooks.timeout_ms must be a number of milliseconds from 1 to 600000");
  for (const k of ["pre_start", "pre_exit"] as const) {
    const h = file.hooks?.[k];
    if (h !== undefined && h.length > 0 && !h[0]!.startsWith("/")) problems.push(`hooks.${k} must be an argv whose first element is an absolute path`);
  }
  const known = (n: string) => lookupRuntime(config, n) !== undefined;
  if (!known(config.default)) problems.push(`default = ${JSON.stringify(config.default)} names no runtime`);
  for (const [phase, n] of Object.entries(config.phases)) {
    if (!known(n)) problems.push(`phases.${JSON.stringify(phase)} = ${JSON.stringify(n)} names no runtime`);
  }
  for (const [name, r] of Object.entries(runtimes)) {
    for (const k of PATH_KEYS) {
      const v = (r as Record<string, unknown>)[k];
      if (typeof v === "string" && !v.startsWith("/")) problems.push(`runtime.${name}.${k} must be absolute, got ${v}`);
    }
    if (r.type === "gvisor") {
      const st = r.state ?? "";
      if (st.startsWith("/run/user")) problems.push(`runtime.${name}.state must not live under /run/user`);
    }
  }
  for (const n of config.allow ?? []) if (!known(n)) problems.push(`allow names ${JSON.stringify(n)}, which is no runtime`);
  for (const h of Object.keys(config.seats)) if (!["claude", "pi", "codex"].includes(h)) problems.push(`seats.${h}: no such harness`);
  if (!config.credentials.claude.startsWith("/")) problems.push(`credentials.claude must be absolute`);
  problems.push(...guardrailProblems(config));
  for (const s of config.credentials.seatSpellingConflicts ?? []) problems.push(`credentials: seat ${s} has one dir in [credentials.seats] and another in seat_dirs`);
  const byDir = new Map<string, string>();
  for (const [seat, dir] of Object.entries(config.credentials.seats ?? {})) {
    const other = byDir.get(dir);
    if (other !== undefined) problems.push(`credentials.seats: ${other} and ${seat} name the same dir ${dir}; one config dir is one seat`);
    byDir.set(dir, seat);
  }
  if (problems.length) throw new RuntimesConfigError(`${source}:\n  ${problems.join("\n  ")}`);
  return config;
}

export function parseRuntimesToml(text: string, source = "<inline>", home = homedir()): RuntimesConfig {
  let doc: unknown;
  try {
    doc = parseToml(text);
  } catch (e) {
    throw new RuntimesConfigError(`${source}: TOML: ${(e as Error).message}`);
  }
  return decodeRuntimes(doc, source, home);
}

/** Load the runtimes file. A missing file at the default path means "everything on host". */
export function loadRuntimes(path?: string, home = homedir()): RuntimesConfig {
  const explicit = path ?? process.env.AX_CONWIP_RUNTIMES;
  const p = expandHome(explicit ?? DEFAULT_PATH, home);
  let text: string;
  try {
    text = readFileSync(p, "utf8");
  } catch (e) {
    if ((e as NodeJS.ErrnoException).code === "ENOENT" && explicit === undefined) {
      return decodeRuntimes({}, `${p} (absent: all calls on host)`, home);
    }
    throw new RuntimesConfigError(`${p}: ${(e as Error).message}`);
  }
  return parseRuntimesToml(text, p, home);
}

/** How a call's runtime was chosen, for the receipt. */
export interface Selection {
  readonly name: string;
  readonly runtime: Runtime;
  /** `seat`: the call named a seat (agent({seat}) or runs-on seat:X) and this is the one runtime that spends it. */
  readonly via: "call" | "phase" | "default" | "seat";
}

/** Pick the runtime for one agent() call. Throws when the call or phase names an unknown runtime. */
export function selectRuntime(
  config: RuntimesConfig,
  call: { readonly runtime?: unknown; readonly phase?: string | undefined },
): Selection {
  if (call.runtime !== undefined) {
    if (typeof call.runtime !== "string") {
      throw new RuntimesConfigError(`agent({runtime}) must be a string, got ${typeof call.runtime}`);
    }
    const r = lookupRuntime(config, call.runtime);
    if (!r) throw new RuntimesConfigError(`agent({runtime: ${JSON.stringify(call.runtime)}}) names no runtime in ${config.source}`);
    // A phase the floor refuses gives no base: the call is judged against the default.
    let base: Selection;
    try {
      base = baseSelection(config, call.phase);
    } catch {
      base = baseSelection(config, undefined);
    }
    const refuse = (why: string) => {
      throw new RuntimesConfigError(`agent({runtime: ${JSON.stringify(call.runtime)}}) refused: ${why} (${config.source})`);
    };
    if (call.runtime !== base.name && !isLockedTable(config, call.runtime)) {
      if (config.allow !== undefined) {
        if (!config.allow.includes(call.runtime)) refuse(`not on the file's allow list [${config.allow.join(", ")}]`);
      } else {
        if (config.runtimes[call.runtime] === undefined && base.runtime.type !== "host") {
          refuse(`the built-in ${call.runtime} is not declared and the ${base.via} runtime ${base.name} is not host`);
        }
        if (SANDBOXED.has(base.runtime.type) && ESCAPES.has(r.type)) {
          refuse(`a call may not leave the sandboxed ${base.via} runtime ${base.name} (${base.runtime.type}) for ${r.type}; list it in allow = [...] to permit that`);
        }
      }
    }
    return { name: call.runtime, runtime: r, via: "call" };
  }
  return baseSelection(config, call.phase);
}

const SANDBOXED = new Set<Runtime["type"]>(["gvisor", "microvm"]);
const ESCAPES = new Set<Runtime["type"]>(["host", "runtime-test", "herdr", "ssh"]);

/**
 * The runtime the file itself assigns: the phase's, else the default. The
 * phase map is a floor, never an escalation (successor review r4: a script in
 * a gVisor phase named another phase, mapped to host, and ran there; the
 * script controls its phase title): a phase may not take a call out of a
 * sandboxed default to host, herdr or ssh unless the file's allow list names
 * that runtime.
 */
function baseSelection(config: RuntimesConfig, phase: string | undefined): Selection {
  if (phase !== undefined) {
    const n = config.phases[phase];
    if (n !== undefined) {
      const r = lookupRuntime(config, n)!;
      const d = lookupRuntime(config, config.default)!;
      if (n !== config.default && SANDBOXED.has(d.type) && ESCAPES.has(r.type) && !(config.allow ?? []).includes(n)) {
        throw new RuntimesConfigError(
          `phase ${JSON.stringify(phase)} refused: its runtime ${n} (${r.type}) would take a call out of the sandboxed default ${config.default} (${d.type}); list ${n} in allow = [...] to permit that (${config.source})`,
        );
      }
      return { name: n, runtime: r, via: "phase" };
    }
  }
  return { name: config.default, runtime: lookupRuntime(config, config.default)!, via: "default" };
}

/** Runtime types whose claude harness reads a LOCAL seat config dir (credentialMount). */
export const LOCAL_CREDENTIAL = new Set<Runtime["type"]>(["host", "runtime-test", "herdr", "gvisor", "microvm"]);

/** The harness a runtime runs an agent() call with. */
export const harnessOf = (r: Runtime): "claude" | "pi" | "codex" => r.harness ?? "claude";

/** Whether a runtime table carries a seat credential at all (`credential = false` on gVisor or microvm says no). */
export const carriesCredential = (r: Runtime): boolean => !((r.type === "gvisor" || r.type === "microvm") && r.credential === false);

/**
 * The capacity seat a call on this runtime spends: the table's own `seat`,
 * else `[seats][harness]`, else (claude only) the run's --seat. An ssh claude
 * spends the remote login, so with no table seat it spends none here. codex
 * on ax is never rendered (backend.ts), so it spends none.
 */
export function seatOf(config: Pick<RuntimesConfig, "seats">, r: Runtime, defaultSeat?: string): string | undefined {
  const h = harnessOf(r);
  if (r.type === "ax" && h === "codex") return undefined;
  if (r.seat !== undefined) return r.seat;
  if (r.type === "ssh" && h === "claude") return undefined;
  return config.seats[h] ?? (h === "claude" ? defaultSeat : undefined);
}

/**
 * The Claude config dir a claude job gated on `seat` must spend (RG-1), or
 * why none can be named. With `[credentials.seats]`: that seat's entry, and a
 * seat not in it is refused. Without it: the explicit `[credentials].claude`
 * (decodeRuntimes has checked that at most one claude seat is bound), or,
 * for a call bound to no seat at all, the default dir. A bound seat against
 * the implicit `~/.claude` default is refused: nothing says that dir is the seat.
 */
export function credentialDirFor(
  config: Pick<RuntimesConfig, "credentials">,
  seat: string | undefined,
  /** The seat came from the run's --seat, not from the file: without a map it keeps the pre-RG-1 default dir (the receipt marks it). */
  fromRunSeat = false,
): { dir: string; unverified?: true } | { refused: string } {
  const map = config.credentials.seats ?? {};
  if (seat !== undefined && map[seat] !== undefined) return { dir: map[seat]! };
  if (Object.keys(map).length > 0) {
    return { refused: seat === undefined
      ? `a claude job bound to no capacity seat cannot pick a dir from [credentials.seats] (${Object.keys(map).join(", ")})`
      : `seat ${seat} has no Claude config dir in [credentials.seats] (declared: ${Object.keys(map).join(", ")}); a job gated on ${seat} never spends another seat's dir` };
  }
  if (seat === undefined || config.credentials.claudeExplicit === true) return { dir: config.credentials.claude };
  if (fromRunSeat) return { dir: config.credentials.claude, unverified: true };
  return { refused: `seat ${seat} is bound to no Claude config dir: declare [credentials.seats] ${seat} = "<dir>" (the implicit ${config.credentials.claude} default is not tied to any seat, so a job gated on ${seat} could spend another)` };
}

/** Load-time guardrail checks (critique pass 2026-09-24): seat credentials, locked, codexSandbox, context. */
function guardrailProblems(config: RuntimesConfig): string[] {
  const problems: string[] = [];
  const map = config.credentials.seats ?? {};
  for (const [s, d] of Object.entries(map)) if (!d.startsWith("/")) problems.push(`credentials.seats.${s} must be absolute, got ${d}`);
  const ctx = config.credentials.context ?? [];
  const names = new Set<string>();
  for (const c of ctx) {
    if (!c.startsWith("/")) problems.push(`credentials.context entry must be absolute, got ${c}`);
    const b = c.replace(/\/+$/, "").split("/").pop() ?? "";
    // The credential file's name is reserved: a context entry never shadows it.
    if (b === "" || b.startsWith(".credentials") || b === "context") problems.push(`credentials.context entry ${c} has a reserved or empty name`);
    if (names.has(b)) problems.push(`credentials.context has two entries named ${b}`);
    names.add(b);
  }
  // Every runtime a call can reach by default: the declared tables plus a built-in default.
  const reachable: Array<[string, Runtime]> = Object.entries(config.runtimes);
  if (config.runtimes[config.default] === undefined) {
    const d = lookupRuntime(config, config.default);
    if (d) reachable.push([config.default, d]);
  }
  const claudeSeats = new Set<string>();
  for (const [name, r] of reachable) {
    const h = harnessOf(r);
    if (r.codexSandbox !== undefined && h !== "codex") problems.push(`runtime.${name}.codexSandbox applies to the codex harness only (harness is ${h})`);
    if (!carriesCredential(r) && h === "claude") problems.push(`runtime.${name}: credential = false with the claude harness, which cannot run without a seat credential`);
    if (name === "locked") {
      if (r.type !== "gvisor") problems.push(`runtime.locked must be type = "gvisor" (got ${r.type}): the reserved name promises no credential and no host loopback`);
      else {
        if (r.credential !== false) problems.push(`runtime.locked must set credential = false`);
        if (r.network === "host") problems.push(`runtime.locked must not use network = "host"`);
      }
    }
    if (h !== "claude" || !LOCAL_CREDENTIAL.has(r.type) || !carriesCredential(r)) continue;
    const seat = seatOf(config, r);
    if (seat === undefined) continue; // bound at run time by --seat; credentialDirFor judges it then
    claudeSeats.add(seat);
    const d = credentialDirFor(config, seat);
    if ("refused" in d) problems.push(`runtime.${name}: ${d.refused}`);
  }
  if (Object.keys(map).length === 0 && config.credentials.claudeExplicit === true && claudeSeats.size > 1) {
    problems.push(`credentials.claude is one dir but the file binds ${claudeSeats.size} claude seats (${[...claudeSeats].join(", ")}); declare [credentials.seats]`);
  }
  return problems;
}

/**
 * A declared gVisor table with no credential and no host network: a call
 * moving INTO it gives up authority, so the allow list never bars it.
 */
function isLockedTable(config: Pick<RuntimesConfig, "runtimes">, name: string): boolean {
  const r = config.runtimes[name];
  return r !== undefined && r.type === "gvisor" && r.credential === false && r.network !== "host";
}

/** The routing opts of one agent() call (interpreter key.ts ROUTE_OPTS). */
export interface CallRoute {
  readonly runtime?: unknown;
  readonly seat?: unknown;
  readonly runsOn?: unknown;
  readonly phase?: string | undefined;
}

/**
 * Pick the runtime for one call from ALL its routing opts (critique pass
 * 2026-09-24, RG-2: `agent({seat:'codex'})` was keyed but ignored, and ran
 * claude). Honoured or refused, never dropped:
 *
 *   - `runsOn` is a list of `seat:<id>` and `runtime:<name>` labels (the
 *     floor's runs-on); any other label is refused here, where no holder
 *     matches labels.
 *   - a named runtime goes through selectRuntime's confinement; a named seat
 *     must then be the seat that runtime spends.
 *   - a seat alone picks the ONE runtime this file permits the call that
 *     spends that seat: the phase or default runtime when it does, else the
 *     unique permitted table. None, or several, is a refusal naming them.
 */
export function selectForCall(config: RuntimesConfig, call: CallRoute, defaultSeat?: string): Selection {
  const refuse = (why: string): never => {
    throw new RuntimesConfigError(`agent() route refused: ${why} (${config.source})`);
  };
  let runtime = call.runtime;
  let seat = call.seat;
  if (seat !== undefined && typeof seat !== "string") refuse(`agent({seat}) must be a string, got ${typeof seat}`);
  if (call.runsOn !== undefined) {
    if (!Array.isArray(call.runsOn) || call.runsOn.some((l) => typeof l !== "string")) refuse(`agent({runsOn}) must be an array of labels`);
    for (const l of call.runsOn as string[]) {
      const m = /^(seat|runtime):(.+)$/.exec(l);
      if (!m) refuse(`runs-on label ${JSON.stringify(l)} is neither seat:<id> nor runtime:<name>; a local dispatch cannot honour it`);
      const [, k, v] = m!;
      if (k === "seat") {
        if (seat !== undefined && seat !== v) refuse(`runs-on seat:${v} contradicts seat ${String(seat)}`);
        seat = v;
      } else {
        if (runtime !== undefined && runtime !== v) refuse(`runs-on runtime:${v} contradicts runtime ${String(runtime)}`);
        runtime = v;
      }
    }
  }
  if (runtime !== undefined) {
    const sel = selectRuntime(config, { runtime, phase: call.phase });
    if (seat !== undefined) {
      const spends = seatOf(config, sel.runtime, defaultSeat);
      if (spends !== seat) refuse(`runtime ${sel.name} spends seat ${spends ?? "(none)"}, not ${String(seat)}`);
    }
    return sel;
  }
  if (seat === undefined) return selectRuntime(config, { phase: call.phase });
  // The phase or default runtime wins when it already spends the seat (no move at all).
  let base: Selection | undefined;
  try {
    base = selectRuntime(config, { phase: call.phase });
  } catch {
    base = undefined;
  }
  if (base && seatOf(config, base.runtime, defaultSeat) === seat) return base;
  const names = [...new Set([...Object.keys(config.runtimes), ...(config.allow ?? []), config.default])];
  const matches: Selection[] = [];
  for (const n of names) {
    let sel: Selection;
    try {
      sel = selectRuntime(config, { runtime: n, phase: call.phase });
    } catch {
      continue; // not permitted to this call
    }
    if (seatOf(config, sel.runtime, defaultSeat) === seat) matches.push(sel);
  }
  if (matches.length === 0) {
    const served = names.map((n) => [n, lookupRuntime(config, n)] as const).filter(([, r]) => r).map(([n, r]) => `${n}=${seatOf(config, r!, defaultSeat) ?? "(none)"}`);
    refuse(`no runtime this file permits the call spends seat ${seat} (runtime=seat: ${served.join(", ")})`);
  }
  if (matches.length > 1) refuse(`seat ${seat} is spent by ${matches.length} permitted runtimes (${matches.map((m) => m.name).join(", ")}); name one with agent({runtime})`);
  return { ...matches[0]!, via: "seat" };
}
