// Probe: what mpv reports for a bogus song id, a bad token, and an unreachable server; does stderr leak auth?
import { spawn } from "node:child_process";
import { url, BASE, redact } from "./subsonic.mjs";
import { createHash, randomBytes } from "node:crypto";
const child = spawn("/etc/profiles/per-user/tom/bin/mpv", ["--no-config","--no-video","--idle=yes","--ao=null","--input-ipc-client=fd://3","--msg-level=all=warn","--network-timeout=3"], { stdio: ["ignore","pipe","pipe","pipe"] });
let stderr = ""; child.stderr.on("data", d => stderr += d); child.stdout.on("data", d => stderr += d);
const ipc = child.stdio[3]; let buf = ""; const listeners = new Set(); const t0 = performance.now(); const now = () => performance.now() - t0;
ipc.on("data", d => { buf += d; let i; while ((i = buf.indexOf("\n")) >= 0) { const l = buf.slice(0, i); buf = buf.slice(i + 1); if (l) { const m = JSON.parse(l); for (const h of [...listeners]) h(m); } } });
const send = (...command) => ipc.write(JSON.stringify({ command }) + "\n");
const until = (pred, ms) => new Promise((res) => { const h = m => { if (pred(m)) { listeners.delete(h); res(m); } }; listeners.add(h); setTimeout(() => { listeners.delete(h); res({ timeout: true }); }, ms); });
async function attempt(label, u) { const a = now(); send("loadfile", u, "replace"); const m = await until(m => m.event === "end-file" || m.event === "playback-restart", 12000); return { label, ms: Math.round(now() - a), event: m.event ?? "timeout", reason: m.reason, file_error: m.file_error }; }
const out = [];
out.push(await attempt("bogus song id", url("stream", { id: "doesNotExist00000000000" })));
const s = randomBytes(8).toString("hex"); const bad = new URLSearchParams({ u: "gpuix-probe-nouser", t: createHash("md5").update("wrong" + s).digest("hex"), s, v: "1.16.1", c: "gpuix-shell", f: "json", id: "knQBFakYGknBpS93V0Ceh5" });
out.push(await attempt("wrong credentials", `${BASE}/rest/stream?${bad}`));
out.push(await attempt("unreachable host", url("stream", { id: "knQBFakYGknBpS93V0Ceh5" }).replace(BASE, "http://127.0.0.1:9")));
send("quit"); await new Promise(r => child.on("exit", r));
console.log(JSON.stringify({ out, stderrLeaksAuthToken: /[?&]t=[0-9a-f]{32}/.test(stderr), stderrRedacted: redact(stderr).split("\n").filter(Boolean) }, null, 1));
