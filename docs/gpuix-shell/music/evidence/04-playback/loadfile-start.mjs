// Probe: named-argument loadfile with a per-file start option (used for restore/crash-resume), and
// that per-file options do not leak to the appended successor.
import { spawn } from "node:child_process";
const child = spawn("/etc/profiles/per-user/tom/bin/mpv", ["--no-config","--idle=yes","--no-video","--no-terminal","--ytdl=no","--ao=null","--pause=yes","--input-ipc-client=fd://3"], { stdio: ["ignore","ignore","ignore","pipe"] });
const ipc = child.stdio[3]; let buf = ""; const out = {}; let restarts = 0; let rid = 1; const pend = new Map();
const req = (command) => new Promise(r => { const id = rid++; pend.set(id, r); ipc.write(JSON.stringify({ command, request_id: id }) + "\n"); });
ipc.on("data", async d => { buf += d; let i; while ((i = buf.indexOf("\n")) >= 0) { const l = buf.slice(0, i); buf = buf.slice(i + 1); if (!l) continue; const m = JSON.parse(l);
  if (m.request_id && pend.has(m.request_id)) { pend.get(m.request_id)(m); pend.delete(m.request_id); continue; }
  if (m.event === "playback-restart") { restarts++;
    if (restarts === 1) { out.firstTimePos = (await req(["get_property", "time-pos"])).data; out.pausedAtLoad = (await req(["get_property", "pause"])).data; await req(["set_property", "pause", false]); }
    if (restarts === 2) { out.successorTimePos = (await req(["get_property", "time-pos"])).data; await req(["quit"]); } } } });
out.loadReply = (await req({ name: "loadfile", url: "av://lavfi:sine=frequency=440:duration=6", flags: "replace", options: { start: "4.5" } })).error;
out.appendReply = (await req({ name: "loadfile", url: "av://lavfi:sine=frequency=660:duration=3", flags: "append" })).error;
setTimeout(() => req(["quit"]), 9000);
child.on("exit", () => console.log(JSON.stringify(out)));
