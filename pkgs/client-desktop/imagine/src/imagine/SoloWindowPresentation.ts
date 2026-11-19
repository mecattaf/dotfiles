import type { StageScreen } from "@domicile-desktop/manganese-window-management/screens/stage-screens";
import type { WindowState } from "@domicile-desktop/manganese-window-management/window-state";
import { windowsIn } from "./GaplessFrames";

type Node = NonNullable<WindowState["workspaces"][number]["tiling"]["root"]>;
const SCROLLING_WORKSPACE = () => false;
const visibleGroups = (node: Node): readonly (readonly string[])[] =>
  node.kind === 1 || node.layout === 2 || node.layout === 3
    ? [windowsIn(node)] : node.children.flatMap(visibleGroups);

/**
 * Scrolling neighbors count even when outside the viewport. Floating mode
 * counts a tab group or float as one visible group, like the old smart-border
 * rule: inactive tabs do not force a border around the only visible group.
 * Hidden scratchpad/background windows and native popups are outside these trees.
 */
export const soloWindowGroups = (state: WindowState,
  floatingWorkspace: (workspace: string) => boolean = SCROLLING_WORKSPACE,
): ReadonlyMap<string, readonly string[]> =>
  new Map(state.workspaces.flatMap(workspace => {
    const groups = floatingWorkspace(workspace.name)
      ? [...(workspace.tiling.root === undefined ? [] : visibleGroups(workspace.tiling.root)),
        ...workspace.floats.map(float => windowsIn(float.root))]
      : [...(workspace.tiling.root === undefined ? [] : windowsIn(workspace.tiling.root)).map(id => [id]),
        ...workspace.floats.flatMap(float => windowsIn(float.root).map(id => [id]))];
    return groups.length === 1 ? [[workspace.name, groups[0]!] as const] : [];
  }));

/** Remove only the solo workspace's focus marker; retain every window box. */
export const presentSoloWindows = (screens: readonly StageScreen[], state: WindowState,
  floatingWorkspace: (workspace: string) => boolean = SCROLLING_WORKSPACE,
): {
  readonly screens: readonly StageScreen[];
  readonly borderlessWindows: ReadonlySet<string>;
} => {
  const solo = soloWindowGroups(state, floatingWorkspace);
  const borderlessWindows = new Set<string>();
  let changed = false;
  const presented = screens.map(screen => {
    const group = solo.get(screen.current);
    if (group === undefined) return screen;
    for (const id of group) borderlessWindows.add(id);
    if (screen.screenful.focusBox === undefined) return screen;
    changed = true;
    return { ...screen, screenful: { ...screen.screenful, focusBox: undefined } };
  });
  return { screens: changed ? presented : screens, borderlessWindows };
};

// Encode host IDs as CSS strings, never interpolate titles or URLs.
const cssString = (value: string): string => `"${[...value].map(character =>
  /[A-Za-z0-9_-]/.test(character) ? character : `\\${character.codePointAt(0)!.toString(16)} `).join("")}"`;

/**
 * Keep the stock border width and resize strips: only its paint disappears.
 * This cannot reflow the terminal or change the native client's pixel bounds.
 * Scope includes a fading previous focus marker during a workspace transition.
 */
export const soloWindowCss = (windows: ReadonlySet<string>): string => [...windows].map(id => {
  const surface = id.startsWith("app:")
    ? `div:has(> app[app-id=${cssString(id.slice(4))}])`
    : id.startsWith("browser:")
      ? `section[aria-label="Browser"]:has(webview[window=${cssString(id.slice(8))}])`
      : undefined;
  if (surface === undefined) return "";
  const title = `[data-window=${cssString(id)}]`;
  const focus = `[data-focus-box~=${cssString(id)}]`;
  return `.agency-desktop ${surface},.agency-desktop ${title},.agency-desktop ${title}>div{border-color:transparent!important}`
    + `.agency-desktop ${focus}{outline-color:transparent!important;box-shadow:none!important}`;
}).join("\n");
