// Probe (READ-ONLY): shape of the server-side play queue. Never calls save*, scrobble or reportPlayback.
import { call } from "./subsonic.mjs";
const a = await call("getPlayQueueByIndex"); const b = await call("getPlayQueue");
const shape = (r, key) => { const q = r?.[key]; return { status: r.status, error: r.error?.message, keys: q ? Object.keys(q) : null, entries: q?.entry?.length ?? 0, currentIndex: q?.currentIndex, current: q?.current ? "(id)" : undefined, position: q?.position, changedBy: q?.changedBy, changed: q?.changed }; };
console.log(JSON.stringify({ byIndex: shape(a, "playQueueByIndex"), classic: shape(b, "playQueue") }, null, 1));
