// Probe: an MPRIS2 server (org.mpris.MediaPlayer2.gpuixshell) via dbus-next under bun, on a PRIVATE bus.
import dbus from "dbus-next";
const { Interface, ACCESS_READ, ACCESS_READWRITE } = dbus.interface;
const { Variant } = dbus;
const calls = [];
const state = { status: "Paused", volume: 0.8, position: 12_000_000n, loop: "None", shuffle: false };
const meta = () => ({
  "mpris:trackid": new Variant("o", "/run/gpuix/shell/music/track/knQBFakYGknBpS93V0Ceh5"),
  "mpris:length": new Variant("x", 218_000_000n),
  "mpris:artUrl": new Variant("s", "file:///home/tom/.cache/gpuix-shell/music/covers/mf-knQBFakYGknBpS93V0Ceh5_663d9232-600.jpg"),
  "xesam:title": new Variant("s", "Civilization"), "xesam:album": new Variant("s", "Audio, Video, Disco"),
  "xesam:artist": new Variant("as", ["Justice"]), "xesam:albumArtist": new Variant("as", ["Justice"]),
  "xesam:trackNumber": new Variant("i", 2), "xesam:url": new Variant("s", "http://music.internal/app/#/album/27IOgjzYxZjO5ZuTJaNv8a/show"),
});
class Root extends Interface {}
Root.configureMembers({
  properties: { Identity: { signature: "s", access: ACCESS_READ }, DesktopEntry: { signature: "s", access: ACCESS_READ }, CanQuit: { signature: "b", access: ACCESS_READ }, CanRaise: { signature: "b", access: ACCESS_READ }, HasTrackList: { signature: "b", access: ACCESS_READ }, SupportedUriSchemes: { signature: "as", access: ACCESS_READ }, SupportedMimeTypes: { signature: "as", access: ACCESS_READ } },
  methods: { Raise: { inSignature: "", outSignature: "" }, Quit: { inSignature: "", outSignature: "" } },
});
const root = new Root("org.mpris.MediaPlayer2");
Object.assign(root, { Identity: "GPUIX Shell Music", DesktopEntry: "gpuix-shell-music", CanQuit: false, CanRaise: true, HasTrackList: false, SupportedUriSchemes: [], SupportedMimeTypes: [], Raise() { calls.push("Raise"); }, Quit() {} });
class Player extends Interface {
  get PlaybackStatus() { return state.status; } get LoopStatus() { return state.loop; } set LoopStatus(v) { calls.push(`LoopStatus=${v}`); state.loop = v; }
  get Rate() { return 1.0; } set Rate(_) {} get Shuffle() { return state.shuffle; } set Shuffle(v) { calls.push(`Shuffle=${v}`); state.shuffle = v; }
  get Metadata() { return meta(); } get Volume() { return state.volume; } set Volume(v) { calls.push(`Volume=${v}`); state.volume = v; }
  get Position() { return state.position; } get MinimumRate() { return 1.0; } get MaximumRate() { return 1.0; }
  get CanGoNext() { return true; } get CanGoPrevious() { return true; } get CanPlay() { return true; } get CanPause() { return true; } get CanSeek() { return true; } get CanControl() { return true; }
  PlayPause() { calls.push("PlayPause"); state.status = state.status === "Playing" ? "Paused" : "Playing"; Interface.emitPropertiesChanged(this, { PlaybackStatus: state.status }, []); }
  Play() { calls.push("Play"); } Pause() { calls.push("Pause"); } Stop() { calls.push("Stop"); }
  Next() { calls.push("Next"); } Previous() { calls.push("Previous"); }
  Seek(offset) { calls.push(`Seek(${offset})`); state.position += offset; this.Seeked(state.position); }
  SetPosition(trackId, pos) { calls.push(`SetPosition(${trackId},${pos})`); state.position = pos; this.Seeked(pos); }
  OpenUri(u) { calls.push(`OpenUri(${u})`); }
  Seeked(pos) { return pos; }
}
Player.configureMembers({
  properties: { PlaybackStatus: { signature: "s", access: ACCESS_READ }, LoopStatus: { signature: "s", access: ACCESS_READWRITE }, Rate: { signature: "d", access: ACCESS_READWRITE }, Shuffle: { signature: "b", access: ACCESS_READWRITE }, Metadata: { signature: "a{sv}", access: ACCESS_READ }, Volume: { signature: "d", access: ACCESS_READWRITE }, Position: { signature: "x", access: ACCESS_READ }, MinimumRate: { signature: "d", access: ACCESS_READ }, MaximumRate: { signature: "d", access: ACCESS_READ }, CanGoNext: { signature: "b", access: ACCESS_READ }, CanGoPrevious: { signature: "b", access: ACCESS_READ }, CanPlay: { signature: "b", access: ACCESS_READ }, CanPause: { signature: "b", access: ACCESS_READ }, CanSeek: { signature: "b", access: ACCESS_READ }, CanControl: { signature: "b", access: ACCESS_READ } },
  methods: { Next: {}, Previous: {}, Pause: {}, PlayPause: {}, Stop: {}, Play: {}, Seek: { inSignature: "x" }, SetPosition: { inSignature: "ox" }, OpenUri: { inSignature: "s" } },
  signals: { Seeked: { signature: "x" } },
});
const player = new Player("org.mpris.MediaPlayer2.Player");
const bus = dbus.sessionBus();
bus.export("/org/mpris/MediaPlayer2", root); bus.export("/org/mpris/MediaPlayer2", player);
await bus.requestName("org.mpris.MediaPlayer2.gpuixshell", 0x4 /* DO_NOT_QUEUE */);
console.error("mpris-probe: name acquired on", process.env.DBUS_SESSION_BUS_ADDRESS?.replace(/guid=.*/, "guid=…"));
process.on("SIGTERM", () => { console.log(JSON.stringify({ calls, final: { ...state, position: Number(state.position) } })); process.exit(0); });
