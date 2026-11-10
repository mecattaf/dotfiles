// Agency's window policy, composed around the public stock Manganese reducer.
// Baseline: cprussin/domicile 67c29a9906905bd5e1679803232c2f510b3fed9e.
// No engine changes or live commands: every transition here is pure.
import { Axis } from "@domicile-desktop/manganese-window-management/direction";
import {
  activeIdOf,
  NO_WINDOWS,
  reduceWindows,
  WindowAction,
  WindowActionKind,
  WORKSPACES,
  workspaceHolding,
} from "@domicile-desktop/manganese-window-management/window-state";
import type { WindowState } from "@domicile-desktop/manganese-window-management/window-state";

export type AgencyPolicy = {
  /** Prefer these physical display identities; otherwise use their geometry. */
  readonly upperDisplay?: string;
  readonly lowerDisplay?: string;
  /** Per-slot display preferences; disconnected displays fall back upstairs. */
  readonly workspaceDisplays?: Readonly<Record<string, string>>;
  readonly defaultSplitAxis?: Axis;
};
export const DEFAULT_AGENCY_POLICY: AgencyPolicy = {};

type Workspace = WindowState["workspaces"][number];
type Node = NonNullable<Workspace["tiling"]["root"]>;

/**
 * Reserve empty slots as well as populated ones. The client can move selected
 * slots to an external display; unplugging it returns them upstairs.
 */
export const applyWorkspaceHomes = (
  state: WindowState,
  policy: AgencyPolicy = DEFAULT_AGENCY_POLICY,
  focusedWorkspace?: string,
): WindowState => {
  const ordered = [...state.screens].sort((a, b) =>
    a.box.y - b.box.y || a.box.x - b.box.x || a.name.localeCompare(b.name),
  );
  const upper = ordered.find(({ name }) => name === policy.upperDisplay) ?? ordered[0];
  if (upper === undefined) return state;
  const lower = policy.lowerDisplay === undefined
    ? ordered.find(({ name }) => name !== upper.name) ?? upper
    : ordered.find(({ name }) => name === policy.lowerDisplay) ?? upper;
  const homes = Object.fromEntries(WORKSPACES.map((name) => [
    name, ordered.find((screen) => screen.name === policy.workspaceDisplays?.[name])?.name
      ?? (name === "10" ? lower.name : upper.name),
  ]));
  const managed = new Set(Object.values(homes));
  // Unassigned extra monitors keep their currently shown workspace.
  for (const screen of state.screens) {
    if (!managed.has(screen.name)) {
      homes[screen.current] = screen.name;
    }
  }
  const screens = state.screens.map((screen) => {
    const current = focusedWorkspace !== undefined && homes[focusedWorkspace] === screen.name
      ? focusedWorkspace
      : homes[screen.current] === screen.name ? screen.current
      : WORKSPACES.find((name) => homes[name] === screen.name) ?? screen.current;
    return current === screen.current ? screen : { ...screen, current };
  });
  const wasCurrent = focusedWorkspace ?? state.screens.find(({ name }) => name === state.focused)?.current;
  const focused = wasCurrent !== undefined && homes[wasCurrent] !== state.focused
    ? screens.find(({ current }) => current === wasCurrent)?.name ?? state.focused
    : state.focused;
  return focused === state.focused
    && screens.every((screen, at) => screen === state.screens[at])
    && WORKSPACES.every((name) => homes[name] === state.homes[name])
    ? state : { ...state, homes, screens, focused };
};

export const initialAgencyState = (
  policy: AgencyPolicy = DEFAULT_AGENCY_POLICY,
): WindowState => applyWorkspaceHomes(NO_WINDOWS, policy);

const contains = (node: Node | undefined, id: string): boolean =>
  node !== undefined && ("id" in node
    ? node.id === id : node.children.some((child) => contains(child, id)));

/** Wrap every upstream transition so empty workspace reservations survive it. */
const stock = (state: WindowState, action: WindowAction, policy: AgencyPolicy): WindowState =>
  applyWorkspaceHomes(reduceWindows(applyWorkspaceHomes(state, policy), action), policy,
    action.kind === WindowActionKind.ScreensDescribed
      ? state.screens.find(({ name }) => name === state.focused)?.current : undefined);

/**
 * Separate new normal windows using the exported layout actions. Work in reverse
 * insertion order so one browser report containing a,b,c yields a|b|c. Existing
 * tab groups stay intentional; dialogs, floats, popups and background windows
 * never enter this path. Restore the stock transition's actual active window.
 */
const splitNewWindows = (
  before: WindowState,
  after: WindowState,
  policy: AgencyPolicy,
): WindowState => {
  const known = new Set(before.windows.map(({ id }) => id));
  const added = after.windows.filter(({ id }) => !known.has(id));
  if (added.length === 0) return after;
  const active = activeIdOf(after);
  let next = after;
  for (const { id } of added.toReversed()) {
    const workspace = workspaceHolding(next, id);
    if (workspace === undefined || !contains(workspace.tiling.root, id)) continue;
    next = stock(next, WindowAction.WindowSelected(id), policy);
    next = stock(next, WindowAction.ContainerSplit(policy.defaultSplitAxis ?? Axis.Horizontal), policy);
  }
  return active === undefined || activeIdOf(next) === active
    ? next : stock(next, WindowAction.WindowSelected(active), policy);
};

export const createAgencyReducer = (policy: AgencyPolicy = DEFAULT_AGENCY_POLICY) =>
  (before: WindowState, action: WindowAction): WindowState => {
    const state = applyWorkspaceHomes(before, policy);
    // Repeating a numbered chord always selects that slot. Upstream's implicit
    // back-and-forth could otherwise jump from Meta+1 to the downstairs slot.
    if (action.kind === WindowActionKind.WorkspaceSelected) {
      const shown = state.screens.find(({ current }) => current === action.name);
      if (shown !== undefined) {
        return shown.name === state.focused ? state : { ...state, focused: shown.name };
      }
    }
    return splitNewWindows(state, stock(state, action, policy), policy);
  };

export const agencyReducer = createAgencyReducer();
