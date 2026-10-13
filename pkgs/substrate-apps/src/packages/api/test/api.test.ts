// The client's error mapping and decode guard, and the operator config loader.
import { chmodSync, mkdtempSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { describe, expect, it } from "vitest"
import { clientFromConfig, ConfigError, loadClientConfig, openApiDocument, SubstrateClient, SubstrateError } from "../src/index.ts"

const answer = (status: number, body: unknown): typeof fetch => (async () => new Response(typeof body === "string" ? body : JSON.stringify(body), { status })) as typeof fetch

describe("SubstrateClient", () => {
  it("carries the floor's own error code, in both refusal shapes", async () => {
    await expect(new SubstrateClient({ url: "http://f", token: "t", fetch: answer(404, { error: { code: "not-found", message: "no run x" } }) }).run("x"))
      .rejects.toMatchObject({ status: 404, code: "not-found" })
    await expect(new SubstrateClient({ url: "http://f", fetch: answer(401, { error: "Unauthorized" }) }).runs()).rejects.toMatchObject({ status: 401, code: "Unauthorized" })
    await expect(new SubstrateClient({ url: "http://f", fetch: answer(502, "bad gateway") }).runs()).rejects.toMatchObject({ status: 502, code: "http-502" })
  })
  it("refuses an answer that does not match the published schema", async () => {
    const e = await new SubstrateClient({ url: "http://f", fetch: answer(200, { runs: [{ id: 1 }] }) }).runs().catch((x: unknown) => x)
    expect(e).toBeInstanceOf(SubstrateError)
    expect((e as SubstrateError).code).toBe("decode")
  })
  it("sends the bearer and the Access pair", async () => {
    let seen: Headers | undefined
    const f = (async (_: unknown, init?: RequestInit) => { seen = new Headers(init?.headers); return new Response(JSON.stringify({ runs: [] })) }) as typeof fetch
    await new SubstrateClient({ url: "http://f/", token: "tok", access: { clientId: "id", clientSecret: "sec" }, fetch: f }).runs()
    expect([seen!.get("authorization"), seen!.get("cf-access-client-id"), seen!.get("cf-access-client-secret")]).toEqual(["Bearer tok", "id", "sec"])
  })
})

describe("sessions chapter client methods", () => {
  it("sessions, session, patchSession, stopSession, nudge, the trigger methods and health send their route and decode the record", async () => {
    const S = { id: "s1", project: "desk", thread: "T-9", harness: null, harness_session_id: "h", model: "m", effort: null, cwd: null, worker_status: "idle",
      post_turn_summary: null, usage: null, transcript: null, turn: 0, stopped: false, created_at: "2026-10-12T21:00:00Z", last_event_at: "2026-10-12T21:00:00Z" }
    const T = { id: "trig_0123456789abcdef", name: "n", project: "desk", kind: "routine", thread: "T-9", persistent_session_id: "s1", prompt: "p", cron_expression: "* * * * *",
      timezone: "Europe/Paris", message: null, run_at: null, enabled: true, suspension_reason: null, next_run_at: null, last_run_at: null, creator: "cli", created_at: "2026-10-12T21:00:00Z" }
    const seen: Array<string> = []
    const f = (async (input: unknown, init?: RequestInit) => {
      const u = new URL(String(input)), m = init?.method ?? "GET"
      seen.push(`${m} ${u.pathname}${u.search}${typeof init?.body === "string" ? ` ${init.body}` : ""}`)
      const body = u.pathname === "/sessions" ? { sessions: [S] } : u.pathname.startsWith("/sessions") ? S : u.pathname === "/nudge" ? { ok: true }
        : u.pathname === "/health" ? { ok: true, commit: null } : m === "DELETE" ? { deleted: true } : u.pathname === "/triggers" && m === "GET" ? { triggers: [T] } : T
      return new Response(JSON.stringify(body), { status: m === "POST" && u.pathname === "/nudge" ? 202 : m === "POST" && u.pathname === "/triggers" ? 201 : 200 })
    }) as typeof fetch
    const c = new SubstrateClient({ url: "http://f", token: "t", fetch: f })
    expect(await c.sessions({ project: "desk", thread: "T-9" })).toEqual([S])
    expect(await c.session("s1")).toEqual(S)
    await c.patchSession("s1", { model: "m2" })
    await c.stopSession("s1")
    expect(await c.nudge()).toEqual({ ok: true })
    expect(await c.triggers({ project: "desk" })).toEqual([T])
    await c.trigger(T.id)
    await c.createTrigger({ kind: "routine", project: "desk", thread: "T-9", persistent_session_id: "s1", prompt: "p", cron_expression: "* * * * *", creator: "cli", name: "n" })
    await c.updateTrigger(T.id, { enabled: false })
    expect(await c.deleteTrigger(T.id)).toEqual({ deleted: true })
    expect(await c.health()).toEqual({ ok: true, commit: null })
    expect(seen).toEqual(["GET /sessions?project=desk&thread=T-9", "GET /sessions/s1", "PATCH /sessions/s1 {\"model\":\"m2\"}", "POST /sessions/s1/stop", "POST /nudge {}",
      "GET /triggers?project=desk", `GET /triggers/${T.id}`,
      "POST /triggers {\"kind\":\"routine\",\"project\":\"desk\",\"thread\":\"T-9\",\"persistent_session_id\":\"s1\",\"prompt\":\"p\",\"cron_expression\":\"* * * * *\",\"creator\":\"cli\",\"name\":\"n\"}",
      `PATCH /triggers/${T.id} {"enabled":false}`, `DELETE /triggers/${T.id}`, "GET /health"])
  })
})

describe("config", () => {
  it("reads the file, expands ~, lets the environment override, and refuses a loose secret file", () => {
    const home = mkdtempSync(join(tmpdir(), "substrate-home-"))
    const cfg = join(home, "c.toml")
    writeFileSync(cfg, `floor_url = "https://floor.example"\ntoken_file = "~/tok"\n[puller]\nholder = "coord"\nmax_runs = 2\n`)
    const c = loadClientConfig({ SUBSTRATE_CLIENT_CONFIG: cfg }, home)
    expect(c).toMatchObject({ floor_url: "https://floor.example", token_file: join(home, "tok"), puller: { holder: "coord", max_runs: 2 }, source: cfg })
    expect(loadClientConfig({ SUBSTRATE_CLIENT_CONFIG: cfg, SUBSTRATE_URL: "http://other" }, home).floor_url).toBe("http://other")
    expect(() => clientFromConfig(c)).toThrow(/does not exist/)
    writeFileSync(join(home, "tok"), "secret-value\n")
    chmodSync(join(home, "tok"), 0o644)
    let msg = ""
    try { clientFromConfig(c) } catch (e) { expect(e).toBeInstanceOf(ConfigError); msg = (e as Error).message }
    expect(msg).toMatch(/chmod 600/)
    expect(msg).not.toContain("secret-value")
    chmodSync(join(home, "tok"), 0o600)
    expect(clientFromConfig(c).url).toBe("https://floor.example")
    expect(() => clientFromConfig(loadClientConfig({ SUBSTRATE_CLIENT_CONFIG: join(home, "none.toml") }, home))).toThrow(/no floor_url/)
  })
  it("the OpenAPI document declares both credential schemes and no 500 responses", () => {
    const d = openApiDocument() as { components: { securitySchemes: Record<string, unknown> }; paths: Record<string, unknown> }
    expect(Object.keys(d.components.securitySchemes).sort()).toEqual(["accessClientId", "accessClientSecret", "bearer"])
    expect(JSON.stringify(d.paths)).not.toContain("\"500\"")
  })
})

describe("G-BK5 underLease", () => {
  it("sends x-substrate-lease on every request of the derived client, and only there", async () => {
    const seen: Array<string | null> = []
    const fetch = (async (_u: unknown, init?: RequestInit) => { seen.push(new Headers(init?.headers).get("x-substrate-lease")); return new Response("{\"enqueued\":[]}", { status: 201 }) }) as typeof globalThis.fetch
    const { SubstrateClient } = await import("../src/client.ts")
    const c = new SubstrateClient({ url: "http://f.test", token: "t", fetch })
    await c.request("POST", "/runs/r1/jobs", { json: [] })
    await c.underLease("run-r1-a2", 2).request("POST", "/runs/r1/jobs", { json: [] })
    expect(seen).toEqual([null, "run-r1-a2:2"])
  })
})
