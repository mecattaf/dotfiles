// Imagine presentation policy on the pinned public StageScreen contract.
// Window/process/guest identities and the upstream window state remain untouched.
import type { Placement } from "@domicile-desktop/manganese-window-management/placement";
import type { StageScreen } from "@domicile-desktop/manganese-window-management/screens/stage-screens";

export type ChromeVisibility = ReadonlySet<string>;

/** A preference for this running window, never an application-wide PID/title rule. */
export const setChromeHidden = (current: ChromeVisibility, id: string, hidden: boolean): ChromeVisibility => {
  if (current.has(id) === hidden) return current;
  const next = new Set(current);
  if (hidden) next.add(id); else next.delete(id);
  return next;
};

export const toggleChrome = (current: ChromeVisibility, id: string): ChromeVisibility =>
  setChromeHidden(current, id, !current.has(id));

/** Closed windows do not leave a preference that a later host id could inherit. */
export const pruneChromeVisibility = (current: ChromeVisibility, live: ReadonlySet<string>): ChromeVisibility => {
  const next = new Set([...current].filter((id) => live.has(id)));
  return next.size === current.size ? current : next;
};

export type ChromeCommandResult = {
  readonly handled: boolean;
  readonly hidden: ChromeVisibility;
  readonly error?: string;
};

/** Words after `imagine`: `chrome toggle|show|hide [running-window-id]`. */
export const chromeCommand = (current: ChromeVisibility, args: readonly string[],
  activeId: string | undefined, live: ReadonlySet<string>): ChromeCommandResult => {
  if (args[0] !== "chrome") return { handled: false, hidden: current };
  const [, operation, explicit, ...rest] = args;
  if (rest.length > 0 || !["toggle", "show", "hide"].includes(operation ?? "")) {
    return { handled: true, hidden: current, error: "Usage: imagine chrome toggle|show|hide [running-window-id]" };
  }
  const id = explicit ?? activeId;
  if (id === undefined || !live.has(id)) {
    return { handled: true, hidden: current, error: "Imagine chrome: no matching running window" };
  }
  return { handled: true, hidden: operation === "toggle" ? toggleChrome(current, id)
    : setChromeHidden(current, id, operation === "hide") };
};

type Strip = NonNullable<Placement["strip"]>;
// Equal across all tabs of the same strip; distinct for nested strips.
const stripKey = (strip: Strip, depth: number): string => JSON.stringify([
  depth, strip.group.wells, strip.group.node.up,
  [...strip.group.windows].sort(), strip.area,
]);

export type ChromePresentation = {
  readonly screens: readonly StageScreen[];
  /** Only non-fullscreen, shell-decorated contents need replacement top corners. */
  readonly roundedWindows: ReadonlySet<string>;
};

/**
 * Hide chrome around a running window without changing its tree or host id.
 *
 * A strip is shared: when its visible window has the preference, hide the
 * whole immediate strip. Selecting a sibling without that preference restores
 * it. Ancestor container tabs remain available. Hidden sibling contents stay
 * hidden; switching tabs remains the stock reducer's job.
 *
 * Stock bare dialogs/page fullscreen are left alone. A manually fullscreen
 * group may hide its bar, but receives no artificial rounding at the screen edge.
 */
export const presentChrome = (screens: readonly StageScreen[], hidden: ChromeVisibility): ChromePresentation => {
  const roundedWindows = new Set<string>();
  if (hidden.size === 0) return { screens, roundedWindows };
  let changed = false;
  const next = screens.map((screen) => {
    const placements = screen.screenful.placements;
    const strips = new Set(placements.flatMap((place) =>
      !place.bare && place.surface !== undefined && hidden.has(place.id) && place.strip !== undefined
        ? [stripKey(place.strip, place.depth)] : []));
    let screenChanged = false;
    const laidOut = placements.map((place) => {
      if (place.bare) return place;
      const inHiddenStrip = place.strip !== undefined && strips.has(stripKey(place.strip, place.depth));
      const alone = place.strip === undefined && hidden.has(place.id) && place.surface !== undefined;
      if (!inHiddenStrip && !alone) return place;
      screenChanged = true;
      const frame = place.surface === undefined ? place.frame : place.strip?.area ?? place.frame;
      if (place.surface !== undefined && !screen.fullscreen?.windows.includes(place.id)) roundedWindows.add(place.id);
      return { ...place, bare: true, frame,
        surface: place.surface === undefined ? undefined : frame,
        // Neither WindowBar nor GroupStrip should reserve or draw chrome.
        strip: undefined, tabbed: undefined,
        bar: { ...frame, height: 0 },
      };
    });
    const tabs = screen.screenful.tabs.filter((tab) => !strips.has(stripKey(tab.strip, tab.depth)));
    if (!screenChanged && tabs.length === screen.screenful.tabs.length) return screen;
    changed = true;
    return { ...screen, screenful: { ...screen.screenful, placements: laidOut, tabs } };
  });
  return { screens: changed ? next : screens, roundedWindows };
};

// CSS strings, not selectors assembled from unescaped host titles or URLs.
const cssString = (value: string): string => `"${[...value].map((character) =>
  /[A-Za-z0-9_-]/.test(character) ? character : `\\${character.codePointAt(0)!.toString(16)} `).join("")}"`;

/**
 * Stock Stage suppresses WindowBar for bare placements, but its content wrapper
 * normally gets only bottom corners. Restore its top border/corners locally.
 * No DOM replacement, global theme edit, fullscreen request, or page reload.
 */
export const roundedChromeCss = (windows: ReadonlySet<string>): string => [...windows].map((id) => {
  const target = id.startsWith("app:")
    ? `div:has(> app[app-id=${cssString(id.slice(4))}])`
    : id.startsWith("browser:")
      ? `section[aria-label="Browser"]:has(webview[window=${cssString(id.slice(8))}])`
      : undefined;
  return target === undefined ? "" : `.agency-desktop [data-window-frame] > ${target}{border-start-start-radius:8px!important;border-start-end-radius:8px!important;border-block-start-width:1px!important}`;
}).join("\n");
