// G-BK7: the puller's loopback health endpoint. GET /status.json is Puller.status(); GET /metrics is the same in
// Prometheus text. Loopback only: a non-loopback address is refused, and nothing here carries a secret.
import { createServer } from "node:http"
import type { Puller, PullerStatus } from "./puller.ts"

export const prometheusOf = (s: PullerStatus): string => {
  const h = JSON.stringify(s.holder)
  const lines = [
    "# TYPE substrate_puller_held gauge", `substrate_puller_held{holder=${h}} ${s.held}`,
    "# TYPE substrate_puller_active gauge", `substrate_puller_active{holder=${h}} ${s.active.length}`,
    "# TYPE substrate_puller_outbox gauge", `substrate_puller_outbox{holder=${h}} ${s.outbox}`,
    "# TYPE substrate_puller_draining gauge", `substrate_puller_draining{holder=${h}} ${s.state === "draining" ? 1 : 0}`,
    "# TYPE substrate_puller_heartbeat_failures_consecutive gauge", `substrate_puller_heartbeat_failures_consecutive{holder=${h}} ${s.heartbeatFailures}`,
    "# TYPE substrate_puller_events_total counter",
    ...Object.entries(s.counters).sort().map(([k, v]) => `substrate_puller_events_total{holder=${h},event=${JSON.stringify(k)}} ${v}`)
  ]
  return lines.join("\n") + "\n"
}

export const serveHealth = (addr: string, puller: Pick<Puller, "status">): Promise<{ addr: string; close: () => void }> => {
  const m = /^(127\.0\.0\.1|localhost|\[::1\]):(\d+)$/.exec(addr)
  if (!m) return Promise.reject(new Error(`health_addr ${addr} must be a loopback host:port`))
  const host = m[1] === "[::1]" ? "::1" : m[1]!
  const srv = createServer((req, res) => {
    const path = (req.url ?? "/").split("?")[0]
    if (req.method === "GET" && path === "/status.json") { res.writeHead(200, { "content-type": "application/json" }); res.end(JSON.stringify(puller.status())); return }
    if (req.method === "GET" && path === "/metrics") { res.writeHead(200, { "content-type": "text/plain; version=0.0.4" }); res.end(prometheusOf(puller.status())); return }
    res.writeHead(404).end()
  })
  return new Promise((ok, no) => {
    srv.once("error", no)
    srv.listen(Number(m[2]), host, () => {
      const a = srv.address()
      ok({ addr: typeof a === "object" && a ? `${host}:${a.port}` : addr, close: () => srv.close() })
    })
  })
}
