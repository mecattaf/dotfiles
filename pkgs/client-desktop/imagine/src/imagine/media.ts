// Bounded MPRIS keyboard controls through the shell's public session D-Bus API.
// No playerctl, subprocess, synthetic input or persistent background watcher.
import type { Domicile } from "@domicile-desktop/sdk/desktop/desktop";
import { Bus, SystemErrorKind } from "@domicile-desktop/sdk/system";
import type { DbusBody, SystemError } from "@domicile-desktop/sdk/system";

type Host = Pick<Domicile, "dbus">;
export type MediaAction = "play-pause" | "previous" | "next";
export type MediaSnapshot = {
  readonly player: string;
  readonly status: "Playing" | "Paused" | "Stopped";
  readonly title?: string;
  readonly artists: readonly string[];
};
export type MediaController = {
  read: () => Promise<MediaSnapshot | undefined>;
  press: (action: MediaAction) => Promise<MediaSnapshot | undefined>;
  dispose: () => void;
};
type Player = MediaSnapshot & { properties: Record<string, unknown> };
const PATH = "/org/mpris/MediaPlayer2";
const PLAYER = "org.mpris.MediaPlayer2.Player";
const METHOD = { "play-pause": "PlayPause", previous: "Previous", next: "Next" } as const;

const object = (value: unknown): Record<string, unknown> => {
  if (value === null || typeof value !== "object" || Array.isArray(value)) throw Error("Invalid MPRIS property dictionary");
  return value as Record<string, unknown>;
};
const variant = (value: unknown, signature: string): unknown => {
  const wrapped = object(value);
  if (wrapped.signature !== signature) throw Error(`Invalid MPRIS variant; expected ${signature}`);
  return wrapped.value;
};
const stringValue = (value: unknown): string => {
  if (typeof value !== "string") throw Error("Invalid MPRIS string");
  return value;
};
const vanished = (error: SystemError) => error.kind === SystemErrorKind.Dbus
  && /^org\.freedesktop\.DBus\.Error\.(ServiceUnknown|NameHasNoOwner)(?:[:\s]|$)/.test(error.message);

export const createMediaController = (host: Host): MediaController => {
  let lastPlayer: string | undefined;
  let pending: Promise<unknown> = Promise.resolve();
  let disposed = false;
  const properties = async (name: string): Promise<Player | undefined> => {
    const reply = await host.dbus.call({
      bus: Bus.Session, destination: name, path: PATH,
      interface: "org.freedesktop.DBus.Properties", member: "GetAll", signature: "s", body: [PLAYER],
    });
    const body = reply.match<DbusBody | undefined>({
      Ok: (value) => value,
      Err: (error) => {
        if (vanished(error)) return undefined;
        throw Error(`Cannot inspect ${name}: ${error.message}`);
      },
    });
    if (body === undefined) return undefined;
    if (body.signature !== "a{sv}" || body.body.length !== 1) throw Error("Invalid MPRIS GetAll reply");
    const props = object(body.body[0]);
    const status = stringValue(variant(props.PlaybackStatus, "s"));
    if (status !== "Playing" && status !== "Paused" && status !== "Stopped") throw Error("Invalid MPRIS playback status");
    const metadata = props.Metadata === undefined ? {} : object(variant(props.Metadata, "a{sv}"));
    const title = metadata["xesam:title"] === undefined ? undefined : stringValue(variant(metadata["xesam:title"], "s"));
    const artists = metadata["xesam:artist"] === undefined ? [] : variant(metadata["xesam:artist"], "as");
    if (!Array.isArray(artists) || artists.some((artist) => typeof artist !== "string")) throw Error("Invalid MPRIS artists");
    return { player: name, status, title, artists, properties: props };
  };
  const can = (player: Player, key: string) => player.properties[key] === undefined
    || variant(player.properties[key], "b") === true;
  const choose = async (action?: MediaAction): Promise<Player | undefined> => {
    if (disposed) return undefined;
    const reply = (await host.dbus.call({
      bus: Bus.Session, destination: "org.freedesktop.DBus", path: "/org/freedesktop/DBus",
      interface: "org.freedesktop.DBus", member: "ListNames",
    })).match({ Ok: (value) => value, Err: (error) => { throw Error(`Cannot list media players: ${error.message}`); } });
    if (reply.signature !== "as" || reply.body.length !== 1 || !Array.isArray(reply.body[0])
      || reply.body[0].some((name) => typeof name !== "string")) throw Error("Invalid D-Bus name listing");
    const names = (reply.body[0] as string[]).filter((name) => /^org\.mpris\.MediaPlayer2\.[A-Za-z0-9_.-]+$/.test(name));
    const players = (await Promise.all(names.map(properties))).filter((player): player is Player => player !== undefined);
    const rank = (player: Player) => (player.status === "Playing" ? 0 : player.status === "Paused" ? 1 : 2);
    return players.filter((player) => {
      if (!can(player, "CanControl")) return false;
      if (action === "next") return can(player, "CanGoNext");
      if (action === "previous") return can(player, "CanGoPrevious");
      return action === undefined || can(player, player.status === "Playing" ? "CanPause" : "CanPlay");
    }).sort((a, b) => rank(a) - rank(b) || Number(b.player === lastPlayer) - Number(a.player === lastPlayer) || a.player.localeCompare(b.player))[0];
  };
  const snapshot = ({ properties: _properties, ...value }: Player): MediaSnapshot => value;
  return {
    read: async () => {
      const player = await choose();
      return player === undefined ? undefined : snapshot(player);
    },
    press: (action) => {
      const result = pending.then(async () => {
        const player = await choose(action);
        if (player === undefined || disposed) return undefined;
        (await host.dbus.call({
          bus: Bus.Session, destination: player.player, path: PATH,
          interface: PLAYER, member: METHOD[action],
        })).match({ Ok: () => undefined, Err: (error) => { throw Error(`Cannot ${action}: ${error.message}`); } });
        lastPlayer = player.player;
        if (disposed) return undefined;
        // Read fresh state after the method. Players may publish later metadata
        // asynchronously; this snapshot is what they report now, never guessed.
        const current = await properties(player.player);
        return current === undefined ? undefined : snapshot(current);
      });
      pending = result.then(() => undefined, () => undefined);
      return result;
    },
    dispose: () => { disposed = true; },
  };
};
