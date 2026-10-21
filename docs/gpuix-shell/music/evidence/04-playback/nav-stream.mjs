// Probe: play real Navidrome streams in mpv (ao=null) over fd IPC; measure open latency, seek, metadata,
// prefetch-assisted transition, error shape, and whether mpv's stderr leaks auth query params.
import { spawn } from "node:child_process";
import { call, url, redact } from "./subsonic.mjs";
const prefetch = process.argv[2] ?? "yes";
const album = await call("getAlbum", { id: "27IOgjzYxZjO5ZuTJaNv8a" });
const songs = album.album.song; const [s1, s2] = [songs[1], songs[2]];
const child = spawn("/etc/profiles/per-user/tom/bin/mpv", ["--no-config","--no-video","--idle=yes","--ao=null","--cache=yes","--demuxer-max-bytes=64MiB","--gapless-audio=weak",`--prefetch-playlist=${prefetch}`,"--input-ipc-client=fd://3","--audio-client-name=gpuix-shell"], { stdio: ["ignore","pipe","pipe","pipe"] });
let stderr = ""; child.stderr.on("data", d => stderr += d); child.stdout.on("data", d => stderr += d);
const ipc = child.stdio[3]; let buf = ""; const t0 = performance.now(); const now = () => +(performance.now() - t0).toFixed(0);
const pending = new Map(); let rid = 1; const ev = [];
const cmd = (...command) => new Promise(res => { const id = rid++; pending.set(id, res); ipc.write(JSON.stringify({ command, request_id: id }) + "\n"); });
const waitEv = (pred, ms = 15000) => new Promise((res, rej) => { const h = (m) => { if (pred(m)) { listeners.delete(h); res({ at: now(), m }); } }; listeners.add(h); setTimeout(() => { listeners.delete(h); rej(new Error("timeout")); }, ms); });
const listeners = new Set();
ipc.on("data", d => { buf += d; let i; while ((i = buf.indexOf("\n")) >= 0) { const l = buf.slice(0, i); buf = buf.slice(i + 1); if (!l) continue; const m = JSON.parse(l);
  if (m.request_id && pending.has(m.request_id)) { pending.get(m.request_id)(m); pending.delete(m.request_id); }
  if (m.event) { ev.push([now(), m.event, m.reason ?? "", m.file_error ?? "", m.playlist_entry_id ?? ""].filter(Boolean).join(" ")); for (const h of [...listeners]) h(m); } } });
const out = { prefetch, song1: `${s1.artist} — ${s1.title} (${s1.suffix} ${s1.bitRate}k ${s1.duration}s)`, song2: `${s2.title} (${s2.suffix})` };
// 1. open latency
let a = now(); cmd("loadfile", url("stream", { id: s1.id }), "replace");
let r = await waitEv(m => m.event === "playback-restart"); out.openToFirstAudioMs = r.at - a;
out.duration = (await cmd("get_property", "duration")).data;
out.seekable = (await cmd("get_property", "seekable")).data;
out.metadataKeys = Object.keys((await cmd("get_property", "metadata")).data ?? {});
out.mediaTitle = (await cmd("get_property", "media-title")).data;
out.pathLeaksAuth = /[?&]t=/.test((await cmd("get_property", "path")).data ?? "");
out.audioParams = (await cmd("get_property", "audio-params")).data;
out.audioCodec = (await cmd("get_property", "audio-codec-name")).data;
// 2. seek far ahead (HTTP Range)
a = now(); await cmd("seek", 150, "absolute");
r = await waitEv(m => m.event === "playback-restart"); out.seekTo150Ms = r.at - a;
await new Promise(res => setTimeout(res, 1500));
const cache = (await cmd("get_property", "demuxer-cache-state")).data;
out.cacheAfterSeek = { cacheEnd: cache?.["cache-end"], fwBytes: cache?.["fw-bytes"], eofCached: cache?.eof, bofCached: cache?.bof, seekableRanges: cache?.["seekable-ranges"] };
out.timePos = (await cmd("get_property", "time-pos")).data;
// 3. prefetch-assisted transition: append s2, seek near end of s1
await cmd("loadfile", url("stream", { id: s2.id }), "append");
await cmd("seek", out.duration - 4, "absolute");
await waitEv(m => m.event === "playback-restart");
const endAt = (await waitEv(m => m.event === "end-file", 20000)).at;
r = await waitEv(m => m.event === "playback-restart", 20000); out.transitionEndFileToAudioMs = r.at - endAt;
// 4. error shape: bogus id
await cmd("playlist-clear"); a = now();
cmd("loadfile", url("stream", { id: "doesNotExist00000000000" }), "replace");
r = await waitEv(m => m.event === "end-file", 15000); out.bogusId = { endFileMs: r.at - a, reason: r.m.reason, file_error: r.m.file_error };
await cmd("quit");
await new Promise(res => child.on("exit", res));
out.stderrLeaksAuthToken = /[?&]t=[0-9a-f]{32}/.test(stderr); out.stderrMentionsUrl = /\/rest\/stream/.test(stderr);
out.stderrRedactedTail = redact(stderr).split("\n").filter(Boolean).slice(-6);
out.events = ev;
console.log(JSON.stringify(out, null, 1));
