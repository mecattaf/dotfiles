/** Launcher providers beside application and window search.
 * Clipboard and filesystem enumeration are explicit, separate requests;
 * ordinary command search never reads clipboard history or private files.
 */
import { run, type Run } from "./controller";
import { searchScore } from "./applications";
import { execFile, spawn } from "node:child_process";
import { lstat, opendir } from "node:fs/promises";
import { basename, isAbsolute, join } from "node:path";

const commands = {
  files: ["nautilus"],
  network: ["kitty", "--class", "network-settings", "nmtui"],
  audio: ["kitty", "--class", "audio-route-prompt", "-e", "audio-route"],
  accent: ["kitty", "--class", "theme-prompt", "-e", "theme-prompt", "accent"],
  herdr: ["herdr-picker"],
  workspaceNew: ["desktop-workspace", "new"],
  workspaceRestore: ["desktop-workspace", "restore"],
  workspaceRename: ["desktop-workspace", "rename"],
  screenshot: ["screenshot", "screen"],
  screenshotArea: ["screenshot", "area"],
  screenshotWindow: ["screenshot", "window"],
  color: ["colorpicker"],
  ocr: ["screen-ocr-area"],
  record: ["recording-toggle"],
  monitors: ["monitors-off"],
  mediaToggle: ["media", "play"],
  mediaPrevious: ["media", "prev"],
  mediaNext: ["media", "next"],
  volumeMute: ["volume", "mute"],
  microphoneMute: ["volume", "micmute"],
} as const;
export type ProviderAction =
  | { kind: "command"; name: keyof typeof commands }
  | { kind: "theme"; name: string }
  | { kind: "copy"; text: string }
  | { kind: "clipboard"; id: string }
  | { kind: "file"; path: string };
export interface ProviderItem {
  id: string;
  title: string;
  subtitle: string;
  keywords: string;
  action: ProviderAction;
}
const catalog: [keyof typeof commands, string, string, string][] = [
  ["files", "Files", "Open the file manager", "nautilus downloads documents"],
  ["network", "Network settings", "Configure NetworkManager", "wifi ethernet nmtui"],
  ["audio", "Audio output", "Choose the playback device", "sound route headphones speakers"],
  ["accent", "Wallpaper accent", "Choose wallpaper and folder colors", "palette theme"],
  ["herdr", "Herdr workspaces", "Find workspaces and agent status", "terminal session"],
  ["workspaceNew", "New Herdr workspace", "Create an empty dedicated workspace", "terminal"],
  ["workspaceRestore", "Restore Herdr workspace", "Reopen the last parked session", "terminal closed"],
  ["workspaceRename", "Rename workspace", "Name the current desktop workspace", "terminal"],
  ["screenshot", "Screenshot screen", "Capture the focused display", "capture image"],
  ["screenshotArea", "Screenshot area", "Select and annotate a region", "capture image"],
  ["screenshotWindow", "Screenshot window", "Capture and annotate the focused window", "capture image"],
  ["color", "Pick a color", "Copy the color under the pointer", "eyedropper clipboard"],
  ["ocr", "Copy text from screen", "Select an area for OCR", "image clipboard"],
  ["record", "Toggle screen recording", "Start or stop the existing recorder", "video capture"],
  ["monitors", "Turn monitors off", "Wake displays on the next input", "screen sleep dpms"],
  ["mediaToggle", "Play / pause", "Control the active media player", "music audio"],
  ["mediaPrevious", "Previous track", "Control the active media player", "music audio"],
  ["mediaNext", "Next track", "Control the active media player", "music audio"],
  ["volumeMute", "Mute / unmute audio", "Toggle the default audio output", "volume sound"],
  ["microphoneMute", "Mute / unmute microphone", "Toggle the default audio input", "mic sound"],
];

// Explicit migration gaps, not items pretending to provide native parity.
export const providerGaps = [
  "Chrome tab search still requires Vicinae's browser-extension bridge.",
  "Application tray menus still require a StatusNotifier host.",
  "File search is bounded filename search, not Vicinae's background index.",
  "Calculator supports arithmetic, not unit or currency conversion.",
  "Cliphist does not import Vicinae history, tagged retention, or its 24-hour eviction policy.",
] as const;

export type RunBytes = (command: string, args: string[], input?: Buffer) => Promise<Buffer>;
export const runBytes: RunBytes = (command, args, input) => new Promise((resolve, reject) => {
  const child = execFile(command, args, { encoding: "buffer", timeout: 5000, maxBuffer: 16 * 1024 * 1024 },
    (error, stdout, stderr) => error ? reject(new Error(stderr.toString().trim() || error.message)) : resolve(stdout));
  child.stdin?.on("error", reject);
  child.stdin?.end(input);
});

/** Interactive capture/terminal helpers outlive the launcher. Success here
 * means the executable started, not that the later interaction completed.
 * Keep stderr in the user service journal and never kill a prompt at 5s. */
export function launchProviderCommand(command: string, args: string[], spawnChild = spawn): Promise<string> {
  return new Promise((resolve, reject) => {
    const child = spawnChild(command, args, { detached: true, stdio: ["ignore", "inherit", "inherit"] });
    child.once("error", reject);
    child.once("spawn", () => { child.unref(); resolve(""); });
  });
}
const executeAction: Run = (command, args) => {
  if (["kitty", "herdr-picker", "screenshot", "screen-ocr-area", "recording-toggle", "monitors-off", "colorpicker", "nautilus"].includes(command) ||
      (command === "desktop-workspace" && args[0] === "rename"))
    return launchProviderCommand(command, args);
  // Theme reload hooks can wait on several already-running applications.
  if (command === "theme") return new Promise((resolve, reject) => {
    execFile(command, args, { timeout: 30000, maxBuffer: 1024 * 1024 },
      (error, stdout, stderr) => error ? reject(new Error(stderr.trim() || error.message)) : resolve(stdout));
  });
  return run(command, args);
};

export function parseClipboard(output: string, query = "", limit = 80): ProviderItem[] {
  const result: ProviderItem[] = [], seen = new Set<string>();
  for (const row of output.split(/\r?\n/)) {
    const tab = row.indexOf("\t"), id = row.slice(0, tab);
    if (tab < 1 || !/^[1-9]\d{0,19}$/.test(id) || seen.has(id)) continue;
    seen.add(id);
    const title = row.slice(tab + 1).replace(/[\x00-\x1f\x7f]/g, " ").slice(0, 500);
    if (searchScore(query, title) < 0) continue;
    result.push({ id: `clipboard:${id}`, title: title || "Clipboard entry", subtitle: "Copy to clipboard",
      keywords: "clipboard", action: { kind: "clipboard", id } });
    if (result.length >= Math.max(1, Math.min(limit, 200))) break;
  }
  return result;
}
export async function clipboardItems(query = "", execute: Run = run): Promise<ProviderItem[]> {
  try { return parseClipboard(await execute("cliphist", ["list"]), query); }
  catch (error) {
    // A new native history has no database until the first copied value.
    if (error instanceof Error && /please store something first/i.test(error.message)) return [];
    throw error;
  }
}

/** Read names/mtime only, never contents or symlink targets. A shallow bounded
 * scan is intentional: no index daemon, no recursive walk of the whole home. */
export async function fileItems(query: string, options: { home?: string; limit?: number; maxEntries?: number } = {}): Promise<ProviderItem[]> {
  const home = options.home ?? process.env.HOME;
  if (!home || !isAbsolute(home)) throw new Error("File search requires an absolute home directory");
  const budget = Math.max(1, Math.min(options.maxEntries ?? 2000, 10000));
  let visited = 0;
  const matches: { path: string; modified: number }[] = [];
  const queue = ["Downloads", "Documents"].map(name => ({ path: join(home, name), depth: 0 }));
  while (queue.length && visited < budget) {
    const current = queue.shift()!;
    try {
      if (!(await lstat(current.path)).isDirectory()) continue;
      const directory = await opendir(current.path);
      for await (const entry of directory) {
        if (++visited > budget) break;
        if (entry.name.startsWith(".") || entry.isSymbolicLink()) continue;
        const path = join(current.path, entry.name);
        if (entry.isDirectory() && current.depth < 3) queue.push({ path, depth: current.depth + 1 });
        if (!entry.isFile() || searchScore(query, entry.name, path.slice(home.length + 1)) < 0) continue;
        const stat = await lstat(path);
        if (stat.isFile()) matches.push({ path, modified: stat.mtimeMs });
      }
    } catch (error) {
      if (!["ENOENT", "EACCES", "ENOTDIR"].includes((error as NodeJS.ErrnoException).code ?? "")) throw error;
    }
  }
  return matches.sort((a, b) => b.modified - a.modified || a.path.localeCompare(b.path))
    .slice(0, Math.max(1, Math.min(options.limit ?? 80, 200))).map(({ path }) => ({
      id: `file:${path}`, title: basename(path), subtitle: path.slice(home.length + 1), keywords: "file",
      action: { kind: "file", path },
    }));
}

function themeName(name: string) {
  // Never pass helper verbs or path fragments as palette names.
  return /^[a-z][a-z0-9-]{0,63}$/.test(name) &&
    !["list", "apply", "icons", "toggle"].includes(name);
}
export async function listThemes(execute: Run = run): Promise<string[]> {
  return [...new Set((await execute("theme", ["list"])).split(/\r?\n/)
    .filter(themeName))];
}

/** Bounded recursive-descent arithmetic; no JavaScript evaluation or process. */
export function calculate(query: string): string | null {
  const input = query.trim().replace(/^=\s*/, "");
  if (!input || input.length > 256 || !/^[\d\s.eE+*/%^()−×÷-]+$/.test(input)) return null;
  const text = input.replaceAll("−", "-").replaceAll("×", "*").replaceAll("÷", "/");
  const tokens = text.match(/(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?|[()+*/%^\-]/g) ?? [];
  if (tokens.join("") !== text.replace(/\s/g, "")) return null;
  let at = 0;
  function primary(): number {
    if (tokens[at] === "(") {
      at++;
      const result = sum();
      if (tokens[at++] !== ")") throw new Error("Missing closing parenthesis");
      return result;
    }
    const token = tokens[at++];
    if (!token || !/^(?:\d|\.)/.test(token)) throw new Error("Expected number");
    return Number(token);
  }
  function power(): number {
    const lhs = primary();
    if (tokens[at] === "^") { at++; return lhs ** unary(); }
    return lhs;
  }
  function unary(): number {
    if (tokens[at] === "+") { at++; return unary(); }
    if (tokens[at] === "-") { at++; return -unary(); }
    return power();
  }
  function product(): number {
    let value = unary();
    while (["*", "/", "%"].includes(tokens[at] ?? "")) {
      const op = tokens[at++], rhs = unary();
      value = op === "*" ? value * rhs : op === "/" ? value / rhs : value % rhs;
    }
    return value;
  }
  function sum(): number {
    let value = product();
    while (["+", "-"].includes(tokens[at] ?? "")) {
      const op = tokens[at++], rhs = product();
      value = op === "+" ? value + rhs : value - rhs;
    }
    return value;
  }
  try {
    const value = sum();
    if (at !== tokens.length || !Number.isFinite(value)) return null;
    return String(Number(value.toPrecision(14)));
  } catch { return null; }
}

export function providerItems(query: string, options: { themeNames?: string[] } = {}): ProviderItem[] {
  const items: ProviderItem[] = catalog.map(([name, title, subtitle, keywords]) => ({
    id: `command:${name}`, title, subtitle, keywords, action: { kind: "command", name },
  }));
  for (const name of options.themeNames ?? []) {
    if (themeName(name)) items.push({ id: `theme:${name}`, title: `Theme: ${name}`,
      subtitle: "Apply the rendered desktop palette", keywords: "appearance color palette",
      action: { kind: "theme", name } });
  }
  const result = items.map(item => ({ item, score: searchScore(query, item.title, item.subtitle, item.keywords) }))
    .filter(row => row.score >= 0).sort((a, b) => b.score - a.score).map(row => row.item);
  const value = calculate(query);
  if (value !== null) result.unshift({ id: "calculator", title: value,
    subtitle: `${query.trim()} · Copy result`, keywords: "calculator arithmetic",
    action: { kind: "copy", text: value } });
  return result;
}

export async function activateProvider(action: ProviderAction, execute: Run = executeAction, bytes: RunBytes = runBytes): Promise<void> {
  switch (action.kind) {
    case "command": {
      if (!Object.hasOwn(commands, action.name)) throw new Error("Unknown launcher command");
      const [command, ...args] = commands[action.name];
      await execute(command, [...args]);
      return;
    }
    case "theme":
      if (!themeName(action.name)) throw new Error("Invalid palette name");
      await execute("theme", [action.name]);
      return;
    case "copy":
      // Only calculated numbers are accepted, never shell or clipboard input.
      if (!/^-?\d+(?:\.\d+)?(?:e[+-]?\d+)?$/.test(action.text) || !Number.isFinite(Number(action.text)))
        throw new Error("Invalid calculator result");
      await execute("wl-copy", ["--", action.text]);
      return;
    case "clipboard": {
      if (!/^[1-9]\d{0,19}$/.test(action.id)) throw new Error("Invalid clipboard entry");
      // ID on stdin works across cliphist versions. Keep decoded bytes binary
      // (images included); never put private clipboard contents into argv.
      const contents = await bytes("cliphist", ["decode"], Buffer.from(action.id + "\n"));
      await bytes("wl-copy", [], contents);
      return;
    }
    case "file":
      if (!isAbsolute(action.path) || action.path.includes("\0")) throw new Error("Invalid file path");
      await execute("gio", ["open", action.path]);
      return;
    default: throw new Error("Unknown launcher action");
  }
}
