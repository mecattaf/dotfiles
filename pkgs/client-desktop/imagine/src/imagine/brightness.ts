// Agency controls actual internal DRM backlights through public SDK/logind calls.
// The stock backlight picker can choose asus_screenpad; the Duo uses its two
// DRM eDP devices. Read-only client confirmation, 2026-11-05: intel_backlight
// and card1-eDP-2-backlight each expose max_brightness=400.
import type { Domicile } from "@domicile-desktop/sdk/desktop/desktop";
import { Bus, SystemErrorKind } from "@domicile-desktop/sdk/system";
import { levelOf } from "@domicile-desktop/system-backlight/read-backlight";
import type { Backlight } from "@domicile-desktop/system-backlight/read-backlight";

type Host = Pick<Domicile, "files" | "dbus">;
export type BrightnessLevel = {
  readonly level: number;
  readonly muted: false;
  readonly blanked: boolean;
  readonly devices: readonly string[];
};
export type BrightnessController = {
  step: (direction: "up" | "down", percent?: number) => Promise<BrightnessLevel | undefined>;
  set: (level: number) => Promise<BrightnessLevel | undefined>;
  /** F10's explicit blank/restore is the only operation allowed to write zero. */
  toggle: () => Promise<BrightnessLevel | undefined>;
  dispose: () => void;
};

const BACKLIGHT = "/sys/class/backlight";

/** Read canonical device paths: a platform keyboard/screenpad is not a panel. */
export const readDuoBacklights = async (host: Host): Promise<readonly Backlight[]> => {
  const entries = (await host.files.readDir(BACKLIGHT)).match({
    Ok: (value) => value,
    Err: (error) => { throw Error(`Cannot list backlights: ${error.message}`); },
  });
  const devices = await Promise.all(entries.map(async ({ name }) => {
    if (!/^[A-Za-z0-9_.-]+$/.test(name)) throw Error("Invalid backlight device name");
    const path = `${BACKLIGHT}/${name}`;
    const stat = (await host.files.stat(path)).match({
      Ok: (value) => value,
      Err: (error) => {
        if (error.kind === SystemErrorKind.NotFound) return undefined;
        throw Error(`Cannot inspect backlight ${name}: ${error.message}`);
      },
    });
    if (stat?.realPath === undefined || !/\/drm\/.*-eDP-[0-9]+\//.test(stat.realPath)) return undefined;
    const read = async (file: string) => (await host.files.readText(`${path}/${file}`)).match({
      Ok: (text) => text.trim(),
      Err: (error) => { throw Error(`Cannot read ${name}/${file}: ${error.message}`); },
    });
    const [rawText, maxText] = await Promise.all([read("brightness"), read("max_brightness")]);
    if (!/^\d+$/.test(rawText) || !/^\d+$/.test(maxText)) throw Error(`Invalid brightness data for ${name}`);
    const max = Number(maxText);
    const raw = Number(rawText);
    if (!Number.isSafeInteger(max) || max < 1 || !Number.isSafeInteger(raw)) throw Error(`Invalid brightness range for ${name}`);
    return { device: name, raw: Math.min(raw, max), max };
  }));
  return devices.filter((device): device is Backlight => device !== undefined)
    .sort((a, b) => Number(b.device === "intel_backlight") - Number(a.device === "intel_backlight") || a.device.localeCompare(b.device));
};

export const createBrightnessController = (host: Host): BrightnessController => {
  let pending: Promise<unknown> = Promise.resolve();
  let disposed = false;
  let restoreLevel = 0.5;
  const queue = (operation: () => Promise<BrightnessLevel | undefined>) => {
    const result = pending.then(() => disposed ? undefined : operation());
    // The caller still receives the rejection; a failed key must not poison later keys.
    pending = result.then(() => undefined, () => undefined);
    return result;
  };
  const write = async (devices: readonly Backlight[], level: number, blank = false): Promise<BrightnessLevel | undefined> => {
    const primary = devices[0];
    if (primary === undefined || disposed) return undefined;
    const target = Math.min(1, Math.max(0, level));
    const rawFor = (device: Backlight) => blank ? 0 : Math.max(1, Math.round(target * device.max));
    // Send the pair together: an accepted key synchronizes both panels even
    // if this shell is disposed while the D-Bus calls are already in flight.
    const results = await Promise.allSettled(devices.map(async (device) => {
      const reply = await host.dbus.call({
        bus: Bus.System, destination: "org.freedesktop.login1",
        path: "/org/freedesktop/login1/session/auto", interface: "org.freedesktop.login1.Session",
        member: "SetBrightness", signature: "ssu", body: ["backlight", device.device, rawFor(device)],
      });
      reply.match({ Ok: () => undefined, Err: (error) => { throw Error(`${device.device}: ${error.message}`); } });
    }));
    const failures = results.flatMap((result) => result.status === "rejected" ? [result.reason] : []);
    if (failures.length > 0) throw new AggregateError(failures, "Could not set every DRM panel backlight");
    return { level: rawFor(primary) / primary.max, muted: false, blanked: blank, devices: devices.map(({ device }) => device) };
  };
  return {
    step: (direction, percent = 10) => queue(async () => {
      if (!Number.isFinite(percent) || percent <= 0 || percent > 100) throw Error("Brightness step must be between 0 and 100 percent");
      const devices = await readDuoBacklights(host);
      const primary = devices[0];
      return primary === undefined ? undefined : write(devices, levelOf(primary) + (direction === "up" ? 1 : -1) * percent / 100);
    }),
    set: (level) => queue(async () => {
      if (!Number.isFinite(level)) throw Error("Brightness must be finite");
      return write(await readDuoBacklights(host), level);
    }),
    toggle: () => queue(async () => {
      const devices = await readDuoBacklights(host);
      const primary = devices[0];
      if (primary === undefined) return undefined;
      if (primary.raw === 0) return write(devices, restoreLevel);
      restoreLevel = levelOf(primary);
      return write(devices, 0, true);
    }),
    dispose: () => { disposed = true; },
  };
};
