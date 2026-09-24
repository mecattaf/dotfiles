/**
 * Transcript retention (guardrail 1; AUDIT-transcripts 2026-09-24, TX1 and TX3).
 *
 * Every agent() call leaves its harness transcript in a per-job archive dir
 * OUTSIDE the run dir (run dirs under ~/today are landed into notes and pushed
 * nightly, so a transcript that may echo a tool's output never goes there):
 *
 *   <transcriptRoot>/<runId>/<jobId>/
 *     harness.stdout      what the harness printed (claude's json envelope, codex's --json events, pi's text)
 *     harness.stderr      its stderr
 *     claude-<sid>.jsonl  the Claude Code session, copied from the seat shadow (gvisor, microvm) or found by
 *                         session id under the host CLAUDE_CONFIG_DIR (host, runtime-test, herdr)
 *     codex-<tid>.jsonl   the codex rollout, found by thread id under $CODEX_HOME/sessions (host only)
 *     pi-...              anything a sandboxed pi left under pi-agent/sessions (pi runs --no-session today)
 *
 * The shadow belongs to the job, which could plant symlinks to host files in
 * it: every copy opens with O_NOFOLLOW, accepts regular files only, never
 * descends a symlinked directory, and is capped (head plus tail, marked).
 * Archiving never throws into the call: a failure is reported, never fatal.
 */
import { closeSync, constants as fsc, existsSync, fstatSync, fsyncSync, lstatSync, mkdirSync, openSync, readdirSync, readSync, writeSync } from "node:fs";
import { createHash } from "node:crypto";
import { dirname, join, relative } from "node:path";

/** Per-file cap on the local copy (AUDIT-transcripts, Unknowns: 64 MB locally). */
export const DEFAULT_TRANSCRIPT_CAP = 64 * 1024 * 1024;
/** How many files one job may archive from a shadow (a job could plant thousands). */
export const MAX_TRANSCRIPT_FILES = 64;

export interface TranscriptFile {
  /** File name inside the job's archive dir. */
  readonly name: string;
  readonly path: string;
  readonly bytes: number;
  readonly sha256: string;
  /** Where it came from: a path relative to the shadow, or "stdout", "stderr", "host-session", "codex-rollout". */
  readonly source: string;
  readonly truncated?: true;
}

/** The archive root: beside the seat shadows, `~/.local/state/substrate/transcripts` for the default layout. */
export function transcriptRootFor(seatShadowRoot: string, override?: string): string {
  return override ?? process.env.SUBSTRATE_TRANSCRIPT_ROOT ?? join(dirname(seatShadowRoot), "transcripts");
}

const MARK = (dropped: number) => `\n[substrate: ${dropped} bytes elided between head and tail; the transcript was over the cap]\n`;

function readRange(fd: number, pos: number, len: number): Buffer {
  const b = Buffer.alloc(len);
  let got = 0;
  while (got < len) {
    const n = readSync(fd, b, got, len - got, pos + got);
    if (n === 0) break;
    got += n;
  }
  return b.subarray(0, got);
}

/** Write bytes to a fresh 0600 file (never through a link, never over a file) and fsync it. */
function writeNew(path: string, data: Buffer): void {
  const fd = openSync(path, fsc.O_WRONLY | fsc.O_CREAT | fsc.O_EXCL | fsc.O_NOFOLLOW, 0o600);
  try {
    let off = 0;
    while (off < data.length) off += writeSync(fd, data, off, data.length - off);
    fsyncSync(fd);
  } finally {
    closeSync(fd);
  }
}

/** Cap a buffer: head plus tail with a marker between. */
export function capBytes(data: Buffer, cap: number): { data: Buffer; truncated: boolean } {
  if (data.length <= cap) return { data, truncated: false };
  const half = Math.max(0, Math.floor(cap / 2) - 128);
  return { data: Buffer.concat([data.subarray(0, half), Buffer.from(MARK(data.length - 2 * half)), data.subarray(data.length - half)]), truncated: true };
}

function record(dest: string, name: string, data: Buffer, source: string, truncated: boolean): TranscriptFile {
  const path = join(dest, name);
  writeNew(path, data);
  return { name, path, bytes: data.length, sha256: createHash("sha256").update(data).digest("hex"), source, ...(truncated ? { truncated: true as const } : {}) };
}

/**
 * Copy one file into `dest/name`: opened with O_NOFOLLOW, regular files only,
 * capped (head plus tail). Undefined when the source is not a regular file.
 */
export function copyCapped(src: string, dest: string, name: string, source: string, cap = DEFAULT_TRANSCRIPT_CAP): TranscriptFile | undefined {
  let fd: number;
  try {
    fd = openSync(src, fsc.O_RDONLY | fsc.O_NOFOLLOW | fsc.O_NONBLOCK);
  } catch {
    return undefined; // ELOOP (a symlink), ENOENT, EACCES
  }
  try {
    const st = fstatSync(fd);
    if (!st.isFile()) return undefined; // a FIFO or device a job planted is never read
    const size = st.size;
    const half = Math.max(0, Math.floor(cap / 2) - 128);
    const data = size <= cap ? readRange(fd, 0, size) : Buffer.concat([readRange(fd, 0, half), Buffer.from(MARK(size - 2 * half)), readRange(fd, size - half, half)]);
    return record(dest, name, data, source, size > cap);
  } finally {
    closeSync(fd);
  }
}

/** Store text the runner holds in memory (stdout, stderr) as an archive file, capped. Empty text is skipped. */
export function storeText(dest: string, name: string, text: string, source: string, cap = DEFAULT_TRANSCRIPT_CAP): TranscriptFile | undefined {
  if (text === "") return undefined;
  const c = capBytes(Buffer.from(text, "utf8"), cap);
  return record(dest, name, c.data, source, c.truncated);
}

const safeName = (s: string) => s.replace(/[^A-Za-z0-9_.-]/g, "_").slice(0, 160);

/**
 * Walk `root` without following links: regular files whose path (relative to
 * `root`) passes `want`, at most `max`, depth-bounded.
 */
function walk(root: string, want: (rel: string) => boolean, max = MAX_TRANSCRIPT_FILES, depth = 8): string[] {
  const out: string[] = [];
  const go = (dir: string, d: number) => {
    if (d > depth || out.length >= max) return;
    let names: string[];
    try {
      names = readdirSync(dir).sort();
    } catch {
      return;
    }
    for (const n of names) {
      if (out.length >= max) return;
      const p = join(dir, n);
      let st;
      try {
        st = lstatSync(p);
      } catch {
        continue;
      }
      if (st.isSymbolicLink()) continue;
      if (st.isDirectory()) go(p, d + 1);
      else if (st.isFile() && want(relative(root, p))) out.push(p);
    }
  };
  go(root, 0);
  return out;
}

/**
 * Copy what a harness left in a job's seat shadow: Claude Code sessions
 * (`projects/**\/*.jsonl`, also subagent transcripts) and pi sessions
 * (`pi-agent/sessions/**`). Never the credential, settings or anything else.
 */
export function archiveShadowTranscripts(shadow: string, dest: string, cap = DEFAULT_TRANSCRIPT_CAP): TranscriptFile[] {
  if (!existsSync(shadow)) return [];
  const want = (rel: string) => (rel.startsWith("projects/") && rel.endsWith(".jsonl")) || rel.startsWith("pi-agent/sessions/");
  const files = walk(shadow, want);
  if (files.length === 0) return [];
  mkdirSync(dest, { recursive: true, mode: 0o700 });
  const out: TranscriptFile[] = [];
  for (const f of files) {
    const rel = relative(shadow, f);
    const name = rel.startsWith("projects/") ? `claude-${safeName(rel.slice("projects/".length).replace(/\//g, "__"))}` : `pi-${safeName(rel.slice("pi-agent/sessions/".length).replace(/\//g, "__"))}`;
    if (existsSync(join(dest, name))) continue;
    const t = copyCapped(f, dest, name, rel, cap);
    if (t) out.push(t);
  }
  return out;
}

/** The host session file of a Claude Code session: `<configDir>/projects/<slug>/<sid>.jsonl`, found by id. */
export function findClaudeSession(configDir: string, sessionId: string): string | undefined {
  if (!/^[A-Za-z0-9-]{8,80}$/.test(sessionId)) return undefined;
  const projects = join(configDir, "projects");
  let slugs: string[];
  try {
    slugs = readdirSync(projects);
  } catch {
    return undefined;
  }
  for (const s of slugs) {
    const p = join(projects, s, `${sessionId}.jsonl`);
    try {
      if (lstatSync(p).isFile()) return p;
    } catch {
      /* not in this project */
    }
  }
  return undefined;
}

/** A codex rollout by thread id: `<codexHome>/sessions/YYYY/MM/DD/rollout-...-<tid>.jsonl`. */
export function findCodexRollout(codexHome: string, threadId: string): string | undefined {
  if (!/^[A-Za-z0-9-]{8,80}$/.test(threadId)) return undefined;
  const hits = walk(join(codexHome, "sessions"), (rel) => rel.endsWith(`${threadId}.jsonl`), 1, 4);
  return hits[0];
}

/** Sum of a job's archive, for the receipt. */
export const transcriptSummary = (files: readonly TranscriptFile[]) =>
  files.map((f) => ({ name: f.name, path: f.path, bytes: f.bytes, sha256: f.sha256, source: f.source, ...(f.truncated ? { truncated: true } : {}) }));
