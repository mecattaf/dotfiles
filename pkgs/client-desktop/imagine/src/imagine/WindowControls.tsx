import { Fragment, useEffect, useEffectEvent, useMemo, useState } from "react";
import { createPortal } from "react-dom";
import type { Geometry } from "@domicile-desktop/manganese-window-management/placement";
import type { StageScreen } from "@domicile-desktop/manganese-window-management/screens/stage-screens";
import { activeIdOf } from "@domicile-desktop/manganese-window-management/window-state";
import type { WindowState } from "@domicile-desktop/manganese-window-management/window-state";
import { windowsIn } from "./GaplessFrames";

export type WindowControlIntent = "close" | "minimize" | "zoom";
type IntentHandler = (id: string, intent: WindowControlIntent, geometry: Geometry) => void;

/** Left-side close, minimize and geometric zoom. The caller owns actions; the
 * component never launches, closes or changes any window by itself. */
export const WindowControls = ({active, zoomed = false, onIntent}: {
  active: boolean;
  zoomed?: boolean;
  onIntent: (intent: WindowControlIntent) => void;
}) => <div className="imagine-window-controls" data-active={active || undefined} role="group" aria-label="Window controls"
  onPointerDown={event => { event.preventDefault(); event.stopPropagation(); }} onDoubleClick={event => event.stopPropagation()}>
  {([
    ["close", "Close window", "×"],
    ["minimize", "Minimize to scratchpad", "−"],
    ["zoom", zoomed ? "Restore window size" : "Zoom to workspace", zoomed ? "↙" : "↗"],
  ] as const).map(([intent, label, glyph]) => <button key={intent} type="button" className={`imagine-window-control imagine-window-control-${intent}`}
    aria-label={label} title={label} onClick={event => { event.stopPropagation(); onIntent(intent); }}>
    <span aria-hidden="true">{glyph}</span>
  </button>)}
</div>;

export const WINDOW_CONTROLS_CSS = `
.imagine-window-controls { display:flex; gap:8px; align-items:center; width:max-content; height:18px; }
.imagine-window-control { all:unset; box-sizing:border-box; display:grid; place-items:center; width:13px; height:13px; border-radius:50%; background:#777572; color:#34302c; box-shadow:inset 0 0 0 .5px #0004; cursor:default; }
.imagine-window-control span { opacity:0; font:600 12px/1 system-ui; pointer-events:none; }
.imagine-window-controls:hover .imagine-window-control span, .imagine-window-control:focus-visible span { opacity:1; }
.imagine-window-control:focus-visible { outline:2px solid #fff; outline-offset:3px; }
.imagine-window-controls[data-active] .imagine-window-control-close { background:#ff5f57; }
.imagine-window-controls[data-active] .imagine-window-control-minimize { background:#febc2e; }
.imagine-window-controls[data-active] .imagine-window-control-zoom { background:#28c840; }
.imagine-window-control:active { filter:brightness(.82); }
[data-imagine-floating-controls] [data-face] > span:last-of-type { display:none; }
[data-imagine-floating-controls] [data-face] > span:first-of-type { padding-inline-start:74px; }
.imagine-window-controls-host { position:absolute; inset-inline-start:10px; top:50%; transform:translateY(-50%); z-index:2; }
`;

type Target = {id: string; geometry: Geometry; active: boolean; zoomed: boolean};
type PortalTarget = Target & {element: HTMLDivElement};

/** Add controls to the existing titlebar DOM rather than another window frame.
 * The portal therefore inherits the upstream bar's move/restack animations,
 * while its drag handle and tab interaction remain the stock implementation.
 * There is one group on the visible tab, never one group per hidden tab. */
export const FloatingWindowControls = ({state, screens, isFloatingWorkspace, zoomed = new Set<string>(), onIntent}: {
  state: WindowState;
  screens: readonly StageScreen[];
  isFloatingWorkspace: (workspace: string) => boolean;
  zoomed?: ReadonlySet<string>;
  onIntent: IntentHandler;
}) => {
  const active = activeIdOf(state);
  const targets = useMemo(() => screens.flatMap(screen => {
    if (!isFloatingWorkspace(screen.current) || screen.fullscreen !== undefined) return [];
    const workspace = state.workspaces.find(item => item.name === screen.current);
    if (workspace === undefined) return [];
    return workspace.floats.flatMap(float => {
      if (float.bare) return [];
      const ids = windowsIn(float.root);
      const visible = screen.screenful.placements.filter(place => ids.includes(place.id) && place.surface !== undefined && !place.bare);
      const place = visible.find(item => ids.includes(active ?? "") && item.id === active) ?? visible[0];
      if (place === undefined) return [];
      // A floating split is a group too; its controls live on its first visible
      // bar and operate on the window named there, as the stock controls do.
      return [{id: place.id, geometry: screen.geometry, active: ids.includes(active ?? ""), zoomed: ids.some(id => zoomed.has(id))}];
    });
  }), [active, isFloatingWorkspace, screens, state.workspaces, zoomed]);
  const [portals, setPortals] = useState<readonly PortalTarget[]>([]);
  const intent = useEffectEvent(onIntent);
  const currentTargets = useEffectEvent(() => targets);
  const signature = JSON.stringify(targets.map(({id, active, zoomed}) => [id, active, zoomed]));
  useEffect(() => {
    const root = document.querySelector(".agency-desktop");
    if (root === null) return;
    const hosts = new Map<HTMLElement, HTMLDivElement>();
    let scheduled: number | undefined;
    const refresh = () => {
      scheduled = undefined;
      const wanted = currentTargets();
      const next: PortalTarget[] = [];
      const used = new Set<HTMLElement>();
      for (const bar of root.querySelectorAll<HTMLElement>("[data-window][data-motion]")) {
        if (bar.inert) continue;
        const target = wanted.find(item => item.id === bar.dataset.window);
        const face = bar.querySelector<HTMLElement>("[data-face]");
        if (target === undefined || face === null || next.some(item => item.id === target.id)) continue;
        let host = hosts.get(bar);
        if (host === undefined) {
          host = document.createElement("div"); host.className = "imagine-window-controls-host";
          hosts.set(bar, host); face.appendChild(host); bar.setAttribute("data-imagine-floating-controls", "");
        }
        used.add(bar); next.push({...target, element: host});
      }
      for (const [bar, host] of hosts) if (!used.has(bar)) { host.remove(); bar.removeAttribute("data-imagine-floating-controls"); hosts.delete(bar); }
      setPortals(before => before.length === next.length && before.every((item, at) => item.element === next[at]!.element &&
        item.id === next[at]!.id && item.active === next[at]!.active && item.zoomed === next[at]!.zoomed) ? before : next);
    };
    const observer = new MutationObserver(() => { if (scheduled === undefined) scheduled = requestAnimationFrame(refresh); });
    observer.observe(root, {childList: true, subtree: true});
    refresh();
    return () => {
      observer.disconnect(); if (scheduled !== undefined) cancelAnimationFrame(scheduled);
      for (const [bar, host] of hosts) { host.remove(); bar.removeAttribute("data-imagine-floating-controls"); }
    };
  }, [signature]);
  return <Fragment><style>{WINDOW_CONTROLS_CSS}</style>{portals.map(target => createPortal(
    <WindowControls active={target.active} zoomed={target.zoomed} onIntent={operation => {
      const current = currentTargets().find(item => item.id === target.id);
      if (current !== undefined) intent(current.id, operation, current.geometry);
    }} />, target.element, target.id))}</Fragment>;
};
