/**
 * `gvisor`: the job runs in a gVisor sandbox through `runsc run` on a generated
 * OCI bundle. This is the direct path the 2026-09-23 lane measured working
 * rootless (rc propagated, rw worktree bind, $HOME hidden); the Kubernetes path
 * through ax and Agent Substrate reaches nothing today and is the `ax` seam.
 *
 * What the sandbox sees, and nothing else:
 *   - an empty read-only root
 *   - `/nix/store` read-only (every binary the job names must resolve into it)
 *   - the job directory read-write at `/work`, which is the working directory
 *   - each job mount at its target (the seat credential rw by default), bound
 *     from the host path: the bytes never enter the bundle
 *   - the network (successor review r4: the old default, the host's network
 *     namespace, let a job reach every loopback-only service on the host,
 *     Chrome DevTools on 127.0.0.1:9222 included):
 *       `isolated` (default): runsc runs inside its own network namespace made
 *         by pasta with no gateway mapping and no port forwards (`--no-map-gw
 *         -T none -U none`): the host's loopback is unreachable; egress goes
 *         out through pasta's host sockets; DNS reaches the host resolver on
 *         port 53 only (`--dns-forward`), through a generated resolv.conf
 *       `none`: loopback only, no egress
 *       `host`: the host's network namespace, loopback included; only when the
 *         runtime table names it
 *
 * runsc state lives under `--root` (default `~/.local/state/substrate/runsc`),
 * never under $XDG_RUNTIME_DIR, so a job can never touch a live session's
 * runtime directory.
 */
import { procStartTicks, sameProcess } from "./proc.ts";
import { accessSync, constants, existsSync, mkdirSync, readdirSync, readFileSync, realpathSync, rmSync, statSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { delimiter, dirname, join } from "node:path";
import { randomBytes } from "node:crypto";
import { refuseCommon, refusal, type Job, type ProcessJob, type Runner, type RunResult } from "./job.ts";
import { runProc } from "./proc.ts";
import { DEFAULT_TIMEOUT_MS } from "./host.ts";

export interface GvisorOptions {
  readonly runsc: string;
  readonly state?: string;
  readonly network?: GvisorNetwork;
  /** The pasta binary for `network = "isolated"`. Default: `pasta` on PATH. */
  readonly pasta?: string;
  readonly timeoutMs?: number;
  /** $HOME inside the sandbox. Default `/home/agent`. */
  readonly home?: string;
}

export const SANDBOX_HOME = "/home/agent";

export type GvisorNetwork = "isolated" | "host" | "none";
/** The default network: never the host's namespace. */
export const DEFAULT_GVISOR_NETWORK: GvisorNetwork = "isolated";
/** The in-namespace address pasta answers DNS on (forwarded to the host resolver, port 53 only). */
export const PASTA_DNS = "169.254.1.53";

/** pasta's argv prefix: its own user and network namespace, no gateway mapping, no port forwards in or out. */
export function pastaArgv(pasta: string, hostResolver: string | undefined): string[] {
  return [
    pasta,
    "--config-net",
    "--no-map-gw",
    "-t", "none",
    "-u", "none",
    "-T", "none",
    "-U", "none",
    "--dns-forward", PASTA_DNS,
    ...(hostResolver ? ["--dns-host", hostResolver] : []),
    "--quiet",
    "--",
  ];
}

/** The host's first nameserver (the address pasta forwards DNS to). */
function hostResolver(): string | undefined {
  try {
    const m = /^\s*nameserver\s+(\S+)/m.exec(readFileSync("/etc/resolv.conf", "utf8"));
    return m?.[1];
  } catch {
    return undefined;
  }
}

/**
 * Resolve argv[0] on the host to the real store path the sandbox will exec.
 * Returns an error string when it does not land in /nix/store, because nothing
 * else of the host root is visible inside.
 */
export function resolveInStore(cmd: string, pathEnv = process.env.PATH ?? ""): string | { error: string } {
  const candidates = cmd.includes("/") ? [cmd] : pathEnv.split(delimiter).filter(Boolean).map((d) => join(d, cmd));
  for (const c of candidates) {
    try {
      accessSync(c, constants.X_OK);
      const real = realpathSync(c);
      if (!real.startsWith("/nix/store/")) return { error: `${cmd} resolves to ${real}, outside /nix/store; the sandbox cannot see it` };
      return real;
    } catch {
      /* try the next */
    }
  }
  return { error: `${cmd} is not an executable on PATH` };
}

const hostFile = (p: string): string | undefined => {
  try {
    return realpathSync(p);
  } catch {
    return undefined;
  }
};

interface OciMount {
  destination: string;
  type: string;
  source: string;
  options?: string[];
}

/**
 * The caller's PATH, translated for the sandbox: each directory that resolves
 * into /nix/store (profile and system-path dirs do) is kept by its store path,
 * which the ro store bind makes visible; the rest is dropped. An agent's tools
 * (bash, git, rg, coreutils) are then the host's own, with no image to build.
 */
export function storePath(pathEnv = process.env.PATH ?? ""): string[] {
  const out: string[] = [];
  for (const d of pathEnv.split(delimiter).filter(Boolean)) {
    const real = hostFile(d);
    if (real?.startsWith("/nix/store/") && !out.includes(real)) out.push(real);
  }
  return out;
}

/** The OCI runtime config for one job. Pure except for resolving host files named by path. */
export function ociConfig(
  job: ProcessJob,
  argv0: string,
  o: Pick<GvisorOptions, "network" | "home"> & { readonly hostPath?: string; readonly resolvConf?: string } = {},
): Record<string, unknown> {
  const network = o.network ?? DEFAULT_GVISOR_NETWORK;
  const home = o.home ?? SANDBOX_HOME;
  const bind = (source: string, destination: string, mode: "ro" | "rw"): OciMount => ({
    destination,
    type: "bind",
    source,
    options: ["rbind", mode],
  });
  const mounts: OciMount[] = [
    { destination: "/proc", type: "proc", source: "proc" },
    { destination: "/dev", type: "tmpfs", source: "tmpfs" },
    { destination: "/sys", type: "sysfs", source: "sysfs", options: ["nosuid", "noexec", "nodev", "ro"] },
    { destination: "/tmp", type: "tmpfs", source: "tmpfs" },
    bind("/nix/store", "/nix/store", "ro"),
    bind(job.jobDir, "/work", "rw"),
  ];
  // /bin/sh and /usr/bin/env are the two absolute paths tools assume (node's
  // shell:true, #! lines); both are bound read-only from their store files.
  for (const [dest, cmd] of [["/bin/sh", "sh"], ["/usr/bin/env", "env"]] as const) {
    const real = resolveInStore(cmd, o.hostPath);
    if (typeof real === "string") mounts.push(bind(real, dest, "ro"));
  }
  const shell = resolveInStore("bash", o.hostPath);
  const env: Record<string, string> = {
    PATH: [dirname(argv0), ...(job.env?.PATH ? job.env.PATH.split(":") : storePath(o.hostPath))].filter((d, i, a) => a.indexOf(d) === i).join(":"),
    ...(typeof shell === "string" ? { SHELL: shell } : {}),
    HOME: home,
    TMPDIR: "/tmp",
    // The process is uid 0 inside a deliberate sandbox. Claude Code refuses
    // --dangerously-skip-permissions as root unless told so (MEASURED 2026-09-23:
    // "cannot be used with root/sudo privileges"); IS_SANDBOX=1 is that statement.
    IS_SANDBOX: "1",
  };
  if (network !== "none") {
    for (const f of ["/etc/resolv.conf", "/etc/hosts"]) {
      // isolated: the generated resolv.conf names pasta's DNS forwarder.
      const real = f === "/etc/resolv.conf" && network === "isolated" ? o.resolvConf : hostFile(f);
      if (real) mounts.push(bind(real, f, "ro"));
    }
    const ca = hostFile("/etc/ssl/certs/ca-certificates.crt");
    if (ca?.startsWith("/nix/store/")) {
      env.SSL_CERT_FILE = ca;
      env.NIX_SSL_CERT_FILE = ca;
    }
  }
  for (const m of job.mounts ?? []) mounts.push(bind(m.source, m.target, m.mode));
  for (const [k, v] of Object.entries(job.env ?? {})) if (k !== "PATH") env[k] = v;
  const caps = ["CAP_AUDIT_WRITE", "CAP_KILL", "CAP_NET_BIND_SERVICE"];
  const namespaces: { type: string }[] = [{ type: "pid" }, { type: "ipc" }, { type: "uts" }, { type: "mount" }];
  if (network === "none") namespaces.push({ type: "network" });
  return {
    ociVersion: "1.0.0",
    process: {
      user: { uid: 0, gid: 0 },
      args: [argv0, ...job.argv.slice(1)],
      env: Object.entries(env).map(([k, v]) => `${k}=${v}`),
      cwd: "/work",
      capabilities: { bounding: caps, effective: caps, inheritable: caps, permitted: caps },
      rlimits: [{ type: "RLIMIT_NOFILE", hard: 4096, soft: 4096 }],
      noNewPrivileges: true,
      terminal: false,
    },
    root: { path: "rootfs", readonly: true },
    hostname: "axc-gvisor",
    mounts,
    linux: { namespaces },
  };
}

export function runscArgv(o: GvisorOptions, state: string, bundle: string, containerId: string): string[] {
  const network = o.network ?? DEFAULT_GVISOR_NETWORK;
  // isolated: runsc uses the namespace pasta made (its "host" is pasta's netns).
  return [
    ...(network === "isolated" ? pastaArgv(o.pasta ?? "pasta", hostResolver()) : []),
    o.runsc,
    "--rootless",
    `--network=${network === "isolated" ? "host" : network}`,
    `--root=${state}`,
    "run",
    "--bundle",
    bundle,
    containerId,
  ];
}

/** The owner record every bundle carries, so a dead runner's bundle and runsc state can be found. */
export const GVISOR_OWNER = "owner.json";

/**
 * Remove the bundles (and `runsc delete --force` the containers) whose owning
 * runner is gone: kill -9 or SIGHUP skips the runner's finally block, and the
 * shared state root accumulated bundles, locks, state files and sockets
 * (successor review r5). A bundle with no owner record is swept only when it
 * is older than `orphanAgeMs` (a live runner writes the record right after
 * mkdir). Returns one line per bundle removed.
 */
export async function sweepGvisorBundles(state: string, runsc: string, orphanAgeMs = 60_000): Promise<string[]> {
  const dir = join(state, "bundles");
  let names: string[];
  try {
    names = readdirSync(dir);
  } catch {
    return [];
  }
  const out: string[] = [];
  for (const id of names) {
    const b = join(dir, id);
    let owner: { runnerPid?: number; runnerStart?: string } | undefined;
    try {
      owner = JSON.parse(readFileSync(join(b, GVISOR_OWNER), "utf8"));
    } catch {
      owner = undefined;
    }
    if (owner !== undefined) {
      if (owner.runnerPid === process.pid || sameProcess(owner.runnerPid, owner.runnerStart)) continue;
    } else {
      try {
        if (Date.now() - statSync(b).mtimeMs < orphanAgeMs) continue;
      } catch {
        continue;
      }
    }
    await runProc({ argv: [runsc, "--rootless", `--root=${state}`, "delete", "--force", id], timeoutMs: 10000 });
    rmSync(b, { recursive: true, force: true });
    out.push(`${id}: gVisor runner gone; container deleted, bundle removed`);
  }
  return out;
}

export function gvisorRunner(name: string, o: GvisorOptions): Runner {
  const state = o.state ?? join(homedir(), ".local/state/substrate/runsc");
  const refuses = (job: Job): string | undefined => {
    const c = refuseCommon(job);
    if (c) return c;
    if (job.kind !== "process") return `${name} runs process jobs only`;
    if (state.startsWith("/run/user")) return `runsc --root ${state} is under /run/user; refused`;
    if (!existsSync(o.runsc)) return `runsc not found at ${o.runsc} (no host declares gvisor yet; build one: nix build nixpkgs#gvisor)`;
    if ((o.network ?? DEFAULT_GVISOR_NETWORK) === "isolated") {
      const found = o.pasta !== undefined ? existsSync(o.pasta) : typeof resolveInStore("pasta") === "string";
      if (!found) {
        return `network = "isolated" needs pasta (passt), not found${o.pasta ? ` at ${o.pasta}` : " on PATH"}; declare it, or name network = "none" (no egress) or "host" (the host's loopback too) in the runtime table`;
      }
    }
    const a0 = resolveInStore(job.argv[0]!);
    if (typeof a0 !== "string") return a0.error;
    for (const m of job.mounts ?? []) {
      if (!existsSync(m.source)) return `mount source ${m.source} does not exist`;
    }
    return undefined;
  };
  return {
    name,
    type: "gvisor",
    refuses,
    async run(job, signal): Promise<RunResult> {
      const why = refuses(job);
      if (why || job.kind !== "process") return refusal(name, job, why ?? "unreachable");
      const argv0 = resolveInStore(job.argv[0]!) as string;
      const containerId = `axc-${job.id}-${randomBytes(3).toString("hex")}`.slice(0, 120);
      // Earlier runners killed before their finally block left bundles here (r5).
      await sweepGvisorBundles(state, o.runsc);
      const bundle = join(state, "bundles", containerId);
      mkdirSync(join(bundle, "rootfs"), { recursive: true });
      writeFileSync(join(bundle, GVISOR_OWNER), JSON.stringify({ runnerPid: process.pid, runnerStart: procStartTicks(process.pid), containerId, state }) + "\n");
      mkdirSync(job.jobDir, { recursive: true });
      const network = o.network ?? DEFAULT_GVISOR_NETWORK;
      const pasta = network === "isolated" ? (o.pasta ?? (resolveInStore("pasta") as string)) : undefined;
      let resolvConf: string | undefined;
      if (network === "isolated") {
        resolvConf = join(bundle, "resolv.conf");
        writeFileSync(resolvConf, `nameserver ${PASTA_DNS}\noptions edns0\n`);
      }
      const cfg = JSON.stringify(ociConfig(job, argv0, { ...o, ...(resolvConf ? { resolvConf } : {}) }), null, 1);
      writeFileSync(join(bundle, "config.json"), cfg);
      // The receipt keeps the exact bundle config (paths only, never credential bytes).
      writeFileSync(join(job.jobDir, ".gvisor-config.json"), cfg);
      try {
        const r = await runProc({
          argv: runscArgv({ ...o, ...(pasta ? { pasta } : {}) }, state, bundle, containerId),
          stdin: job.stdin,
          timeoutMs: job.timeoutMs ?? o.timeoutMs ?? DEFAULT_TIMEOUT_MS,
          signal,
          ...(job.cancelGraceMs !== undefined ? { cancelGraceMs: job.cancelGraceMs } : {}),
          // The runsc and pasta tree is recorded like a host job's, so reapProcFiles finds it.
          ...(job.procFile ? { procFile: job.procFile } : {}),
        });
        return { runtime: name, jobId: job.id, ...r, detail: { containerId, config: join(job.jobDir, ".gvisor-config.json"), runsc: o.runsc, network } };
      } finally {
        // runsc run removes a container that exits; a killed one needs a forced delete.
        await runProc({ argv: [o.runsc, "--rootless", `--root=${state}`, "delete", "--force", containerId], timeoutMs: 10000 });
        rmSync(bundle, { recursive: true, force: true });
      }
    },
  };
}
