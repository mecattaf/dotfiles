// Pure frame layout adapted from Manganese 67c29a9906905bd5e1679803232c2f510b3fed9e.
// Copyright 2026 Connor Prussin; MIT (LICENSE). Agency sets both gap and well margin to zero.
// Types and primitives come only from public package exports.
import type { Placement, PlacedTab } from "@domicile-desktop/manganese-window-management/placement";
import type { Rect } from "@domicile-desktop/manganese-window-management/rect";
import { barOf, surfaceOf, TITLE_BAR, tuckedUnderBar } from "@domicile-desktop/manganese-window-management/rect";
import type { NodeRef, Path } from "@domicile-desktop/manganese-window-management/tree/path";
import { nodeAt } from "@domicile-desktop/manganese-window-management/tree/path";
import type { WindowState } from "@domicile-desktop/manganese-window-management/window-state";

type Tiling = WindowState["workspaces"][number]["tiling"];
type LayoutNode = NonNullable<Tiling["root"]>;
type Container = Extract<LayoutNode, { children: readonly unknown[] }>;
type Frame = Omit<Placement, "bare" | "depth" | "frame">;
type StripPlace = NonNullable<Frame["strip"]>;
type TabLayout = NonNullable<Frame["tabbed"]>;
type Tab = Omit<PlacedTab, "depth">;
type Tiled = { frames: readonly Frame[]; tabs: readonly Tab[] };
// These discriminants are part of the pinned stock WindowState model.
const Layout = { SplitH: 0, SplitV: 1, Stacking: 2, Tabbed: 3 } as const;
const NodeKind = { Container: 0, Window: 1 } as const;
const WELL_MARGIN = 0;
const showsOneChild = (layout: number) => layout === Layout.Tabbed || layout === Layout.Stacking;
export const windowsIn = (node: LayoutNode): readonly string[] =>
  node.kind === NodeKind.Window ? [node.id] : node.children.flatMap(windowsIn);
const childIn = (node: Container) => {
  const child = node.children[node.focused];
  if (child === undefined) throw new Error("Agency layout: focused child is missing");
  return child;
};
const focusedWindowIn = (node: LayoutNode): string =>
  node.kind === NodeKind.Window ? node.id : focusedWindowIn(childIn(node));
const focusChainOf = (node: LayoutNode): Path =>
  node.kind === NodeKind.Window ? [] : [node.focused, ...focusChainOf(childIn(node))];
const focusPathOf = (node: LayoutNode, depth: number): Path => focusChainOf(node).slice(0, depth);


const NOTHING: Tiled = { frames: [], tabs: [] };

export const framesOf = (tiling: Tiling, area: Rect, gap: number): Tiled => {
  const { root } = tiling;
  return root === undefined
    ? NOTHING
    : placed(root, area, gap, focusPathOf(root, tiling.depth), false, 0);
};

export const areaOf = (
  root: LayoutNode,
  path: Path,
  area: Rect,
  gap: number,
): Rect => {
  const [index, ...rest] = path;
  if (index === undefined) {
    return area;
  } else if (root.kind === NodeKind.Window) {
    throw new Error(`layout tree: path ${path.join(".")} runs into a window`);
  } else {
    const child = root.children[index];
    if (child === undefined) {
      throw new Error(`layout tree: path ${path.join(".")} leaves the tree`);
    } else {
      return areaOf(child, rest, childArea(root, child, area, gap, index), gap);
    }
  }
};

export type FocusBox = {
  rect: Rect;

  selection: Rect | undefined;
  windows: readonly string[];
};

export const focusBoxOf = (
  tiling: Tiling,
  area: Rect,
  gap: number,
): FocusBox | undefined => {
  const { root } = tiling;
  if (root === undefined) {
    return undefined;
  } else {
    const focused = focusPathOf(root, tiling.depth);
    const selected = nodeAt(root, focused).kind === NodeKind.Container;
    const path = selected ? focused : tabGroupAround(root, focused);
    const rect = areaOf(root, path, area, gap);
    return {
      rect,
      selection: selected ? rect : undefined,
      windows: windowsIn(nodeAt(root, path)),
    };
  }
};

const placed = (
  node: LayoutNode,
  area: Rect,
  gap: number,
  pointed: Path | undefined,
  selected: boolean,
  wells: number,
): Tiled => {
  switch (node.kind) {
    case NodeKind.Window: {
      return {
        frames: [
          {
            bar: barOf(area),
            behind: undefined,
            id: node.id,
            selected,
            soleTab: false,
            strip: undefined,
            surface: surfaceOf(area),
            tabbed: undefined,
          },
        ],
        tabs: [],
      };
    }
    case NodeKind.Container: {

      const inside = selected || pointed?.length === 0;
      switch (node.layout) {
        case Layout.SplitH:
        case Layout.SplitV: {
          return joined(
            node.children.map((child, at) =>
              placed(
                child,
                sliceOf(node, area, gap, at),
                gap,
                within(pointed, at),
                inside,
                wells,
              ),
            ),
          );
        }
        case Layout.Stacking:
        case Layout.Tabbed: {
          return titled(node, node.layout, area, gap, pointed, inside, wells);
        }
      }
    }
  }
  throw new Error("Agency layout: unrecognised node or layout");
};

const childArea = (
  container: Container,
  child: LayoutNode,
  area: Rect,
  gap: number,
  at: number,
): Rect => {
  switch (container.layout) {
    case Layout.SplitH:
    case Layout.SplitV: {
      return sliceOf(container, area, gap, at);
    }
    case Layout.Stacking:
    case Layout.Tabbed: {
      return child.kind === NodeKind.Container
        ? insetOf(contentsOf(container, area))
        : contentsOf(container, area);
    }
  }
  throw new Error("Agency layout: unrecognised child layout");
};

const within = (pointed: Path | undefined, at: number): Path | undefined =>
  pointed === undefined || pointed[0] !== at ? undefined : pointed.slice(1);

const sliceOf = (
  container: Container,
  area: Rect,
  gap: number,
  at: number,
): Rect => {
  const gaps = gap * (container.children.length - 1);
  const shares = container.fractions.slice(0, at);
  const before = shares.reduce((sum, fraction) => sum + fraction, 0);
  const fraction = container.fractions[at];
  if (fraction === undefined) {
    throw new Error(`layout tree: no share for child ${at.toString()}`);
  } else if (container.layout === Layout.SplitV) {
    const { end, start } = edgesOf(
      area.y + gap * at,
      area.height - gaps,
      before,
      fraction,
    );
    return { ...area, height: end - start, y: start };
  } else {
    const { end, start } = edgesOf(
      area.x + gap * at,
      area.width - gaps,
      before,
      fraction,
    );
    return { ...area, width: end - start, x: start };
  }
};

const edgesOf = (
  origin: number,
  extent: number,
  before: number,
  fraction: number,
): { end: number; start: number } => ({
  end: Math.round(origin + extent * (before + fraction)),
  start: Math.round(origin + extent * before),
});

const titled = (
  container: Container,
  layout: TabLayout,
  area: Rect,
  gap: number,
  pointed: Path | undefined,
  selected: boolean,
  wells: number,
): Tiled => {
  const contents = contentsOf(container, area);
  return joined(
    container.children.map((child, at) => {
      const bar = titleOf(container, area, at);
      const showing = at === container.focused;
      const strip = stripPlaceOf(container, area, at, wells);
      switch (child.kind) {
        case NodeKind.Window: {

          const surface = tuckedUnderBar(contents);
          return {
            frames: [
              {
                bar,
                behind: showing ? undefined : surface,
                id: child.id,
                selected,
                soleTab: container.children.length === 1,
                strip,
                surface: showing ? surface : undefined,
                tabbed: layout,
              },
            ],
            tabs: [],
          };
        }
        case NodeKind.Container: {
          const tab = {
            active: showing,
            group: child.layout,
            id: focusedWindowIn(child),
            node: {
              id: focusedWindowIn(child),
              up: focusChainOf(child).length,
            },
            rect: bar,
            selected,
            strip,
            tabbed: layout,
            well: showing ? contents : undefined,
            windows: windowsIn(child),
          };
          const inside = showing
            ? placed(
                child,
                insetOf(contents),
                gap,
                within(pointed, at),
                selected,
                wells + 1,
              )
            : NOTHING;
          return {
            frames: inside.frames,
            tabs: [tab, ...inside.tabs],
          };
        }
      }
      throw new Error("Agency layout: unrecognised tab child");
    }),
  );
};

const TAB_WIDTH = 240;

const STRIP_END = 72;

const titleOf = (container: Container, area: Rect, at: number): Rect => {
  if (container.layout === Layout.Stacking) {
    return { ...barOf(area), y: area.y + TITLE_BAR * at };
  } else {
    const width = tabWidthOf(container, area);
    return { ...barOf(area), width, x: area.x + width * at };
  }
};

const tabWidthOf = (container: Container, area: Rect): number =>
  Math.min(TAB_WIDTH, (area.width - STRIP_END) / container.children.length);

const stripPlaceOf = (
  container: Container,
  area: Rect,
  at: number,
  wells: number,
): StripPlace => {
  const count = container.children.length;
  return {
    area,
    at,
    box: { ...area, height: TITLE_BAR * barsOf(container) },
    divided:
      at > 0 &&
      (container.layout === Layout.Stacking ||
        (at !== container.focused && at - 1 !== container.focused)),
    end: endOf(container, area),
    endDivided:
      container.layout !== Layout.Stacking && container.focused !== count - 1,
    group: {
      node: {
        id: focusedWindowIn(container),
        up: focusChainOf(container).length,
      },
      wells,
      windows: windowsIn(container),
    },
    nested: wells > 0,
    open: at === container.focused,
    tabs: count,
  };
};

const endOf = (container: Container, area: Rect): Rect | undefined => {
  if (container.layout === Layout.Stacking) {
    return undefined;
  } else {
    const tabs = tabWidthOf(container, area) * container.children.length;
    return { ...barOf(area), width: area.width - tabs, x: area.x + tabs };
  }
};

const contentsOf = (container: Container, area: Rect): Rect => {
  const bars = barsOf(container);
  return {
    ...area,
    height: Math.max(0, area.height - TITLE_BAR * bars),
    y: area.y + TITLE_BAR * bars,
  };
};

const insetOf = (well: Rect): Rect => ({
  height: Math.max(0, well.height - 2 * WELL_MARGIN),
  width: Math.max(0, well.width - 2 * WELL_MARGIN),
  x: well.x + WELL_MARGIN,
  y: well.y + WELL_MARGIN,
});

const barsOf = (container: Container): number =>
  container.layout === Layout.Stacking ? container.children.length : 1;

const tabGroupAround = (root: LayoutNode, path: Path): Path => {
  const parentPath = path.slice(0, -1);
  const parent = nodeAt(root, parentPath);
  return path.length > 0 &&
    parent.kind === NodeKind.Container &&
    showsOneChild(parent.layout)
    ? parentPath
    : path;
};

const joined = (placements: readonly Tiled[]): Tiled => ({
  frames: placements.flatMap(({ frames }) => frames),
  tabs: placements.flatMap(({ tabs }) => tabs),
});
