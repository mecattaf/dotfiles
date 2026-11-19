import { useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import type { Domicile } from "@domicile-desktop/sdk/desktop/desktop";
import { WindowAction } from "@domicile-desktop/manganese-window-management/window-state";
import type { WindowState } from "@domicile-desktop/manganese-window-management/window-state";
import { WindowKind } from "@domicile-desktop/manganese-window-management/window";
import { chatOrigin, chatLaunchTag, emptyChatWorkspace } from "./ChatWindow";
import type { ChatOrigin, ChatPlacement, ChatReservation } from "./ChatWindow";
import { runHelperRequest } from "./HelperRequest";
import { EMPTY_CATALOGUE, markSessionSeen, projectCatalogue, receiveCatalogue } from "./SessionCatalogue";
import type { CatalogueOptions, CatalogueRow, CatalogueState } from "./SessionCatalogue";

/** Stream frames across arbitrary UTF-8/chunk boundaries; no unbounded line buffer. */
export async function consumeCatalogue(stream: ReadableStream<Uint8Array>, receive: (value: unknown) => void, signal?: AbortSignal) {
  const reader = stream.getReader(), decoder = new TextDecoder("utf-8", { fatal: true });
  let buffer = "";
  const cancel = () => { void reader.cancel().catch(() => {}); };
  signal?.addEventListener("abort", cancel, { once: true });
  if (signal?.aborted) cancel();
  try {
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      let end: number;
      while ((end = buffer.indexOf("\n")) >= 0) {
        const line = buffer.slice(0, end); buffer = buffer.slice(end + 1);
        if (line.length > 8 * 1024 * 1024) throw Error("Metadata frame exceeds its limit");
        if (line.trim()) receive(JSON.parse(line));
      }
      if (buffer.length > 8 * 1024 * 1024) throw Error("Metadata frame exceeds its limit");
    }
    if ((buffer + decoder.decode()).trim()) throw Error("Incomplete metadata frame");
  } finally { signal?.removeEventListener("abort", cancel); reader.releaseLock(); }
}

/** One relay per shell mount; stdin EOF and termination dispose its SSH reader. */
export function watchCatalogue(domicile: Domicile, config: CatalogueOptions, receive: (value: unknown) => void) {
  const spawn = async () => (await domicile.processes.spawn([config.relay, "--watch"], { stdin: true }))
    .match({ Ok: (value) => value, Err: () => undefined });
  let stopped = false, process: Awaited<ReturnType<typeof spawn>>;
  let timer: ReturnType<typeof setTimeout> | undefined;
  const unavailable = () => { if (!stopped) { receive({ type: "unavailable" }); receive({ type: "terminals", available: false }); } };
  const start = async () => {
    let current: typeof process;
    try {
      current = await spawn();
      if (current === undefined) throw Error("Metadata relay unavailable");
      if (stopped) { current.closeStdin(); current.kill(); return; }
      process = current;
      // Drain bounded diagnostic chunks without reflecting private streams into UI/logs.
      const readers = new AbortController();
      let ended = false;
      const exited = current.exited.then(value => { ended = true; return value; });
      const errors = consumeCatalogueErrors(current.stderr, readers.signal);
      const output = consumeCatalogue(current.stdout, (frame) => { if (!stopped) receive(frame); }, readers.signal);
      try { await Promise.race([output, exited]); }
      finally { readers.abort(); current.closeStdin(); if (!ended) current.kill(); unavailable(); await exited; await Promise.allSettled([output, errors]); }
    } catch { /* The last good rows remain explicitly unavailable. */ }
    finally {
      current?.closeStdin();
      if (process === current) process = undefined;
      unavailable();
      if (!stopped) timer = setTimeout(() => { void start(); }, 2000);
    }
  };
  void start();
  return () => { stopped = true; clearTimeout(timer); process?.closeStdin(); process?.kill(); };
}
const consumeCatalogueErrors = async (stream: ReadableStream<Uint8Array>, signal: AbortSignal) => {
  const reader = stream.getReader();
  const cancel = () => { void reader.cancel().catch(() => {}); };
  signal.addEventListener("abort", cancel, { once: true });
  if (signal.aborted) cancel();
  try { while (!(await reader.read()).done) { /* Never retain or print diagnostics. */ } }
  finally { signal.removeEventListener("abort", cancel); reader.releaseLock(); }
};


type PendingView = { session: string; identity: string; workspace: string; origin: ChatOrigin; allowOccupied: boolean; reveal: boolean; accepted: boolean };
export function useSessionCatalogue({ domicile, config, chatLauncher, state, blocked, act, reserve, place }: {
  domicile: Domicile; config?: CatalogueOptions; chatLauncher?: string; state: WindowState; blocked: boolean;
  act: (action: WindowAction) => void; reserve: (identity: string, placement: ChatReservation | undefined) => void;
  place: (placement: ChatPlacement) => void;
}) {
  const [catalogue, setCatalogue] = useState(EMPTY_CATALOGUE);
  const [busy, setBusy] = useState<string>();
  const [error, setError] = useState<string>();
  const model = useRef(EMPTY_CATALOGUE);
  const latest = useRef({ state, blocked });
  const inFlight = useRef(false), alive = useRef(true), pending = useRef<PendingView | undefined>(undefined);
  const deadline = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  useLayoutEffect(() => { latest.current = { state, blocked }; }, [state, blocked]);
  useEffect(() => { alive.current = true; return () => { alive.current = false; clearTimeout(deadline.current);
    if (pending.current) reserve(pending.current.identity, undefined); }; }, [reserve]);
  useEffect(() => {
    if (config === undefined) return;
    model.current = EMPTY_CATALOGUE; setCatalogue(model.current);
    return watchCatalogue(domicile, config, (frame) => {
      model.current = receiveCatalogue(model.current, frame, config.server); setCatalogue(model.current);
    });
  }, [domicile, config]);
  const seen = (id: string) => { model.current = markSessionSeen(model.current, id); setCatalogue(model.current); };
  const stillHere = (origin: ChatOrigin) => {
    const current = chatOrigin(latest.current.state);
    return !latest.current.blocked && current?.screen === origin.screen && current.workspace === origin.workspace;
  };
  useEffect(() => {
    const waiting = pending.current;
    if (waiting === undefined) return;
    waiting.reveal &&= stillHere(waiting.origin);
    if (!waiting.reveal) reserve(waiting.identity, { chatPlacement: true, workspace: waiting.workspace, origin: waiting.origin, reveal: false, allowOccupied: waiting.allowOccupied });
    if (!waiting.accepted) return;
    const matches = state.windows.filter((window) => window.kind === WindowKind.App && window.desktopId.includes(waiting.identity));
    if (matches.length === 1) {
      reserve(waiting.identity, undefined);
      place({ chatPlacement: true, id: matches[0]!.id, workspace: waiting.workspace, origin: waiting.origin, reveal: waiting.reveal, allowOccupied: waiting.allowOccupied });
      clearTimeout(deadline.current); pending.current = undefined; setBusy(undefined); seen(waiting.session);
    } else if (matches.length > 1) {
      reserve(waiting.identity, undefined); clearTimeout(deadline.current); pending.current = undefined;
      setBusy(undefined); setError("More than one viewer matched. No window was moved.");
    }
  }, [state, blocked, place, reserve, catalogue]);
  const focus = (id: string, session: string) => {
    if (latest.current.blocked) return;
    act(WindowAction.WindowSelected(id)); seen(session); setError(undefined);
  };
  const open = async (row: CatalogueRow | undefined, terminal?: CatalogueRow["terminals"][number]) => {
    const session = row?.sessionId ?? "$web";
    const main = row === undefined ? state.windows.filter(w => w.kind === WindowKind.App && catalogue.mainViewers.some(tag => w.desktopId.includes(tag))) : [];
    if (main.length > 1) { setError("More than one DSH web window matched."); return; }
    const id = row === undefined ? main[0]?.id : terminal ? terminal.id : row.viewers[0]?.id;
    if (id !== undefined) { focus(id, session); return; }
    if (config === undefined || blocked || inFlight.current || busy || (row !== undefined && !row.available)) return;
    const launcher = terminal ? config.terminalLauncher : chatLauncher;
    if (!launcher) return;
    const origin = chatOrigin(state), workspace = row === undefined ? origin?.workspace : terminal ? row.viewers[0]?.workspace ?? emptyChatWorkspace(state) : emptyChatWorkspace(state);
    if (origin === undefined || workspace === undefined) { setError("No workspace is available for this viewer."); return; }
    const viewerId = crypto.randomUUID(), identity = terminal?.route.windowClass ?? chatLaunchTag(viewerId);
    const request: PendingView = { session, identity, workspace, origin, allowOccupied: row === undefined || (terminal !== undefined && row.viewers.length > 0), reveal: true, accepted: false };
    pending.current = request;
    reserve(identity, { chatPlacement: true, workspace, origin, reveal: true, allowOccupied: request.allowOccupied });
    inFlight.current = true; setBusy(session); setError(undefined);
    try {
      const receipt = await runHelperRequest(domicile, terminal ? [launcher] : [launcher, row === undefined ? "--main" : "--session"], terminal ? terminal.route : row === undefined ? { viewerId } : { sessionId: row.sessionId, viewerId });
      const tag = terminal ? receipt.windowClass : receipt.tag;
      if ((row !== undefined && (terminal ? receipt.session : receipt.sessionId) !== row.sessionId) || (terminal ? tag !== terminal.route.windowClass : !/^agencychat[0-9a-f]{32}$/.test(tag))) throw Error("Viewer identity mismatch");
      if (!alive.current) return;
      request.accepted = true; request.reveal &&= stillHere(origin);
      if (tag !== identity) {
        reserve(identity, undefined);
        const existing = latest.current.state.windows.filter((window) => window.kind === WindowKind.App && window.desktopId.includes(tag));
        if (existing.length === 1) { if (request.reveal) focus(existing[0]!.id, session); pending.current = undefined; setBusy(undefined); return; }
        request.identity = tag;
        reserve(tag, { chatPlacement: true, workspace, origin, reveal: request.reveal, allowOccupied: request.allowOccupied });
      }
      if (pending.current === request) deadline.current = setTimeout(() => {
        if (pending.current !== request) return;
        reserve(request.identity, undefined); pending.current = undefined;
        if (alive.current) { setBusy(undefined); setError("The viewer did not report its native window."); }
      }, 30000);
      // Triggers the appearance check if the window arrived before its receipt.
      setCatalogue((value) => ({ ...value }));
    } catch {
      reserve(request.identity, undefined); if (pending.current === request) pending.current = undefined;
      if (alive.current) { setBusy(undefined); setError("The viewer could not open. Your chat and terminal are kept."); }
    } finally { inFlight.current = false; }
  };
  return { catalogue, rows: useMemo(() => projectCatalogue(catalogue, state), [catalogue, state]), busy, error, open, openWeb: chatLauncher === undefined ? undefined : () => open(undefined) };
}
