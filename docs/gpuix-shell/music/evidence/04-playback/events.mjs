// Probe: event sequence + time-pos rate for a 2-entry mpv playlist window (gapless advance), ao=null.
import { spawn } from "node:child_process";
const child = spawn("/etc/profiles/per-user/tom/bin/mpv", ["--no-config","--no-video","--idle=yes","--ao=null","--gapless-audio=weak","--prefetch-playlist=yes","--input-ipc-client=fd://3","--msg-level=all=warn"], { stdio: ["ignore","pipe","pipe","pipe"] });
const ipc = child.stdio[3]; let buf = ""; const t0 = performance.now(); const log = []; const tp = [];
let rid = 10; const send = (...command) => ipc.write(JSON.stringify({ command, request_id: rid++ }) + "\n");
ipc.on("data", d => { buf += d; let i; while ((i = buf.indexOf("\n")) >= 0) { const l = buf.slice(0, i); buf = buf.slice(i + 1); if (!l) continue; const m = JSON.parse(l); const at = +(performance.now() - t0).toFixed(0);
  if (m.event === "property-change" && m.name === "time-pos") { tp.push(at); continue; }
  log.push([at, m.event ?? `reply#${m.request_id}`, m.name ?? m.reason ?? m.error ?? "", m.data === undefined ? "" : JSON.stringify(m.data).slice(0, 80), m.playlist_entry_id ?? "", m.file_error ?? ""].filter(x => x !== "").join(" "));
  if (m.event === "property-change" && m.name === "playlist-pos" && m.data === 1) { send("playlist-remove", 0); send("loadfile", process.cwd() + "/c.mp3", "append"); }
  if (m.event === "idle" && at > 1000) { send("quit"); }
}});
["time-pos","pause","playlist-pos","playlist-count","idle-active","duration","media-title","eof-reached","core-idle"].forEach((p, i) => send("observe_property", i + 1, p));
send("loadfile", process.cwd() + "/a.flac", "replace");
send("loadfile", process.cwd() + "/b.flac", "append");
child.on("exit", () => {
  const span = (tp.at(-1) - tp[0]) / 1000; const gaps = tp.slice(1).map((t, i) => t - tp[i]);
  console.log(log.join("\n"));
  console.log(JSON.stringify({ timePosEvents: tp.length, spanS: +span.toFixed(2), perSecond: +(tp.length / span).toFixed(1), medianGapMs: gaps.sort((a,b)=>a-b)[gaps.length>>1], maxGapMs: Math.max(...gaps) }));
});
setTimeout(() => { send("quit"); }, 15000);
