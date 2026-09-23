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
  /** Default `rw` (Tom, 2026-09-21: a rw seat config mount). */
  mode: Schema.optionalKey(Schema.Literals(["ro", "rw"])),
  /**
   * What a sandboxed runtime (gvisor, microvm) sees of the seat config: only
   * the credential file in a scratch config dir (`credential`, default since
   * the 2026-09-23 successor review), or the whole dir (`dir`, the literal
   * 09-21 form, which lets a job rewrite host hooks). A ruling question for Tom.
   */
  scope: Schema.optionalKey(Schema.Literals(["credential", "dir"])),
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
});
export type RuntimesFile = typeof RuntimesFile.Type;

/** The decoded, checked, path-expanded configuration. */
export interface RuntimesConfig {
  readonly default: string;
  readonly phases: Readonly<Record<string, string>>;
  readonly credentials: { readonly claude: string; readonly mode: "ro" | "rw"; readonly scope: "credential" | "dir" };
  readonly runtimes: Readonly<Record<string, Runtime>>;
  /** The call-override allow list, when the file has one. */
  readonly allow?: readonly string[];
  /** harness -> seat, from `[seats]`. */
  readonly seats: Readonly<Record<string, string>>;
  /** Where it came from, for receipts. */
  readonly source: string;
  /** The model allowlist; absent means DEFAULT_MODEL_ALLOWLIST. */
  readonly models?: ModelAllowlist;
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
    },
    runtimes,
    ...(file.allow !== undefined ? { allow: file.allow } : {}),
    seats: file.seats ?? {},
    source,
    ...(file.models !== undefined ? { models: file.models } : {}),
  };
  const problems: string[] = [...(file.models !== undefined ? modelAllowlistProblems(file.models) : [])];
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
  readonly via: "call" | "phase" | "default";
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
    if (call.runtime !== base.name) {
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
