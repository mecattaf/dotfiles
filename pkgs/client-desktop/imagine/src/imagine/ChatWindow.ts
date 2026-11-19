import { placeAgentWindow } from "./AgentWindows";
import { activeIdOf, WindowAction, workspaceHolding } from "@domicile-desktop/manganese-window-management/window-state";
import type { WindowState } from "@domicile-desktop/manganese-window-management/window-state";

export type ChatWindowOptions = { readonly launcher: string; readonly bindAltEnter?: boolean };
export const chatWindowConfig = (value: ChatWindowOptions | undefined): ChatWindowOptions | undefined => {
  if (value === undefined) return undefined;
  if (!value.launcher || /[\s\0?#]/u.test(value.launcher) || value.launcher.includes("://")) {
    throw Error("Chat windows require one reviewed executable without arguments");
  }
  return Object.freeze({ launcher: value.launcher, bindAltEnter: value.bindAltEnter === true });
};

export type ChatOrigin = { readonly screen: string; readonly workspace: string };
export const chatOrigin = (state: WindowState): ChatOrigin | undefined => {
  const screen = state.screens.find(({ name }) => name === state.focused);
  return screen === undefined ? undefined : { screen: screen.name, workspace: screen.current };
};

/** Use an existing empty, unshown slot; never replace the current workspace. */
export const emptyChatWorkspace = (state: WindowState): string | undefined => {
  const shown = new Set(state.screens.map(({ current }) => current));
  return state.workspaces.find(({ name, tiling, floats }) =>
    name !== "10" && !shown.has(name) && tiling.root === undefined && floats.length === 0)?.name;
};

export const chatLaunchTag = (requestId: string): string => "agencychat" + requestId.replaceAll("-", "");
export type ChatPlacement = {
  readonly chatPlacement: true;
  readonly agent?: boolean;
  readonly id: string;
  readonly workspace: string;
  readonly origin: ChatOrigin;
  readonly reveal: boolean;
  /** A user-selected existing terminal may join its chat's workspace. */
  readonly allowOccupied?: boolean;
};
export type ChatReservation = Omit<ChatPlacement, "id">;
export type ChatNativeBatch = {
  readonly chatNativeBatch: true;
  readonly actions: readonly WindowAction[];
  readonly placements: readonly ChatPlacement[];
};

/** Announce and place before React can render a frame on the old workspace. */
export const reduceChatNativeBatch = (before: WindowState, batch: ChatNativeBatch,
  reduce: (state: WindowState, action: WindowAction) => WindowState): WindowState => {
  let next = batch.actions.reduce(reduce, before);
  for (const placement of batch.placements) next = placement.agent === true
    ? placeAgentWindow(before, next, placement, reduce) : placeChatWindow(next, placement, reduce, before);
  return next;
};

/** One atomic transaction through the real reducer; no second window model. */
export const placeChatWindow = (state: WindowState, placement: ChatPlacement,
  reduce: (state: WindowState, action: WindowAction) => WindowState, original = state): WindowState => {
  if (!state.windows.some(({ id }) => id === placement.id)) return state;
  const current = chatOrigin(original);
  const active = activeIdOf(original);
  const reveal = placement.reveal && current?.screen === placement.origin.screen &&
    current.workspace === placement.origin.workspace;
  const target = state.workspaces.find(({ name }) => name === placement.workspace);
  if (target === undefined) return state;
  // An occupied target is a newer user intent. Leave the new viewer visible
  // where it appeared rather than moving somebody else's windows.
  const holding = workspaceHolding(state, placement.id);
  if (holding?.name === placement.workspace) return state;
  if (!placement.allowOccupied && (target.tiling.root !== undefined || target.floats.length > 0)) return state;
  let next = reduce(state, WindowAction.WindowSelected(placement.id));
  next = reduce(next, WindowAction.WindowSentToWorkspace(placement.workspace));
  if (reveal) return reduce(next, WindowAction.WorkspaceSelected(placement.workspace));
  if (current !== undefined) next = reduce(next, WindowAction.WorkspaceSelected(current.workspace));
  if (active !== undefined && active !== placement.id && next.windows.some(({ id }) => id === active)) {
    next = reduce(next, WindowAction.WindowSelected(active));
  }
  return next;
};
