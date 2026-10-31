// Probe: gapless-audio=yes + audio-samplerate=48000 across 22.05k -> 44.1k -> 48k sources; report out params + transitions.
import { spawn } from "node:child_process";
const child = spawn("/etc/profiles/per-user/tom/bin/mpv", ["--no-config","--idle=yes","--no-video","--no-terminal","--ytdl=no","--ao=null","--gapless-audio=yes","--audio-samplerate=48000","--prefetch-playlist=yes","--input-ipc-client=fd://3"], { stdio: ["ignore","ignore","ignore","pipe"] });
const ipc = child.stdio[3]; let buf = ""; const t0 = performance.now(); const ev = []; let rid = 100; const outs = [];
const send = (...c) => ipc.write(JSON.stringify({ command: c, request_id: rid++ }) + "\n");
ipc.on("data", d => { buf += d; let i; while ((i = buf.indexOf("\n")) >= 0) { const l = buf.slice(0, i); buf = buf.slice(i + 1); if (!l) continue; const m = JSON.parse(l);
  if (m.event === "end-file" || m.event === "playback-restart") ev.push([Math.round(performance.now() - t0), m.event]);
  if (m.event === "playback-restart") { send("get_property", "audio-out-params"); send("get_property", "audio-params"); }
  if (m.request_id >= 100 && m.data?.samplerate) outs.push(m.data.samplerate);
  if (m.event === "idle" && ev.length > 3) send("quit"); } });
for (const [i, sr] of [22050, 44100, 48000].entries()) send("loadfile", `av://lavfi:sine=frequency=${440 + i * 220}:duration=1.2:sample_rate=${sr}`, i ? "append" : "replace");
setTimeout(() => send("quit"), 9000);
child.on("exit", () => { const gaps = []; for (let k = 0; k + 1 < ev.length; k++) if (ev[k][1] === "end-file" && ev[k + 1][1] === "playback-restart") gaps.push(ev[k + 1][0] - ev[k][0]);
  console.log(JSON.stringify({ transitionsMs: gaps, samplerates_out_in_pairs: outs })); });
