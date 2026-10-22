// Probe: the production argv from 04-playback-engine.md. Checks (1) no ytdl handoff, what still reaches stderr;
// (2) gapless-audio=weak vs yes across a sample-rate change (44.1k flac -> 48k mp3).
import { spawn } from "node:child_process";
import { url, redact } from "./subsonic.mjs";
const ARGV = ["--no-config","--idle=yes","--no-video","--vid=no","--no-terminal","--msg-level=all=error","--input-ipc-client=fd://3",
  "--ytdl=no","--load-scripts=no","--osc=no","--load-stats-overlay=no","--load-console=no","--load-auto-profiles=no","--load-select=no","--load-commands=no","--load-positioning=no",
  "--resume-playback=no","--save-position-on-quit=no","--audio-display=no","--cache=yes","--demuxer-max-bytes=64MiB","--demuxer-readahead-secs=600",
  "--prefetch-playlist=yes","--network-timeout=10","--audio-client-name=gpuix-shell","--volume-max=100","--replaygain=no","--ao=null"];
async function run(extra, files, label) {
  const child = spawn("/etc/profiles/per-user/tom/bin/mpv", [...ARGV, ...extra], { stdio: ["ignore","pipe","pipe","pipe"] });
  let err = ""; child.stderr.on("data", d => err += d); child.stdout.on("data", d => err += d);
  const ipc = child.stdio[3]; let buf = ""; const t0 = performance.now(); const evs = [];
  ipc.on("data", d => { buf += d; let i; while ((i = buf.indexOf("\n")) >= 0) { const l = buf.slice(0, i); buf = buf.slice(i + 1); if (!l) continue; const m = JSON.parse(l); if (m.event) evs.push([Math.round(performance.now() - t0), m.event, m.reason ?? "", m.file_error ?? ""]); if (m.event === "idle" && evs.length > 2) ipc.write('{"command":["quit"]}\n'); } });
  files.forEach((f, i) => ipc.write(JSON.stringify({ command: ["loadfile", f, i ? "append" : "replace"] }) + "\n"));
  setTimeout(() => ipc.write('{"command":["quit"]}\n'), 15000);
  await new Promise(r => child.on("exit", r));
  const starts = evs.filter(e => e[1] === "playback-restart").map(e => e[0]); const ends = evs.filter(e => e[1] === "end-file").map(e => e[0]);
  return { label, endToAudioMs: ends.length && starts.length > 1 ? starts[1] - ends[0] : null, endFiles: evs.filter(e => e[1] === "end-file").map(e => e.slice(2).filter(Boolean).join(":")), stderrLeaksToken: /[?&]t=[0-9a-f]{32}/.test(err), ytdlMentioned: /ytdl|youtube-dl/.test(err), stderr: redact(err).split("\n").filter(Boolean) };
}
const cwd = process.cwd();
console.log(JSON.stringify([
  await run([], [url("stream", { id: "knQBFakYGknBpS93V0Ceh5" }).replace(/^http:\/\/[^/]+/, "http://127.0.0.1:9")], "unreachable host, production argv"),
  await run(["--gapless-audio=weak"], [`${cwd}/b.flac`, `${cwd}/c.mp3`], "44.1k flac -> 48k mp3, gapless weak"),
  await run(["--gapless-audio=yes"], [`${cwd}/b.flac`, `${cwd}/c.mp3`], "44.1k flac -> 48k mp3, gapless yes"),
  await run(["--gapless-audio=weak"], [`${cwd}/a.flac`, `${cwd}/b.flac`], "44.1k flac -> 44.1k flac, gapless weak"),
], null, 1));
