import { useEffect, useEffectEvent, useLayoutEffect, useMemo, useRef, useState } from "react";
import { Axis, axisOf, isForward } from "@domicile-desktop/manganese-window-management/direction";
import type { Direction } from "@domicile-desktop/manganese-window-management/direction";
import type { Geometry } from "@domicile-desktop/manganese-window-management/placement";
import type { StageScreen } from "@domicile-desktop/manganese-window-management/screens/stage-screens";
import { pathTo } from "@domicile-desktop/manganese-window-management/tree/path";
import { activeIdOf, WindowAction, workspaceHolding } from "@domicile-desktop/manganese-window-management/window-state";
import type { WindowState } from "@domicile-desktop/manganese-window-management/window-state";
import type { Domicile } from "@domicile-desktop/sdk/desktop/desktop";
import { SystemErrorKind } from "@domicile-desktop/sdk/system";
import {
  cycleScrollSize, decodeScrollPreferences, emptyScrollPreferences, encodeScrollPreferences,
  nextScrollPreset, panScroll, pruneScrollPreferences, scrollingScreens, scrollSizeOf, setScrollSize,
} from "./ScrollLayout";
import type { ScrollPreferences } from "./ScrollLayout";

const EVERY_WORKSPACE = () => true;
type Options = {
  readonly domicile: Domicile;
  readonly state: WindowState;
  readonly screens: readonly StageScreen[];
  readonly enabled: boolean;
  readonly identity?: string;
  readonly layoutReady: boolean;
  readonly scrollWorkspace?: (name: string) => boolean;
  readonly onAction: (action: WindowAction) => void;
};

/** Source-only geometry and private persistence, scoped to the existing desktop. */
export function useScrollingLayout({ domicile, state, screens, enabled, identity, layoutReady,
  scrollWorkspace = EVERY_WORKSPACE, onAction }: Options) {
  const [saved, setSaved] = useState<{ scope?: string; ready: boolean; preferences: ScrollPreferences }>({ ready: false, preferences: emptyScrollPreferences() });
  const [error, setError] = useState<string>();
  const rejected = useRef(false);
  const current = useRef(saved.preferences);
  const writing = useRef(false);
  const pending = useRef<{ scope: string; text: string } | undefined>(undefined);
  const activeScope = useRef(identity); activeScope.current = identity;
  const signature = useRef("");
  const alive = useRef(true);
  useEffect(() => { alive.current = true; return () => { alive.current = false; }; }, []);
  useEffect(() => {
    if (!enabled || !layoutReady) return;
    if (saved.ready && saved.scope === identity) return;
    if (identity === undefined) {
      setSaved({ ready: true, preferences: emptyScrollPreferences() });
      setError("Scrolling layout recovery is unavailable");
      return;
    }
    let disposed = false;
    rejected.current = false;
    void domicile.files.readText(`.local/state/imagine/scrolling-${identity}.json`).then(result => result.match({
      Ok: text => decodeScrollPreferences(text, identity),
      Err: failure => { if (failure.kind !== SystemErrorKind.NotFound) throw Error("Scrolling layout could not be read"); return emptyScrollPreferences(); },
    })).then(preferences => {
      if (!disposed) { setSaved({ scope: identity, ready: true, preferences }); setError(undefined); }
    }).catch((failure: unknown) => {
      if (!disposed) {
        rejected.current = true;
        setSaved({ scope: identity, ready: true, preferences: emptyScrollPreferences() });
        setError("Saved scrolling layout was rejected; its file is kept");
        console.error("Imagine scrolling recovery", failure);
      }
    });
    return () => { disposed = true; };
  }, [domicile, enabled, identity, layoutReady, saved.scope, saved.ready]);
  const ready = !enabled || (layoutReady && saved.ready && saved.scope === identity);
  const projected = useMemo(() => enabled && ready
    ? scrollingScreens(screens, state, pruneScrollPreferences(saved.preferences, state), scrollWorkspace)
    : { screens, preferences: saved.preferences }, [enabled, ready, screens, state, saved.preferences, scrollWorkspace]);
  current.current = projected.preferences;
  useLayoutEffect(() => {
    if (ready && projected.preferences !== saved.preferences) setSaved(before => ({ ...before, preferences: projected.preferences }));
  }, [ready, projected.preferences, saved.preferences]);
  const reportSaveFailure = (failure: unknown) => {
    if (alive.current) setError("Scrolling layout could not be saved");
    console.error("Imagine scrolling save", failure);
  };
  const flush = useEffectEvent(async () => {
    if (!enabled || !ready || identity === undefined || rejected.current || domicile.session.locked !== false) return;
    pending.current = { scope: identity, text: encodeScrollPreferences(identity, current.current) };
    if (writing.current) return;
    writing.current = true;
    try {
      // If another key arrives during the write, save that newest geometry too.
      while (alive.current && pending.current !== undefined && domicile.session.locked === false) {
        const request = pending.current;
        pending.current = undefined;
        if (request.scope !== activeScope.current || request.text === signature.current) continue;
        const result = await domicile.files.write(`.local/state/imagine/scrolling-${request.scope}.json`, request.text, { atomic: true });
        result.match({ Ok: () => { signature.current = request.text; }, Err: () => { throw Error("Atomic scrolling save was refused"); } });
      }
    } finally { writing.current = false; }
  });
  useEffect(() => { void flush().catch(reportSaveFailure); }, [projected.preferences, identity, enabled, ready, domicile]);
  useEffect(() => domicile.session.on("lockchange", () => {
    if (domicile.session.locked === false) void flush().catch(reportSaveFailure);
  }), [domicile]);

  const change = useEffectEvent((update: (before: ScrollPreferences) => ScrollPreferences) => {
    setSaved(before => ({ ...before, preferences: update(before.preferences) }));
  });
  const command = useEffectEvent((args: readonly string[]): boolean => {
    if (!enabled || !ready || args[0] !== "size-preset") return false;
    if (args.length !== 3 || (args[1] !== "width" && args[1] !== "height") || (args[2] !== "next" && args[2] !== "prev")) {
      console.error("Usage: imagine size-preset width|height next|prev"); return true;
    }
    const id = activeIdOf(state);
    const workspace = id === undefined ? undefined : workspaceHolding(state, id);
    const screen = workspace === undefined ? undefined : screens.find(candidate => candidate.current === workspace.name);
    if (id === undefined || workspace === undefined || screen === undefined || workspace.fullscreen !== undefined) return true;
    const axis = args[1] === "width" ? Axis.Horizontal : Axis.Vertical;
    const backward = args[2] === "prev";
    const floating = workspace.floats.find(float => pathTo(float.root, id) !== undefined);
    if (floating !== undefined) {
      const extent = axis === Axis.Horizontal ? screen.geometry.workspace.width : screen.geometry.workspace.height;
      if (extent <= 0) return true;
      const fraction = nextScrollPreset((axis === Axis.Horizontal ? floating.width : floating.height) / extent, backward);
      const length = fraction * extent;
      onAction(WindowAction.WindowResized(id, axis === Axis.Horizontal
        ? { ...floating, width: length, x: Math.max(0, Math.min(floating.x, extent - length)) }
        : { ...floating, height: length, y: Math.max(0, Math.min(floating.y, extent - length)) }));
    } else if (scrollWorkspace(workspace.name)) change(before => cycleScrollSize(before, state, id, axis, backward,
      axis === Axis.Horizontal ? screen.geometry.workspace.width : screen.geometry.workspace.height));
    return true;
  });
  const stretch = useEffectEvent((id: string, edge: Direction, by: number, geometry: Geometry): boolean => {
    if (!enabled || !ready) return false;
    const workspace = state.workspaces.find(candidate => candidate.tiling.root !== undefined && pathTo(candidate.tiling.root, id) !== undefined);
    if (workspace === undefined || !scrollWorkspace(workspace.name)) return false;
    const axis = axisOf(edge);
    const extent = axis === Axis.Horizontal ? geometry.workspace.width : geometry.workspace.height;
    if (extent <= 0) return true;
    change(before => {
      const size = scrollSizeOf(before, state, id, axis);
      if (size === undefined) return before;
      const minimum = Math.max(1 / 64, Math.min(1, (axis === Axis.Horizontal ? 240 : 120) / extent));
      return setScrollSize(before, state, id, axis, Math.max(minimum, Math.min(4, size + by * (isForward(edge) ? 1 : -1) / extent)));
    });
    return true;
  });
  const pan = useEffectEvent((workspace: string, axis: Axis, delta: number): boolean => {
    if (!enabled || !ready || !scrollWorkspace(workspace)) return false;
    change(before => panScroll(before, state, workspace, axis, delta));
    return true;
  });
  return { screens: projected.screens, preferences: projected.preferences, ready, error, command, stretch, pan };
}
