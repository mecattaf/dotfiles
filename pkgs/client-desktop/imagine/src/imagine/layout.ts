// Agency layout policy on the public stock StageScreen/placement contract.
import type { Geometry, Placement, Screenful } from "@domicile-desktop/manganese-window-management/placement";
import { spanning } from "@domicile-desktop/manganese-window-management/rect";
import type { Rect } from "@domicile-desktop/manganese-window-management/rect";
import type { StageScreen } from "@domicile-desktop/manganese-window-management/screens/stage-screens";
import { nodeAt, pathToRef } from "@domicile-desktop/manganese-window-management/tree/path";
import type { WindowState } from "@domicile-desktop/manganese-window-management/window-state";
import { focusBoxOf, framesOf, windowsIn } from "./GaplessFrames";

type Workspace = WindowState["workspaces"][number];
type Frame = ReturnType<typeof framesOf>["frames"][number];

const placed = (frame: Frame, depth: number, bare?: Rect): Placement => {
  const surface = bare ?? frame.surface;
  return { ...frame, surface, depth, bare: bare !== undefined,
    frame: bare ?? (surface === undefined ? frame.bar : spanning(frame.bar, surface)) };
};

/** Zero outer margins, zero split gaps, and the stock rounded window frame. */
export const agencyPlacement = (workspace: Workspace, geometry: Geometry, below = 0): Screenful => {
  const tiled = framesOf(workspace.tiling, geometry.workspace, 0);
  const floating = workspace.floats.map((float, index) => ({
    float,
    box: { x: float.x + geometry.screen.x, y: float.y + geometry.screen.y,
      width: float.width, height: float.height },
    depth: 2 + 2 * (below + index),
  }));
  const floats = floating.map((item) => ({ ...item,
    laid: framesOf(item.float, item.box, 0),
  }));
  const full = workspace.fullscreen;
  const tree = full === undefined ? undefined : [workspace.tiling, ...workspace.floats]
    .find(({ root }) => root !== undefined && windowsIn(root).includes(full.id));
  const path = full === undefined || tree?.root === undefined ? undefined : pathToRef(tree.root, full);
  const fullNode = path === undefined || tree?.root === undefined ? undefined : nodeAt(tree.root, path);
  const fullBox = full?.global ? geometry.desktop : geometry.screen;
  const fullscreen = fullNode === undefined ? { frames: [], tabs: [] }
    : framesOf({ root: fullNode, depth: Math.max(0, (tree?.depth ?? 0) - (path?.length ?? 0)) }, fullBox, 0);
  const covered = new Set(fullscreen.frames.map(({ id }) => id));
  const normal = [
    ...tiled.frames.map((frame) => placed(frame, 0)),
    ...floats.flatMap(({ box, depth, float, laid }) => laid.frames.map((frame) =>
      placed(frame, depth, float.bare && float.root.kind === 1 ? box : undefined))),
  ];
  const focusFloat = workspace.floatFocus === undefined ? undefined
    : floats.find(({ float }) => windowsIn(float.root).includes(workspace.floatFocus!));
  const focus = full !== undefined ? undefined
    : focusFloat === undefined ? focusBoxOf(workspace.tiling, geometry.workspace, 0)
      : focusFloat.float.scratchpad ? undefined : focusBoxOf(focusFloat.float, focusFloat.box, 0);
  return {
    focusBox: focus === undefined ? undefined : { ...focus, depth: focusFloat?.depth ?? 0 },
    placements: [...normal.filter(({ id }) => !covered.has(id)),
      ...fullscreen.frames.map((frame) => placed(frame, 2000, full?.bare ? fullBox : undefined))],
    tabs: [
      ...tiled.tabs.map((tab) => ({ ...tab, depth: 0 })),
      ...floats.flatMap(({ depth, laid }) => laid.tabs.map((tab) => ({ ...tab, depth }))),
    ].filter(({ strip }) => strip.group.windows.some((id) => !covered.has(id)))
      .concat(fullscreen.tabs.map((tab) => ({ ...tab, depth: 2000 }))),
  };
};

/** Keep real output geometry for fullscreen; reserve the rail only in tiling. */
export const agencyScreens = (base: readonly StageScreen[], state: WindowState,
  railOn: string | undefined, railWidth: number): readonly StageScreen[] => base.map((screen, index) => {
  const workspace = state.workspaces.find(({ name }) => name === screen.current);
  if (workspace === undefined) throw new Error(`Agency: missing workspace ${screen.current}`);
  const reserve = screen.geometry.name === railOn ? Math.min(railWidth, screen.geometry.screen.width) : 0;
  const geometry: Geometry = { ...screen.geometry, workspace: {
    ...screen.geometry.screen, x: screen.geometry.screen.x + reserve,
    width: Math.max(0, screen.geometry.screen.width - reserve),
  } };
  const top = screen.geometry.name === state.focused;
  const below = base.reduce((count, other, at) => count + (at !== index &&
    other.geometry.name !== state.focused && (top || at < index) ? other.floats.length : 0), 0);
  return { ...screen, geometry, screenful: agencyPlacement(workspace, geometry, below) };
});
