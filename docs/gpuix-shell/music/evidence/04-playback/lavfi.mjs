// Probe: fixture-free test audio via mpv's av://lavfi: sources (for bun tests in the Nix sandbox).
import { spawn } from "node:child_process";
const child = spawn("/etc/profiles/per-user/tom/bin/mpv", ["--no-config","--idle=yes","--no-video","--no-terminal","--ytdl=no","--ao=null","--gapless-audio=yes","--prefetch-playlist=yes","--input-ipc-client=fd://3"], { stdio: ["ignore","ignore","ignore","pipe"] });
const ipc = child.stdio[3]; let buf = ""; const t0 = performance.now(); const ev = [];
const send = (...c) => ipc.write(JSON.stringify({ command: c }) + "\n");
ipc.on("data", d => { buf += d; let i; while ((i = buf.indexOf("\n")) >= 0) { const l = buf.slice(0, i); buf = buf.slice(i + 1); if (!l) continue; const m = JSON.parse(l);
  if (m.event && m.event !== "audio-reconfig") ev.push(`${Math.round(performance.now() - t0)} ${m.event}${m.reason ? " " + m.reason : ""}${m.name ? " " + m.name + "=" + JSON.stringify(m.data) : ""}`);
  if (m.event === "idle" && ev.length > 3) send("quit"); } });
send("observe_property", 1, "duration");
send("loadfile", "av://lavfi:sine=frequency=440:duration=1.5:sample_rate=44100", "replace");
send("loadfile", "av://lavfi:sine=frequency=660:duration=1:sample_rate=48000", "append");
setTimeout(() => send("quit"), 8000);
child.on("exit", () => console.log(ev.join("\n")));
