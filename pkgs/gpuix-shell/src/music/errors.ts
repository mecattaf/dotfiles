// src/music/errors.ts — FROZEN CONTRACT (MUSIC.md §6.1). One error type for reads, one mapping
// from Subsonic failures to the words every surface shows (05 §3.5). Messages name the credential
// file's PATH at most, never its content.
import { SubsonicError } from "./subsonic/api";
import type { MusicError } from "./types";

/** Reads on a MusicBackend reject with this; commands resolve `{ ok: false, error }` instead. */
export class MusicFailure extends Error {
  constructor(public readonly music: MusicError) {
    super(music.message);
    this.name = "MusicFailure";
  }
}

export function isMusicFailure(e: unknown): e is MusicFailure {
  return e instanceof Error && e.name === "MusicFailure" && "music" in e;
}

export function isAbort(e: unknown): boolean {
  return e instanceof Error && (e.name === "AbortError" || (e instanceof SubsonicError && e.kind === "aborted"));
}

/** Map anything thrown below the backend to a MusicError. `host` is for the offline sentence only. */
export function toMusicError(e: unknown, o: { host?: string; credentialsFile?: string } = {}): MusicError {
  if (isMusicFailure(e)) return e.music;
  const host = o.host ?? "music.internal";
  if (e instanceof SubsonicError) {
    switch (e.kind) {
      case "credentials":
        return {
          code: "unauthorized",
          message: "No Navidrome credentials on this machine",
          fix: `Check ${o.credentialsFile ?? "/run/agenix/navidrome-credentials"}`,
        };
      case "auth":
        return {
          code: "unauthorized",
          message: "Navidrome refused the saved credentials",
          fix: `Check ${o.credentialsFile ?? "/run/agenix/navidrome-credentials"}`,
        };
      case "unreachable":
      case "timeout":
        return { code: "offline", message: `Can't reach Navidrome at ${host}`, fix: "Check Tailscale or the closet LAN, then press Ctrl+R" };
      case "forbidden":
        return { code: "forbidden", message: "Navidrome says this account may not do that" };
      case "not-found":
        return { code: "not-found", message: "Navidrome no longer has this item" };
      case "usage":
        return { code: "usage", message: e.message };
      case "aborted":
        return { code: "player", message: "Cancelled" };
      default:
        return { code: "player", message: e.message };
    }
  }
  return { code: "player", message: e instanceof Error ? e.message : String(e) };
}
