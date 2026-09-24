/**
 * `microvm`: the job runs in a one-shot microvm.nix guest, built as a
 * `declaredRunner` and booted in the foreground. Two halves, deliberately apart:
 *
 * 1. Build. A small flake is generated per job shape (vcpu, memory, the job
 *    directory, the credential mounts) and `nix build` produces the runner. The
 *    flake holds host PATHS as strings, never file contents, so no credential
 *    and no prompt enters the store: the job's argv and stdin live in the job
 *    directory, shared into the guest over 9p at boot.
 * 2. Boot. Only when `/dev/kvm` is readable and writable AND the process is in
 *    a private user namespace (the runtime-test wrapper). Otherwise the runner
 *    refuses clearly after the build, naming what is missing. Today the wrapper
 *    has no `--dev-bind /dev/kvm` (dotfiles#453), so the boot half is refused on
 *    this fleet by construction, and qemu would fail loudly without kvm anyway.
 *
 * The guest runs `/job/run.sh` as root, writes `/job/exit`, `/job/stdout`,
 * `/job/stderr` and powers off.
 */
import { accessSync, closeSync, constants, existsSync, fstatSync, mkdirSync, openSync, readFileSync, readSync, writeFileSync } from "node:fs";

/** Read a guest-written file: O_NOFOLLOW, a regular file only, at most `max` bytes. "" when absent or refused. */
export function readJobFile(path: string, max = 16 * 1024 * 1024): string {
  let fd: number;
  try {
    fd = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  } catch (e) {
    const code = (e as NodeJS.ErrnoException).code;
    if (code === "ENOENT") return "";
    return `[runner: refused to read ${path}: ${code === "ELOOP" ? "a symlink" : code}]`;
  }
  try {
    const st = fstatSync(fd);
    if (!st.isFile()) return `[runner: refused to read ${path}: not a regular file]`;
    const n = Math.min(st.size, max);
    const buf = Buffer.alloc(n);
    let off = 0;
    while (off < n) {
      const r = readSync(fd, buf, off, n - off, off);
      if (r <= 0) break;
      off += r;
    }
    return buf.subarray(0, off).toString("utf8") + (st.size > max ? `\n[runner: truncated at ${max} of ${st.size} bytes]` : "");
  } finally {
    closeSync(fd);
  }
}
import { homedir } from "node:os";
import { join } from "node:path";
import { createHash } from "node:crypto";
import { refuseCommon, refusal, type Job, type ProcessJob, type Runner, type RunResult } from "./job.ts";
import { runProc, shq } from "./proc.ts";
import { DEFAULT_TIMEOUT_MS } from "./host.ts";
import { resolveInStore } from "./gvisor.ts";

/** The dotfiles pins (flake.lock), as measured by the 2026-09-23 lane. */
export const DEFAULT_NIXPKGS = "github:NixOS/nixpkgs/e2587caef70cea85dd97d7daab492899902dbf5d";
export const DEFAULT_MICROVM = "github:microvm-nix/microvm.nix/fa5340ac684cdce8a22b6d4a0bcebb0cc999275e";

export interface MicrovmOptions {
  readonly nixpkgs?: string;
  readonly microvm?: string;
  readonly vcpu?: number;
  readonly memMiB?: number;
  /**
   * /etc/hosts text whose non-loopback entries the guest gets, so it resolves fleet short
   * names (pi's Halogen base URL is http://worker:8731) the way the host does. The qemu
   * user-net DNS forwards to the host resolver without the host's hosts file (G1 follow-up,
   * MEASURED 2026-09-23: "worker" did not resolve in the guest). Default: the host's /etc/hosts.
   */
  readonly hosts?: string;
  readonly state?: string;
  readonly timeoutMs?: number;
  /** nix binary; tests pass a fake. */
  readonly nix?: string;
  /** Injected boot gate for tests. Default: `kvmGate()`. */
  readonly gate?: () => string | undefined;
}

/** Why a boot may not happen here, or undefined when it may. */
export function kvmGate(): string | undefined {
  try {
    accessSync("/dev/kvm", constants.R_OK | constants.W_OK);
  } catch {
    return "/dev/kvm is not reachable here (runtime-test mounts a minimal /dev without kvm; --dev-bind is dotfiles#453)";
  }
  let uidMap = "";
  try {
    uidMap = readFileSync("/proc/self/uid_map", "utf8").trim();
  } catch {
    /* no procfs: treat as not wrapped */
  }
  if (/^0\s+0\s+4294967295$/.test(uidMap) || uidMap === "") {
    return "not inside runtime-test (no private user namespace); boots run only under ~/.local/bin/runtime-test";
  }
  return undefined;
}

/**
 * Guest RAM in MiB. Exactly 2048 hangs the qemu microvm guest at `ACPI: Core revision` with a
 * garbage DSDT (microvm.nix issue 171; G1, MEASURED 2026-09-23), so 2048 becomes 2047.
 */
export const DEFAULT_MEM_MIB = 2047;
export function guestMemMiB(memMiB?: number): number {
  const m = memMiB ?? DEFAULT_MEM_MIB;
  return m === 2048 ? 2047 : m;
}

/** The non-loopback, well-formed lines of a hosts file: `ip name...`, comments dropped. */
export function guestHostsText(text: string): string {
  const out: string[] = [];
  for (const raw of text.split("\n")) {
    const f = raw.replace(/#.*/, "").trim().split(/\s+/).filter(Boolean);
    if (f.length < 2) continue;
    const [ip, ...names] = f;
    if (!/^[0-9a-fA-F.:]+$/.test(ip!) || ip!.startsWith("127.") || ip === "::1") continue;
    if (!names.every((n) => /^[A-Za-z0-9.-]+$/.test(n))) continue;
    out.push(`${ip} ${names.join(" ")}`);
  }
  return out.join("\n");
}

function hostEtcHosts(): string {
  try {
    return readFileSync("/etc/hosts", "utf8");
  } catch {
    return "";
  }
}

const nixStr = (s: string) => JSON.stringify(s).replace(/\$\{/g, "\\${");

/** The guest flake. Only paths and sizes: no job content. */
export function guestFlake(job: ProcessJob, o: MicrovmOptions): string {
  const shares = [
    `{ proto = "9p"; tag = "ro-store"; source = "/nix/store"; mountPoint = "/nix/.ro-store"; readOnly = true; }`,
    `{ proto = "9p"; tag = "job"; source = ${nixStr(job.jobDir)}; mountPoint = "/job"; }`,
    ...(job.mounts ?? []).map(
      (m, i) =>
        `{ proto = "9p"; tag = "m${i}"; source = ${nixStr(m.source)}; mountPoint = ${nixStr(m.target)}; readOnly = ${m.mode === "ro"}; }`,
    ),
  ];
  const hosts = guestHostsText(o.hosts ?? "");
  const hostsLine = hosts ? `          networking.extraHosts = ${nixStr(hosts + "\n")};\n` : "";
  return `{
  # Generated by @substrate/runners microvm adapter. Paths only; no job content.
  inputs.nixpkgs.url = ${nixStr(o.nixpkgs ?? DEFAULT_NIXPKGS)};
  inputs.microvm.url = ${nixStr(o.microvm ?? DEFAULT_MICROVM)};
  inputs.microvm.inputs.nixpkgs.follows = "nixpkgs";
  outputs = { self, nixpkgs, microvm }: {
    nixosConfigurations.job = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        microvm.nixosModules.microvm
        ({ pkgs, ... }: {
          system.stateVersion = "25.11";
          networking.hostName = "axc-job";
${hostsLine}          microvm = {
            hypervisor = "qemu";
            vcpu = ${o.vcpu ?? 2};
            mem = ${guestMemMiB(o.memMiB)};
            interfaces = [ { type = "user"; id = "qemu"; mac = "02:00:00:00:00:01"; } ];
            shares = [
              ${shares.join("\n              ")}
            ];
          };
          systemd.services.axc-job = {
            wantedBy = [ "multi-user.target" ];
            after = [ "network-online.target" ];
            wants = [ "network-online.target" ];
            serviceConfig.Type = "oneshot";
            script = "rc=0; \${pkgs.bash}/bin/bash /job/run.sh || rc=$?; echo $rc > /job/exit; \${pkgs.systemd}/bin/systemctl poweroff";
          };
        })
      ];
    };
    packages.x86_64-linux.default = self.nixosConfigurations.job.config.microvm.declaredRunner;
  };
}
`;
}

/** run.sh inside the guest: argv exactly, stdin from the job dir, streams apart. */
export function guestScript(job: ProcessJob, argv0: string = job.argv[0]!): string {
  const env = Object.entries(job.env ?? {}).map(([k, v]) => `export ${k}=${shq(v)}`);
  return [
    "#!/usr/bin/env bash",
    "cd /job",
    "export HOME=/root",
    "export IS_SANDBOX=1 # root inside a deliberate sandbox; see gvisor.ts",
    ...env,
    `${[argv0, ...job.argv.slice(1)].map(shq).join(" ")} < /job/.stdin > /job/stdout 2> /job/stderr`,
    "",
  ].join("\n");
}

export function microvmRunner(name: string, o: MicrovmOptions = {}): Runner {
  const state = o.state ?? join(homedir(), ".local/state/substrate/microvm");
  const refuses = (job: Job): string | undefined => {
    const c = refuseCommon(job);
    if (c) return c;
    if (job.kind !== "process") return `${name} runs process jobs only`;
    for (const m of job.mounts ?? []) if (!existsSync(m.source)) return `mount source ${m.source} does not exist`;
    const a0 = resolveInStore(job.argv[0]!);
    if (typeof a0 !== "string") return a0.error;
    return undefined;
  };
  /** Build the runner for a job; returns the store path or an error. */
  const build = async (job: ProcessJob, signal?: AbortSignal) => {
    const flake = guestFlake(job, { ...o, hosts: o.hosts ?? hostEtcHosts() });
    const key = createHash("sha256").update(flake).digest("hex").slice(0, 16);
    const dir = join(state, "flakes", key);
    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, "flake.nix"), flake);
    const r = await runProc({
      argv: [o.nix ?? "nix", "build", "--no-link", "--print-out-paths", `path:${dir}#default`],
      timeoutMs: 20 * 60 * 1000,
      signal,
    });
    const out = r.stdout.trim().split("\n").pop() ?? "";
    return r.exitCode === 0 && out.startsWith("/nix/store/")
      ? { runner: out, flakeDir: dir, buildMs: r.durationMs }
      : { error: `nix build failed (rc ${r.exitCode}): ${r.stderr.slice(-800)}`, flakeDir: dir };
  };
  return {
    name,
    type: "microvm",
    refuses,
    async run(job, signal): Promise<RunResult> {
      const why = refuses(job);
      if (why || job.kind !== "process") return refusal(name, job, why ?? "unreachable");
      mkdirSync(job.jobDir, { recursive: true });
      writeFileSync(join(job.jobDir, "run.sh"), guestScript(job, resolveInStore(job.argv[0]!) as string), { mode: 0o755 });
      writeFileSync(join(job.jobDir, ".stdin"), job.stdin ?? "");
      const b = await build(job, signal);
      if ("error" in b) return { ...refusal(name, job, b.error ?? "build failed"), detail: { flakeDir: b.flakeDir } };
      const gate = (o.gate ?? kvmGate)();
      const detail = { runner: b.runner, flakeDir: b.flakeDir, buildMs: String(b.buildMs) };
      if (gate) return { ...refusal(name, job, `built ${b.runner}; not booted: ${gate}`), detail };
      const r = await runProc({
        argv: [join(b.runner, "bin/microvm-run")],
        cwd: b.flakeDir,
        timeoutMs: job.timeoutMs ?? o.timeoutMs ?? DEFAULT_TIMEOUT_MS,
        signal,
        ...(job.cancelGraceMs !== undefined ? { cancelGraceMs: job.cancelGraceMs } : {}),
      });
      // The guest owns /job (a rw 9p share): a file there may be a symlink it
      // planted to a host path. Read only regular files, never through a link,
      // and capped (successor review 2026-09-23).
      const read = (f: string) => readJobFile(join(job.jobDir, f));
      const exit = read("exit").trim();
      return {
        runtime: name,
        jobId: job.id,
        exitCode: /^\d+$/.test(exit) ? Number(exit) : r.exitCode === 0 ? 1 : r.exitCode,
        stdout: read("stdout"),
        stderr: read("stderr") + (exit ? "" : `\n[runner: guest wrote no exit file; qemu rc ${r.exitCode}]\n${r.stderr.slice(-2000)}\n[guest console, last 3000 bytes]\n${r.stdout.slice(-3000)}`),
        durationMs: r.durationMs,
        timedOut: r.timedOut,
        detail,
      };
    },
  };
}
