import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { createServer, type Server } from "node:net";
import { spawn } from "node:child_process";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { parse } from "smol-toml";
import { herdrRunner, pluginManifest, ENTRY, DEFAULT_PLUGIN } from "../src/herdr.ts";
import { isRefusal, type RunOutcome } from "../src/job.ts";
import { tmp } from "./helpers.ts";

/**
 * A fake herdr: the NDJSON socket protocol, the plugin registry, plugin actions
 * that really run their manifest command with HERDR_PLUGIN_CONTEXT_JSON, and
 * panes that run sent text in sh. Enough to drive both modes end to end.
 */
const evict = { on: false };
function fakeHerdr(socket: string) {
  const plugins = new Map<string, { actions: { id: string; command: string[] }[] }>();
  const logs: Record<string, unknown>[] = [];
  const panes = new Map<string, { cwd: string; out: string }>();
  const created: string[] = [];
  const closed: string[] = [];
  let n = 0;
  const handle = async (method: string, p: Record<string, any>): Promise<unknown> => {
    switch (method) {
      case "plugin.action.list": {
        const pl = plugins.get(p.plugin_id);
        if (!pl) throw { code: "plugin_not_found", message: "plugin not found" };
        return { type: "plugin_action_list", actions: pl.actions.map((a) => ({ action_id: a.id, plugin_id: p.plugin_id })) };
      }
      case "plugin.link": {
        const m = parse(readFileSync(join(p.path, "herdr-plugin.toml"), "utf8")) as any;
        plugins.set(m.id, { actions: m.actions });
        return { type: "plugin_linked" };
      }
      case "plugin.action.invoke": {
        const pl = plugins.get(p.plugin_id);
        const a = pl?.actions.find((x) => x.id === p.action_id);
        if (!a) throw { code: "plugin_not_found", message: "plugin not found" };
        const log: Record<string, any> = { log_id: `plugin-log-${++n}`, plugin_id: p.plugin_id, action_id: a.id, status: "running" };
        logs.push(log);
        const c = spawn(a.command[0]!, a.command.slice(1), { env: { ...process.env, HERDR_PLUGIN_CONTEXT_JSON: JSON.stringify(p.context ?? {}) } });
        let so = "", se = "";
        c.stdout.on("data", (b) => (so += b));
        c.stderr.on("data", (b) => (se += b));
        c.on("close", (code) => Object.assign(log, { status: code === 0 ? "succeeded" : "failed", exit_code: code, stdout: so, stderr: se }));
        return { type: "plugin_action_invoked", log: { ...log } };
      }
      case "plugin.log.list":
        if (evict.on) return { type: "plugin_log_list", logs: [] };
        return { type: "plugin_log_list", logs: logs.filter((l) => !p.plugin_id || l.plugin_id === p.plugin_id) };
      case "workspace.create": {
        const ws = `w${++n}`;
        created.push(ws);
        panes.set(`${ws}:p1`, { cwd: p.cwd, out: "" });
        return { workspace: { workspace_id: ws }, root_pane: { pane_id: `${ws}:p1` } };
      }
      case "pane.send_input": {
        const pane = panes.get(p.pane_id)!;
        pane.out += `$ ${p.text}\n`;
        const c = spawn("sh", ["-c", p.text], { cwd: pane.cwd });
        c.stdout.on("data", (b) => (pane.out += b));
        c.stderr.on("data", (b) => (pane.out += b));
        return { type: "ok" };
      }
      case "pane.wait_for_output": {
        const pane = panes.get(p.pane_id)!;
        const re = new RegExp(p.match.value);
        const end = Date.now() + (p.timeout_ms ?? 5000);
        while (Date.now() < end) {
          if (re.test(pane.out)) return { type: "output_matched" };
          await new Promise((r) => setTimeout(r, 20));
        }
        throw { code: "timeout", message: "no match" };
      }
      case "workspace.close":
        closed.push(p.workspace_id);
        return { type: "ok" };
      default:
        throw { code: "unknown_method", message: method };
    }
  };
  const server: Server = createServer((s) => {
    let buf = "";
    s.on("data", async (d) => {
      buf += d;
      const i = buf.indexOf("\n");
      if (i < 0) return;
      const req = JSON.parse(buf.slice(0, i));
      try {
        s.end(JSON.stringify({ id: req.id, result: await handle(req.method, req.params ?? {}) }) + "\n");
      } catch (e: any) {
        s.end(JSON.stringify({ id: req.id, error: { code: e.code ?? "x", message: e.message ?? String(e) } }) + "\n");
      }
    });
  });
  return { server, plugins, created, closed, listen: () => new Promise<void>((r) => server.listen(socket, r)) };
}

const d = tmp();
const socket = join(d, "herdr.sock");
const fake = fakeHerdr(socket);
beforeAll(() => fake.listen());
afterAll(() => fake.server.close());

const job = (id: string, argv: string[], stdin = "") => ({ kind: "process" as const, id, argv, stdin, jobDir: join(d, "jobs", id) });

describe("herdr plugin manifest", () => {
  it("one action, one fixed command: node plus the entry script; the job never rides in argv", () => {
    const m = parse(pluginManifest(DEFAULT_PLUGIN, "/nix/store/n/bin/node", ENTRY)) as any;
    expect(m.id).toBe("substrate-runner");
    expect(m.name).toBe("substrate-runner");
    expect(m.actions).toEqual([{ id: "job", title: "substrate job", command: ["/nix/store/n/bin/node", ENTRY], contexts: ["global", "selection"] }]);
  });
});

describe("herdr runner, action mode", () => {
  it("refuses when the plugin is not linked and autoLink is off, and links nothing", async () => {
    const r = await herdrRunner("herdr", { socket }).run(job("a0", ["true"]));
    expect(isRefusal(r) && r.refused).toMatch(/not linked.*herdr-link/);
    expect(fake.plugins.size).toBe(0);
  });

  it("with autoLink, reports herdr's native exit_code, stdout and stderr", async () => {
    const r = herdrRunner("herdr", { socket, autoLink: true, pluginDir: join(d, "plugin"), pollMs: 20 });
    const res = (await r.run(job("a1", ["sh", "-c", "cat; echo e >&2; exit 3"], "from-stdin"))) as RunOutcome;
    expect(res).toMatchObject({ exitCode: 3, stdout: "from-stdin", stderr: "e\n" });
    expect(res.detail).toMatchObject({ mode: "action", status: "failed" });
    expect(fake.created).toEqual([]); // no pane, no workspace
  });

  it("enforces the job timeout inside the plugin command (124)", async () => {
    const r = herdrRunner("herdr", { socket, pollMs: 20 });
    const res = (await r.run({ ...job("a2", ["sleep", "5"]), timeoutMs: 300 })) as RunOutcome;
    expect(res.exitCode).toBe(124);
    expect(res.timedOut).toBe(true);
  });
});

describe("herdr runner, evicted log entry", () => {
  it("falls back to the entry script's rc and output files when herdr's bounded log drops the entry", async () => {
    evict.on = true;
    try {
      const res = (await herdrRunner("herdr", { socket, pollMs: 20 }).run(job("a3", ["sh", "-c", "echo kept; exit 6"]))) as RunOutcome;
      expect(res).toMatchObject({ exitCode: 6, stdout: "kept\n" });
      expect(res.detail).toMatchObject({ status: "evicted" });
    } finally {
      evict.on = false;
    }
  });
});

describe("herdr runner, pane mode", () => {
  it("creates its own unfocused workspace, reads the sentinel, and closes only that workspace", async () => {
    const r = herdrRunner("herdr", { socket, mode: "pane" });
    const res = (await r.run(job("p1", ["sh", "-c", "echo out; echo err >&2; exit 7"]))) as RunOutcome;
    expect(res).toMatchObject({ exitCode: 7, stdout: "out\n", stderr: "err\n" });
    expect(fake.closed).toEqual([res.detail!.workspace]);
    expect(fake.created).toContain(res.detail!.workspace);
  });

  it("refuses without a socket and refuses non-identity mounts", () => {
    expect(herdrRunner("h", { socket: join(d, "none.sock") }).refuses(job("x", ["true"]))).toMatch(/no herdr socket/);
    expect(
      herdrRunner("h", { socket }).refuses({ ...job("y", ["true"]), mounts: [{ source: "/a", target: "/b", mode: "rw" }] }),
    ).toMatch(/cannot mount/);
  });
});
