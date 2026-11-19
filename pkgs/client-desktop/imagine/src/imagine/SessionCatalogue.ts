import { WindowKind } from "@domicile-desktop/manganese-window-management/window";
import { workspaceHolding } from "@domicile-desktop/manganese-window-management/window-state";
import type { WindowState } from "@domicile-desktop/manganese-window-management/window-state";

export type CatalogueOptions = { readonly relay: string; readonly server: string; readonly terminalLauncher?: string };
export const catalogueConfig = (value?: CatalogueOptions): CatalogueOptions | undefined => {
  if (value === undefined) return undefined;
  if (!/^[\w-]{1,128}$/.test(value.server) || [value.relay, value.terminalLauncher].some((word) =>
    word !== undefined && (!word || /[\s\0?#]/u.test(word) || word.includes("://")))) throw Error("Invalid session catalogue configuration");
  return Object.freeze({ ...value });
};
export const ATTENTION_LABELS = { working: "Working", "needs-approval": "Needs approval", "needs-answer": "Needs answer",
  finished: "Finished", failed: "Failed", idle: "Idle" } as const;
export type AttentionStatus = keyof typeof ATTENTION_LABELS;
export type SessionRow = { sessionId: string; title: string; status: AttentionStatus; revision: number; attentionRevision: number;
  pendingApprovals: number; pendingQuestions: number; updatedAt: number };
export type TerminalRoute = { version: 1; server: string; epoch: string; session: string; terminal: string; windowClass: string };
export type TerminalEntry = { route: TerminalRoute; title: string };
export type Viewer = { sessionId: string; tag: string };
export type CatalogueState = { available: boolean; epoch?: string; seq: number; rows: Readonly<Record<string, SessionRow>>;
  seen: Readonly<Record<string, number>>; viewers: readonly Viewer[]; viewersAvailable: boolean; mainViewers: readonly string[]; terminalsAvailable: boolean; terminals: readonly TerminalEntry[] };
export const EMPTY_CATALOGUE: CatalogueState = { available: false, seq: -1, rows: {}, seen: {}, viewers: [], viewersAvailable: false, mainViewers: [], terminalsAvailable: false, terminals: [] };
const object = (value: unknown): Record<string, unknown> => {
  if (value === null || typeof value !== "object" || Array.isArray(value)) throw Error("Invalid catalogue frame");
  return value as Record<string, unknown>;
};
const identity = (value: unknown): string => {
  if (typeof value !== "string" || !/^[\w-]{1,128}$/.test(value)) throw Error("Invalid catalogue identity");
  return value;
};
const natural = (value: unknown): number => {
  if (!Number.isSafeInteger(value) || (value as number) < 0) throw Error("Invalid catalogue revision");
  return value as number;
};
const title = (value: unknown): string => {
  if (typeof value !== "string" || value.length > 65536) throw Error("Invalid catalogue title");
  return value.replace(/[\x00-\x1f\x7f]/g, " ").trim().slice(0, 512) || "Untitled chat";
};
const sessionRow = (value: unknown): SessionRow => {
  const row = object(value);
  if (typeof row.status !== "string" || !Object.hasOwn(ATTENTION_LABELS, row.status)) throw Error("Invalid attention status");
  return { sessionId: identity(row.sessionId), title: title(row.title), status: row.status as AttentionStatus,
    revision: natural(row.revision), attentionRevision: natural(row.attentionRevision),
    pendingApprovals: natural(row.pendingApprovals), pendingQuestions: natural(row.pendingQuestions), updatedAt: natural(row.updatedAt) };
};
export const terminalRoute = (value: unknown, server: string): TerminalRoute => {
  const row = object(value);
  if (row.version !== 1 || row.server !== server || typeof row.windowClass !== "string" || !/^dsh-terminal-[a-f0-9]{20}$/.test(row.windowClass)) throw Error("Invalid terminal route");
  return { version: 1, server, epoch: identity(row.epoch), session: identity(row.session), terminal: identity(row.terminal), windowClass: row.windowClass };
};
const bounded = (value: unknown): unknown[] => {
  if (!Array.isArray(value) || value.length > 4096) throw Error("Catalogue exceeds its limit");
  return value;
};

/** Only the Host folds agent state. This consumer orders and replaces metadata. */
export function receiveCatalogue(before: CatalogueState, value: unknown, server: string): CatalogueState {
  const frame = object(value);
  if (frame.type === "unavailable") return { ...before, available: false };
  if (frame.type === "viewers") return { ...before, viewersAvailable: true, mainViewers: bounded(frame.mainViewers ?? []).map(value => {
    if (typeof value !== "string" || !/^agencychat[a-f0-9]{32}$/.test(value)) throw Error("Invalid main viewer tag");
    return value;
  }), viewers: bounded(frame.viewers).map((value) => {
    const viewer = object(value);
    if (typeof viewer.tag !== "string" || !/^agencychat[a-f0-9]{32}$/.test(viewer.tag)) throw Error("Invalid viewer tag");
    return { sessionId: identity(viewer.sessionId), tag: viewer.tag };
  }) };
  if (frame.type === "terminals") return { ...before, terminalsAvailable: frame.available === true,
    terminals: frame.available === true ? bounded(frame.terminals).map((value) => {
      const terminal = object(value);
      return { route: terminalRoute(terminal.route, server), title: title(terminal.title) };
    }) : [] };
  if (frame.version !== 1) throw Error("Unknown catalogue protocol");
  const epoch = identity(frame.epoch), seq = natural(frame.seq);
  if (frame.type === "snapshot") {
    if (epoch === before.epoch && seq < before.seq) throw Error("Stale catalogue snapshot");
    const items = Object.entries(object(frame.sessions));
    if (items.length > 4096) throw Error("Catalogue exceeds its limit");
    const rows = Object.fromEntries(items.map(([id, value]) => {
      const row = sessionRow(value);
      if (row.sessionId !== id || row.revision > seq || row.attentionRevision > row.revision) throw Error("Mismatched session identity");
      return [id, row];
    }));
    // Every attachment is a baseline: old completions produce no fresh badge.
    return { ...before, available: true, epoch, seq, rows,
      seen: Object.fromEntries(Object.values(rows).map((row) => [row.sessionId, row.attentionRevision])) };
  }
  if (epoch !== before.epoch || !before.available || seq !== before.seq + 1) {
    if (epoch === before.epoch && seq <= before.seq) return before;
    throw Error("Catalogue needs a fresh snapshot");
  }
  if (frame.type === "upsert") {
    const row = sessionRow(frame.session);
    if (row.revision !== seq || row.attentionRevision > row.revision) throw Error("Invalid attention revision");
    return { ...before, seq, rows: { ...before.rows, [row.sessionId]: row } };
  }
  if (frame.type === "remove") {
    const id = identity(frame.sessionId), rows = { ...before.rows }, seen = { ...before.seen };
    delete rows[id]; delete seen[id];
    return { ...before, seq, rows, seen };
  }
  throw Error("Unknown catalogue event");
}
export const markSessionSeen = (state: CatalogueState, id: string): CatalogueState => !Object.hasOwn(state.rows, id) ? state :
  { ...state, seen: { ...state.seen, [id]: state.rows[id]!.attentionRevision } };
const priority: Record<AttentionStatus, number> = { "needs-approval": 0, "needs-answer": 0, working: 1, failed: 2, finished: 3, idle: 4 };
export function projectCatalogue(catalogue: CatalogueState, state: WindowState) {
  const native = state.windows.filter((window) => window.kind === WindowKind.App);
  const location = (id: string) => workspaceHolding(state, id)?.name;
  return Object.values(catalogue.rows).sort((a, b) => priority[a.status] - priority[b.status] || b.updatedAt - a.updatedAt || a.sessionId.localeCompare(b.sessionId)).map((row) => ({
    ...row, available: catalogue.available,
    unseen: catalogue.available && ["needs-approval", "needs-answer", "finished", "failed"].includes(row.status) &&
      row.attentionRevision > (Object.hasOwn(catalogue.seen, row.sessionId) ? catalogue.seen[row.sessionId]! : -1),
    viewers: catalogue.viewers.filter((viewer) => viewer.sessionId === row.sessionId).flatMap(({ tag }) =>
      native.filter((window) => window.desktopId.includes(tag)).map(({ id }) => ({ id, tag, workspace: location(id) }))),
    terminals: catalogue.terminals.filter(({ route }) => route.session === row.sessionId).map((terminal) => {
      const windows = native.filter((window) => window.desktopId === terminal.route.windowClass);
      const id = windows.length === 1 ? windows[0]!.id : undefined;
      return { ...terminal, id, workspace: id === undefined ? undefined : location(id) };
    }),
  }));
}
export type CatalogueRow = ReturnType<typeof projectCatalogue>[number];
