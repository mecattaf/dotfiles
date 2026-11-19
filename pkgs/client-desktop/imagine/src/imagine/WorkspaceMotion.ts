// Presentation adapter for the public Stage at Manganese 67c29a9, MIT (LICENSE).
// Stage keeps the window list, logical direction, late offsets and completion.
import { movingStyles } from "@domicile-desktop/manganese-window-management/window-styles";
import { useLayoutEffect, useRef } from "react";

const motions = ["arriving-from-end", "arriving-from-start", "leaving-to-end", "leaving-to-start"] as const;
const names = ["agencyWorkspaceFromBelow", "agencyWorkspaceFromAbove", "agencyWorkspaceToBelow", "agencyWorkspaceToAbove"];
// The public recipe also covers parts without data-motion, such as group wells.
const selectors = motions.map((motion) => `.${movingStyles({ motion }).split(/\s+/).join(".")}`);
const switching = selectors.join(", ");
const scoped = selectors.map((selector) => `.agency-desktop ${selector}`).join(", ");
const reduced = selectors.map((selector) => `[data-reduced-motion] .agency-desktop ${selector}`).join(", ");
const HEIGHT = "--agency-workspace-height";

/** Full logical screen height from Stage's workspace-switch clipping rectangle. */
export const workspaceHeight = (clip: string): number | undefined => {
  const match = /^rect\((.*)\)$/.exec(clip.trim());
  if (match === null) return undefined;
  const parts = match[1]!.split(",").map((part) => part.trim());
  if (parts.length !== 4 || parts.some((part) => !/^[+-]?(?:\d+\.?\d*|\.\d+)(?:e[+-]?\d+)?px$/i.test(part))) {
    return undefined;
  }
  const [top, right, bottom, left] = parts.map(Number.parseFloat) as [number, number, number, number];
  if (![top, right, bottom, left].every(Number.isFinite) || right <= left || bottom <= top) return undefined;
  return bottom - top;
};

/** Give every switching part its screen extent, including small floats and late contents. */
export const applyWorkspaceHeights = (root: HTMLElement): void => {
  for (const part of root.querySelectorAll<HTMLElement>(switching)) {
    for (let wrapper = part.parentElement; wrapper !== null && wrapper !== root; wrapper = wrapper.parentElement) {
      // Stock WindowFrame/Sliding clips to geometry.screen, not frame/workspace.
      // Reading that same rectangle also covers leaving windows on their old screen.
      const height = workspaceHeight(wrapper.style.clip);
      if (height === undefined) continue;
      const value = `${height}px`;
      if (wrapper.style.getPropertyValue(HEIGHT) !== value) wrapper.style.setProperty(HEIGHT, value);
      break;
    }
  }
};

/** Scope the adapter to this desktop without replacing any Stage or guest node. */
export const useWorkspaceMotion = () => {
  const root = useRef<HTMLDivElement>(null);
  useLayoutEffect(() => {
    const element = root.current;
    if (element === null) return;
    const apply = () => applyWorkspaceHeights(element);
    apply();
    const observer = new MutationObserver(apply);
    observer.observe(element, { subtree: true, childList: true,
      attributes: true, attributeFilter: ["style", "class"] });
    return () => observer.disconnect();
  }, []);
  return root;
};

/** Workspace-only CSS uses public recipe selectors, not generated hash literals. */
export const WORKSPACE_MOTION_CSS = `
${scoped} {
  animation-duration: 35ms;
  animation-timing-function: cubic-bezier(0.25, 0.1, 0.25, 1);
}
${selectors.map((selector, index) => `.agency-desktop ${selector} { animation-name: ${names[index]}; }`).join("\n")}
@keyframes agencyWorkspaceFromBelow {
  from { transform: translateY(var(--agency-workspace-height)); }
  to { transform: translateY(0); }
}
@keyframes agencyWorkspaceFromAbove {
  from { transform: translateY(calc(-1 * var(--agency-workspace-height))); }
  to { transform: translateY(0); }
}
@keyframes agencyWorkspaceToBelow {
  from { transform: translateY(0); }
  to { transform: translateY(var(--agency-workspace-height)); }
}
@keyframes agencyWorkspaceToAbove {
  from { transform: translateY(0); }
  to { transform: translateY(calc(-1 * var(--agency-workspace-height))); }
}

/* Keep an animation so Stage receives completion; reduced motion does not pan. */
@keyframes agencyWorkspaceStill {
  from { transform: none; }
  to { transform: none; }
}

${reduced} { animation-name: agencyWorkspaceStill; }
/* Join the stock layer: layered important rules beat unlayered ones. */
@layer base {
  ${reduced} { animation-duration: 1ms !important; }
}
@media (prefers-reduced-motion: reduce) {
  ${scoped} { animation-name: agencyWorkspaceStill; animation-duration: 1ms; animation-delay: 0ms; }
}
`;
