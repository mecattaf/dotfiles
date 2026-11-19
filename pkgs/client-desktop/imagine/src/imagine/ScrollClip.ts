import { useLayoutEffect, useRef } from "react";
import type { RefObject } from "react";
import type { Rect } from "@domicile-desktop/manganese-window-management/rect";
import type { StageScreen } from "@domicile-desktop/manganese-window-management/screens/stage-screens";

type Property = "clip" | "clipPath";
type OwnedClip = { readonly property: Property; readonly before: string; readonly applied: string; readonly shape: string };
export type ScrollClipOwnership = Map<HTMLElement, OwnedClip>;
export const scrollClipTargets = (screens: readonly StageScreen[], scrollWorkspace: (name: string) => boolean): ReadonlyMap<string, Rect> =>
  new Map(screens.filter(screen => scrollWorkspace(screen.current) && screen.fullscreen === undefined)
    .flatMap(screen => screen.screenful.placements.filter(placement => placement.depth === 0)
      .map(placement => [placement.id, screen.geometry.workspace] as const)));

export const scrollViewportClip = (viewport: Rect) =>
  `rect(${viewport.y}px, ${viewport.x + viewport.width}px, ${viewport.y + viewport.height}px, ${viewport.x}px)`;

/** Insets are local to a grab sheet; the viewport itself uses page coordinates. */
export function scrollSheetClip(bounds: Pick<DOMRect, "x" | "y" | "width" | "height">, viewport: Rect): string {
  if (bounds.x >= viewport.x + viewport.width || bounds.x + bounds.width <= viewport.x
    || bounds.y >= viewport.y + viewport.height || bounds.y + bounds.height <= viewport.y) return "inset(50%)";
  return `inset(${Math.max(0, viewport.y - bounds.y)}px ${Math.max(0, bounds.x + bounds.width - viewport.x - viewport.width)}px ${Math.max(0, bounds.y + bounds.height - viewport.y - viewport.height)}px ${Math.max(0, viewport.x - bounds.x)}px)`;
}

const own = (element: HTMLElement, property: Property, shape: string, ownership: ScrollClipOwnership) => {
  const previous = ownership.get(element);
  const current = element.style[property];
  // CSSOM may normalize inset(0px 0px 0px 0px) to inset(0px). Compare the
  // normalized applied value too, so the observer never responds to itself.
  if (previous?.property === property && previous.shape === shape && previous.applied === current) return;
  const before = previous?.property === property && previous.applied === current ? previous.before : current;
  element.style[property] = shape;
  ownership.set(element, { property, before, shape, applied: element.style[property] });
  element.setAttribute("data-imagine-scroll-clip", "");
};
const release = (element: HTMLElement, ownership: ScrollClipOwnership) => {
  const owned = ownership.get(element);
  if (owned !== undefined && element.style[owned.property] === owned.applied) element.style[owned.property] = owned.before;
  element.removeAttribute("data-imagine-scroll-clip");
  ownership.delete(element);
};

/**
 * Stock Stage clips only while a workspace slides, because floating drags must
 * cross displays. Scrolling tiles need a permanent viewport clip, including
 * their transparent modifier-drag sheets, without replacing an app or guest.
 */
export function applyScrollClipping(root: HTMLElement, targets: ReadonlyMap<string, Rect>, ownership: ScrollClipOwnership): void {
  const retained = new Set<HTMLElement>();
  for (const wrapper of root.querySelectorAll<HTMLElement>("[data-window-frame]")) {
    const app = wrapper.querySelector("app[app-id]");
    const browser = app === null ? wrapper.querySelector("webview[window]") : null;
    const id = app !== null ? "app:" + app.getAttribute("app-id") : browser !== null ? "browser:" + browser.getAttribute("window") : undefined;
    const viewport = id === undefined ? undefined : targets.get(id);
    if (viewport === undefined) continue;
    own(wrapper, "clip", scrollViewportClip(viewport), ownership);
    retained.add(wrapper);
  }
  for (const sheet of root.querySelectorAll<HTMLElement>("[data-window]")) {
    const viewport = targets.get(sheet.getAttribute("data-window") ?? "");
    if (viewport === undefined) continue;
    own(sheet, "clipPath", scrollSheetClip(sheet.getBoundingClientRect(), viewport), ownership);
    retained.add(sheet);
  }
  for (const [element] of ownership) {
    if (retained.has(element)) continue;
    // A leaving workspace still owns its prior viewport until Stage removes it.
    if (root.contains(element) && element.querySelector('[data-motion="leaving-to-start"], [data-motion="leaving-to-end"]') !== null) continue;
    release(element, ownership);
  }
}

/** Reapply after Stage's render and motion styles, and remove only owned clips. */
export function useScrollClipping(root: RefObject<HTMLElement | null>, screens: readonly StageScreen[], scrollWorkspace: (name: string) => boolean) {
  const targets = useRef(scrollClipTargets(screens, scrollWorkspace));
  targets.current = scrollClipTargets(screens, scrollWorkspace);
  const ownership = useRef<ScrollClipOwnership>(new Map());
  useLayoutEffect(() => {
    const element = root.current;
    if (element !== null) applyScrollClipping(element, targets.current, ownership.current);
  }, [root, screens, scrollWorkspace]);
  useLayoutEffect(() => {
    const element = root.current;
    if (element === null) return;
    const owned = ownership.current;
    const apply = () => applyScrollClipping(element, targets.current, owned);
    const observer = new MutationObserver(apply);
    observer.observe(element, { subtree: true, childList: true,
      attributes: true, attributeFilter: ["style", "class", "data-motion", "app-id", "window", "data-window"] });
    apply();
    return () => {
      observer.disconnect();
      for (const [part] of owned) release(part, owned);
    };
  }, [root]);
}
