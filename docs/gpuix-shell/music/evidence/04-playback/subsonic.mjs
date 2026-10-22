// Minimal Subsonic token-auth helper for probes. Reads credentials at runtime; never logs them.
import { readFileSync } from "node:fs";
import { createHash, randomBytes } from "node:crypto";
export const BASE = (process.env.NAVIDROME_URL ?? "http://music.internal").replace(/\/$/, "");
function creds() {
  const text = readFileSync(process.env.NAVIDROME_CREDENTIALS_FILE ?? "/run/agenix/navidrome-credentials", "utf8");
  const get = (k) => (text.match(new RegExp(`^${k}=(.*)$`, "m"))?.[1] ?? "").trim().replace(/^["']|["']$/g, "");
  return { user: get("NAVIDROME_USER"), password: get("NAVIDROME_PASSWORD") };
}
export function authParams() {
  const { user, password } = creds();
  const s = randomBytes(8).toString("hex");
  const t = createHash("md5").update(password + s).digest("hex");
  return new URLSearchParams({ u: user, t, s, v: "1.16.1", c: "gpuix-shell", f: "json" });
}
export function url(endpoint, params = {}) {
  const q = authParams(); for (const [k, v] of Object.entries(params)) q.set(k, String(v));
  return `${BASE}/rest/${endpoint}?${q}`;
}
export async function call(endpoint, params) { const r = await fetch(url(endpoint, params)); return (await r.json())["subsonic-response"]; }
export const redact = (s) => String(s).replace(/([?&](?:u|t|s|p|apiKey)=)[^&\s"']+/g, "$1REDACTED");
