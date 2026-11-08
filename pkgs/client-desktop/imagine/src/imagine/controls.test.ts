import { describe, expect, test } from "bun:test";
import { Err, Ok } from "@cprussin/option-result";
import { Bus, FileType, SystemErrorKind } from "@domicile-desktop/sdk/system";
import type { DbusCall } from "@domicile-desktop/sdk/system";
import { createBrightnessController, readDuoBacklights } from "./brightness";
import { createMediaController } from "./media";

type Panel = { path: string; raw: number; max: number };
const brightnessFixture = () => {
  const panels = new Map<string, Panel>([
    ["asus_screenpad", { path: "/sys/devices/platform/asus-nb-wmi/backlight/asus_screenpad", raw: 100, max: 255 }],
    ["card1-eDP-2-backlight", { path: "/sys/devices/pci0000:00/drm/card1/card1-eDP-2/card1-eDP-2-backlight", raw: 400, max: 400 }],
    ["intel_backlight", { path: "/sys/devices/pci0000:00/drm/card1/card1-eDP-1/intel_backlight", raw: 400, max: 400 }],
  ]);
  const calls: DbusCall[] = [];
  let denied: string | undefined;
  const host = {
    files: {
      readDir: async () => Ok([...panels.keys()].map((name) => ({ name, fileType: FileType.Symlink }))),
      stat: async (path: string) => Ok({ realPath: panels.get(path.split("/").at(-1)!)?.path }),
      readText: async (path: string) => {
        const parts = path.split("/");
        const panel = panels.get(parts.at(-2)!);
        if (panel === undefined) return Err({ kind: SystemErrorKind.NotFound, message: "gone" });
        return Ok(String(parts.at(-1) === "max_brightness" ? panel.max : panel.raw));
      },
    },
    dbus: { call: async (call: DbusCall) => {
      calls.push(call);
      const device = call.body?.[1] as string;
      if (device === denied) return Err({ kind: SystemErrorKind.PermissionDenied, message: "fixture denied" });
      panels.get(device)!.raw = call.body?.[2] as number;
      return Ok({ signature: "", body: [] });
    } },
  };
  return { host: host as any, panels, calls, deny: (name: string) => { denied = name; } };
};

describe("native Duo brightness", () => {
  test("selects both DRM eDP panels, prioritizes intel and excludes screenpad", async () => {
    const f = brightnessFixture();
    expect((await readDuoBacklights(f.host)).map(({ device }) => device)).toEqual(["intel_backlight", "card1-eDP-2-backlight"]);
    const result = await createBrightnessController(f.host).step("down");
    expect(result?.level).toBe(0.9);
    expect(f.panels.get("intel_backlight")?.raw).toBe(360);
    expect(f.panels.get("card1-eDP-2-backlight")?.raw).toBe(360);
    expect(f.panels.get("asus_screenpad")?.raw).toBe(100);
    expect(f.calls).toHaveLength(2);
    for (const call of f.calls) expect(call).toMatchObject({
      bus: Bus.System, destination: "org.freedesktop.login1", path: "/org/freedesktop/login1/session/auto",
      interface: "org.freedesktop.login1.Session", member: "SetBrightness", signature: "ssu",
    });
  });
  test("two percent fine steps and maximum use the same selected pair", async () => {
    const f = brightnessFixture(); const control = createBrightnessController(f.host);
    expect((await control.step("down", 2))?.level).toBe(0.98);
    expect(f.panels.get("intel_backlight")?.raw).toBe(392);
    expect(f.panels.get("card1-eDP-2-backlight")?.raw).toBe(392);
    expect((await control.set(1))?.level).toBe(1);
  });
  test("normal controls keep the visible floor and synchronize different raw ranges", async () => {
    const f = brightnessFixture();
    f.panels.get("card1-eDP-2-backlight")!.max = 800;
    const control = createBrightnessController(f.host);
    await control.set(0.5);
    expect(f.panels.get("intel_backlight")?.raw).toBe(200);
    expect(f.panels.get("card1-eDP-2-backlight")?.raw).toBe(400);
    await control.set(0);
    expect(f.panels.get("intel_backlight")?.raw).toBe(1);
    expect(f.panels.get("card1-eDP-2-backlight")?.raw).toBe(1);
    await control.step("down");
    expect(f.panels.get("intel_backlight")?.raw).toBe(1);
  });
  test("F10 explicitly blanks and restores the previously selected level", async () => {
    const f = brightnessFixture(); const control = createBrightnessController(f.host);
    await control.set(0.4);
    expect(await control.toggle()).toMatchObject({ blanked: true, level: 0 });
    expect(f.panels.get("card1-eDP-2-backlight")?.raw).toBe(0);
    expect(await control.toggle()).toMatchObject({ blanked: false, level: 0.4 });
    expect(f.panels.get("intel_backlight")?.raw).toBe(160);
    expect(f.panels.get("card1-eDP-2-backlight")?.raw).toBe(160);
  });
  test("repeat presses are serialized without lost increments", async () => {
    const f = brightnessFixture(); const control = createBrightnessController(f.host);
    await Promise.all([control.step("down"), control.step("down"), control.step("down", 2)]);
    expect(f.panels.get("intel_backlight")?.raw).toBe(312);
    expect(f.panels.get("card1-eDP-2-backlight")?.raw).toBe(312);
  });
  test("partial failures reject and do not poison the next key", async () => {
    const f = brightnessFixture(); const control = createBrightnessController(f.host);
    f.deny("card1-eDP-2-backlight");
    await expect(control.step("down")).rejects.toThrow(AggregateError);
    expect(f.calls).toHaveLength(2);
    await expect(control.step("up", 2)).rejects.toThrow(AggregateError);
    expect(f.calls).toHaveLength(4);
  });
  test("no DRM panels and disposed controls make no hardware calls", async () => {
    const f = brightnessFixture();
    f.panels.delete("intel_backlight"); f.panels.delete("card1-eDP-2-backlight");
    expect(await createBrightnessController(f.host).step("down")).toBeUndefined();
    const control = createBrightnessController(f.host); control.dispose();
    expect(await control.toggle()).toBeUndefined();
    expect(f.calls).toEqual([]);
  });
  test("bad levels and invalid ranges fail before hardware writes", async () => {
    const f = brightnessFixture(); const control = createBrightnessController(f.host);
    await expect(control.set(Number.NaN)).rejects.toThrow("finite");
    await expect(control.step("down", 0)).rejects.toThrow("percent");
    f.panels.get("intel_backlight")!.max = 0;
    await expect(control.step("down")).rejects.toThrow("range");
    expect(f.calls).toEqual([]);
  });
});

type PlayerFixture = { status: string; title: string; artists: string[]; control?: boolean; next?: boolean };
const mediaFixture = () => {
  const players = new Map<string, PlayerFixture>();
  const calls: DbusCall[] = [];
  const vanished = new Set<string>();
  let denied = false;
  const v = (signature: string, value: unknown) => ({ signature, value });
  const host = { dbus: { call: async (call: DbusCall) => {
    calls.push(call);
    if (call.member === "ListNames") return Ok({ signature: "as", body: [[":1.23", "org.example.Unrelated", ...players.keys()]] });
    const player = players.get(call.destination)!;
    if (vanished.has(call.destination)) return Err({ kind: SystemErrorKind.Dbus, message: "org.freedesktop.DBus.Error.NameHasNoOwner: fixture gone" });
    if (call.member === "GetAll") return Ok({ signature: "a{sv}", body: [{
      PlaybackStatus: v("s", player.status),
      Metadata: v("a{sv}", { "xesam:title": v("s", player.title), "xesam:artist": v("as", player.artists) }),
      CanControl: v("b", player.control ?? true), CanGoNext: v("b", player.next ?? true),
      CanGoPrevious: v("b", true), CanPlay: v("b", true), CanPause: v("b", true),
    }] });
    if (denied) return Err({ kind: SystemErrorKind.PermissionDenied, message: "fixture denied" });
    if (call.member === "PlayPause") player.status = player.status === "Playing" ? "Paused" : "Playing";
    if (call.member === "Next") player.title = "Next track";
    if (call.member === "Previous") player.title = "Previous track";
    return Ok({ signature: "", body: [] });
  } } };
  const add = (name: string, status: string, extra: Partial<PlayerFixture> = {}) => {
    const id = "org.mpris.MediaPlayer2." + name;
    players.set(id, { status, title: "Current track", artists: ["Fixture artist"], ...extra });
    return id;
  };
  return { host: host as any, players, calls, vanished, add, deny: () => { denied = true; } };
};

describe("native MPRIS controls", () => {
  test("prefers a playing player and returns fresh metadata/status", async () => {
    const f = mediaFixture(); f.add("a_paused", "Paused"); const playing = f.add("z_playing", "Playing");
    const control = createMediaController(f.host);
    expect(await control.press("play-pause")).toMatchObject({ player: playing, status: "Paused", title: "Current track", artists: ["Fixture artist"] });
    const action = f.calls.find(({ member }) => member === "PlayPause");
    expect(action).toMatchObject({ bus: Bus.Session, destination: playing, path: "/org/mpris/MediaPlayer2", interface: "org.mpris.MediaPlayer2.Player" });
  });
  test("next/previous return the track the player reports after invocation", async () => {
    const f = mediaFixture(); f.add("fixture", "Playing"); const control = createMediaController(f.host);
    expect((await control.press("next"))?.title).toBe("Next track");
    expect((await control.press("previous"))?.title).toBe("Previous track");
  });
  test("capabilities exclude a noncontrollable player or unsupported action", async () => {
    const f = mediaFixture(); f.add("a_disabled", "Playing", { control: false });
    f.add("b_no_next", "Playing", { next: false }); const capable = f.add("z_capable", "Paused");
    expect((await createMediaController(f.host).press("next"))?.player).toBe(capable);
  });
  test("an empty player list and disposal never invoke transport methods", async () => {
    const f = mediaFixture(); const control = createMediaController(f.host);
    expect(await control.press("next")).toBeUndefined();
    f.add("fixture", "Playing"); control.dispose();
    expect(await control.press("play-pause")).toBeUndefined();
    expect(f.calls.filter(({ interface: iface }) => iface === "org.mpris.MediaPlayer2.Player")).toEqual([]);
  });
  test("enumeration races skip only disappeared owners", async () => {
    const f = mediaFixture(); const gone = f.add("a_gone", "Playing"); f.vanished.add(gone);
    const remaining = f.add("z_remaining", "Paused");
    expect((await createMediaController(f.host).press("play-pause"))?.player).toBe(remaining);
  });
  test("real permission failures surface instead of being called no player", async () => {
    const f = mediaFixture(); f.add("fixture", "Playing"); f.deny();
    await expect(createMediaController(f.host).press("next")).rejects.toThrow("fixture denied");
  });
  test("repeated play/pause calls are serialized in key order", async () => {
    const f = mediaFixture(); f.add("fixture", "Paused"); const control = createMediaController(f.host);
    const answers = await Promise.all([control.press("play-pause"), control.press("play-pause")]);
    expect(answers.map((answer) => answer?.status)).toEqual(["Playing", "Paused"]);
  });
});
