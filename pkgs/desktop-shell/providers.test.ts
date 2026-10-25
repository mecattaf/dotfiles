import { test, expect } from "bun:test";
import { mkdtemp, mkdir, writeFile, symlink, rm, utimes } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { EventEmitter } from "node:events";
import { activateProvider, calculate, clipboardItems, fileItems, launchProviderCommand, listThemes, parseClipboard, providerItems, type ProviderAction, type RunBytes } from "./providers";
import type { Run } from "./controller";

test("calculator precedence, unary operators, powers, scientific notation and decimals", () => {
  for (const [expression, answer] of [
    ["2+3*4", "14"], ["(2+3)*4", "20"], ["-2^2", "-4"], ["2^-2", "0.25"],
    ["2^3^2", "512"], ["= .5 + 1e-2", "0.51"], ["7%4", "3"], ["3 × 4 − 2", "10"],
    ["0.1+0.2", "0.3"], ["---2", "-2"],
  ]) expect(calculate(expression!)).toBe(answer);
});
test("calculator never evaluates code, partial expressions, nonfinite values or excessive input", () => {
  for (const expression of ["globalThis.process.exit()", "1;echo bad", "$(bad)", "1e", "1/0", "0/0", "2 3", "(2+1", "1+", "2**3", "1e999", "-".repeat(300)])
    expect(calculate(expression)).toBeNull();
});
test("ordinary command search is pure and arithmetic result copies exact number", async () => {
  const items = providerItems("2+2");
  expect(items[0]!.title).toBe("4");
  const calls: unknown[] = [];
  await activateProvider(items[0]!.action, async (...args) => { calls.push(args); return ""; });
  expect(calls).toEqual([["wl-copy", ["--", "4"]]]);
  expect(providerItems("ocr").map(item => item.id)).toContain("command:ocr");
  expect(providerItems("no matching result")).toEqual([]);
});
test("only rendered valid palette names enter selection; helper verbs and injection rejected", async () => {
  const names = await listThemes(async (command, args) => {
    expect([command, ...args]).toEqual(["theme", "list"]);
    return "claude-dark\nnoir\nclaude-dark\n../../bad\napply\nnoir;exec bad\n";
  });
  expect(names).toEqual(["claude-dark", "noir"]);
  const items = providerItems("palette", { themeNames: names });
  expect(items.filter(item => item.action.kind === "theme")).toHaveLength(2);
  const calls: unknown[] = [];
  await activateProvider({ kind: "theme", name: "claude-dark" }, async (...args) => { calls.push(args); return ""; });
  expect(calls).toEqual([["theme", ["claude-dark"]]]);
  for (const name of ["apply", "toggle", "../noir", "--help", "a;bad"])
    await expect(activateProvider({ kind: "theme", name }, async () => { throw Error("must not execute"); })).rejects.toThrow("Invalid palette");
});
test("fixed helper actions cannot select arbitrary commands or swallow failures", async () => {
  const calls: unknown[] = [];
  const execute: Run = async (...args) => { calls.push(args); return ""; };
  await activateProvider({ kind: "command", name: "screenshotArea" }, execute);
  expect(calls).toEqual([["screenshot", ["area"]]]);
  await expect(activateProvider({ kind: "command", name: "__proto__" } as unknown as ProviderAction, execute)).rejects.toThrow("Unknown launcher");
  await expect(activateProvider({ kind: "command", name: "monitors" }, async () => { throw Error("no compositor"); })).rejects.toThrow("no compositor");
});
test("interactive helper launch keeps exact argv, survives launcher and reports exec failure", async () => {
  const events = new EventEmitter();
  let unreferenced = false;
  Object.assign(events, { unref: () => { unreferenced = true; } });
  const launch = launchProviderCommand("kitty", ["--class", "literal ; $(text)"], ((command: string, args: string[], options: unknown) => {
    expect(command).toBe("kitty");
    expect(args).toEqual(["--class", "literal ; $(text)"]);
    expect(options).toEqual({ detached: true, stdio: ["ignore", "inherit", "inherit"] });
    queueMicrotask(() => events.emit("spawn"));
    return events;
  }) as never);
  await launch;
  expect(unreferenced).toBe(true);
  await expect(launchProviderCommand("missing", [], (() => {
    const child = new EventEmitter();
    queueMicrotask(() => child.emit("error", new Error("ENOENT")));
    return child;
  }) as never)).rejects.toThrow("ENOENT");
});
test("clipboard parser filters previews, preserves IDs as strings and rejects malformed entries", () => {
  const rows = "5\tfirst item\n4\t[[ binary data 2 KiB png 1x1 ]]\n3\t$(touch bad)\n5\tduplicate\n-2\tbad\nno id\n2\ttext\u001b[0m\n";
  expect(parseClipboard(rows).map(row => row.id)).toEqual(["clipboard:5", "clipboard:4", "clipboard:3", "clipboard:2"]);
  expect(parseClipboard(rows, "binary")[0]!.action).toEqual({ kind: "clipboard", id: "4" });
  expect(parseClipboard(rows, "", 2)).toHaveLength(2);
  expect(parseClipboard(rows, "not present")).toEqual([]);
});
test("clipboard listing is explicit, handles empty initial history and surfaces actual failures", async () => {
  const execute: Run = async (command, args) => {
    expect([command, ...args]).toEqual(["cliphist", "list"]);
    return "1\tfixture only";
  };
  expect(await clipboardItems("fixture", execute)).toHaveLength(1);
  expect(await clipboardItems("", async () => { throw Error("please store something first"); })).toEqual([]);
  await expect(clipboardItems("", async () => { throw Error("database locked"); })).rejects.toThrow("database locked");
});
test("clipboard activation transfers bytes through stdin and never evaluates or places content in argv", async () => {
  const contents = Buffer.from([0x89, 0x50, 0, 0xff, 0x24, 0x28]);
  const calls: [string, string[], Buffer | undefined][] = [];
  const bytes: RunBytes = async (command, args, input) => {
    calls.push([command, args, input]);
    return command === "cliphist" ? contents : Buffer.alloc(0);
  };
  await activateProvider({ kind: "clipboard", id: "42" }, async () => { throw Error("text executor forbidden"); }, bytes);
  expect(calls).toEqual([["cliphist", ["decode"], Buffer.from("42\n")], ["wl-copy", [], contents]]);
  await expect(activateProvider({ kind: "clipboard", id: "42;exec bad" }, undefined, bytes)).rejects.toThrow("Invalid clipboard");
  expect(calls).toHaveLength(2);
});
test("failed clipboard decode never writes a replacement clipboard", async () => {
  const calls: string[] = [];
  await expect(activateProvider({ kind: "clipboard", id: "42" }, undefined, async command => {
    calls.push(command); throw Error("entry disappeared");
  })).rejects.toThrow("entry disappeared");
  expect(calls).toEqual(["cliphist"]);
});
test("bounded file provider searches names only and skips hidden files and symlinks", async () => {
  const home = await mkdtemp(join(tmpdir(), "shell-provider-"));
  try {
    await mkdir(join(home, "Downloads"));
    await mkdir(join(home, "Documents"));
    await mkdir(join(home, "Documents", "nested"));
    await writeFile(join(home, "Downloads", "old.txt"), "fixture");
    await utimes(join(home, "Downloads", "old.txt"), 1, 1);
    await writeFile(join(home, "Documents", "nested", "draft ; $(literal).txt"), "fixture");
    await writeFile(join(home, "Downloads", ".hidden"), "fixture");
    await symlink(join(home, "Documents"), join(home, "Downloads", "link"));
    const rows = await fileItems("", { home });
    expect(rows.map(row => row.title)).toEqual(["draft ; $(literal).txt", "old.txt"]);
    expect(await fileItems("not found", { home })).toEqual([]);
    expect(await fileItems("draft", { home })).toHaveLength(1);
    expect(await fileItems("", { home, limit: 1 })).toHaveLength(1);
    expect((await fileItems("", { home, maxEntries: 1 })).length).toBeLessThanOrEqual(1);
    const calls: unknown[] = [];
    await activateProvider(rows[0]!.action, async (...args) => { calls.push(args); return ""; });
    expect(calls).toEqual([["gio", ["open", join(home, "Documents", "nested", "draft ; $(literal).txt")]]]);
  } finally { await rm(home, { recursive: true, force: true }); }
});
test("file provider refuses relative homes, missing roots are empty and file actions validate paths", async () => {
  await expect(fileItems("", { home: "relative" })).rejects.toThrow("absolute home");
  expect(await fileItems("", { home: "/nonexistent-desktop-shell-test-home" })).toEqual([]);
  await expect(activateProvider({ kind: "file", path: "https://example.com" })).rejects.toThrow("Invalid file");
});
