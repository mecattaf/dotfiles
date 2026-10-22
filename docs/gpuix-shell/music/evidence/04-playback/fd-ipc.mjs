// Probe: mpv JSON IPC over an inherited socketpair (--input-ipc-client=fd://3), no filesystem socket.
import { spawn } from "node:child_process";
const MPV = process.env.MPV ?? "/etc/profiles/per-user/tom/bin/mpv";
const rt = typeof Bun !== "undefined" ? `bun ${Bun.version}` : `node ${process.version}`;
const child = spawn(MPV, ["--no-config", "--no-video", "--idle=yes", "--ao=null", "--input-ipc-client=fd://3", "--msg-level=all=warn"],
  { stdio: ["ignore", "pipe", "pipe", "pipe"] });
const ipc = child.stdio[3];
if (!ipc) { console.log(JSON.stringify({ rt, ok: false, why: "no stdio[3]" })); process.exit(1); }
let buf = ""; const replies = [];
const t0 = performance.now();
ipc.on("data", (d) => { buf += d.toString(); let i; while ((i = buf.indexOf("\n")) >= 0) { const line = buf.slice(0, i); buf = buf.slice(i + 1); if (line) replies.push({ at: +(performance.now() - t0).toFixed(1), msg: JSON.parse(line) }); } });
ipc.write(JSON.stringify({ command: ["get_property", "mpv-version"], request_id: 1 }) + "\n");
ipc.write(JSON.stringify({ command: ["get_property", "pid"], request_id: 2 }) + "\n");
ipc.write(JSON.stringify({ command: ["observe_property", 1, "idle-active"] }) + "\n");
setTimeout(() => { ipc.write(JSON.stringify({ command: ["quit"], request_id: 3 }) + "\n"); }, 400);
child.on("exit", (code, sig) => { console.log(JSON.stringify({ rt, ok: replies.some(r => r.msg.request_id === 1 && r.msg.error === "success"), exit: code, sig, replies })); });
