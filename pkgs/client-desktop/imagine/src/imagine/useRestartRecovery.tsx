import { useEffect, useLayoutEffect, useRef, useState } from "react";
import type { Domicile } from "@domicile-desktop/sdk/desktop/desktop";
import { SystemErrorKind } from "@domicile-desktop/sdk/system";
import { WindowKind } from "@domicile-desktop/manganese-window-management/window";
import { chatOrigin, chatLaunchTag } from "./ChatWindow";
import type { ChatOrigin, ChatReservation } from "./ChatWindow";
import type { CatalogueState } from "./SessionCatalogue";
import { captureRecovery, decodeRecovery, rebindRecovery } from "./RestartRecovery";
import type { RecoveryBinding, RecoveryCheckpoint } from "./RestartRecovery";
import { runHelperRequest } from "./HelperRequest";
import type { Windows } from "./useAgencyWindows";

const FILE = ".local/state/imagine/chat-layout.json";

/** A fresh desktop offers recovery before it can overwrite the previous layout.
 * Only a local user click reopens viewers; provider sessions are never started. */
export function useRestartRecovery({ domicile, enabled, windows, catalogue, server, chatLauncher, terminalLauncher, blocked }: {
  domicile: Domicile; enabled: boolean; windows: Windows; catalogue: CatalogueState; server?: string;
  chatLauncher?: string; terminalLauncher?: string; blocked: boolean;
}) {
  const [checkpoint, setCheckpoint] = useState<RecoveryCheckpoint>();
  const [phase, setPhase] = useState<"loading" | "watching" | "offered" | "restoring" | "saving" | "failed">("loading");
  const [error, setError] = useState<string>();
  const [message, setMessage] = useState<string>();
  const latest = useRef({ windows, catalogue, blocked });
  const savedCheckpoint = useRef(checkpoint); savedCheckpoint.current = checkpoint;
  const alive = useRef(true), running = useRef(false), generation = useRef(0);
  const writing = useRef<Promise<unknown> | undefined>(undefined);
  const claims = useRef(new Set<string>());
  const restoreOrigin = useRef<ChatOrigin | undefined>(undefined), restoreReveal = useRef(true);
  useLayoutEffect(() => {
    latest.current = { windows, catalogue, blocked };
    const origin = restoreOrigin.current, current = chatOrigin(windows);
    if (running.current && origin) restoreReveal.current &&= !blocked && current?.screen === origin.screen && current.workspace === origin.workspace;
  });
  useEffect(() => {
    alive.current = true;
    return () => { alive.current = false; generation.current++;
      for (const tag of claims.current) windows.reserveChat(tag, undefined); claims.current.clear(); };
  }, [windows.reserveChat]);
  useEffect(() => {
    if (!enabled || !windows.layoutIdentity) return;
    let disposed = false;
    void domicile.files.readText(FILE).then(result => result.match({
      Ok: text => decodeRecovery(text),
      Err: error => { if (error.kind !== SystemErrorKind.NotFound) throw Error("Recovery file unavailable"); return undefined; },
    })).then(saved => {
      if (disposed) return;
      setCheckpoint(saved);
      setPhase(saved !== undefined && (saved.pinned === true || saved.incarnation !== windows.layoutIdentity) && saved.slots.length > 0 ? "offered" : "watching");
    }).catch(() => { if (!disposed) { setPhase("failed"); setError("Saved chat layout could not be read. It has been kept."); } });
    return () => { disposed = true; };
  }, [enabled, domicile, windows.layoutIdentity]);
  useEffect(() => {
    if (!enabled || phase !== "watching" || !windows.layoutIdentity || !server) return;
    let disposed = false, signature = "", candidate = "", stableAt = 0;
    const save = async () => {
      const current = latest.current;
      if (disposed || writing.current || current.blocked || !current.windows.layoutReady || !current.catalogue.available || !current.catalogue.viewersAvailable || domicile.session.locked !== false) return;
      if (savedCheckpoint.current?.slots.some(s => s.route.kind === "terminal") && !current.catalogue.terminalsAvailable) return;
      const saved = captureRecovery(current.windows, current.catalogue, server, current.windows.layoutIdentity!);
      const layout = JSON.stringify({ ...saved, savedAt: 0 });
      if (layout === signature) return;
      if (layout !== candidate) { candidate = layout; stableAt = Date.now(); return; }
      if (Date.now() - stableAt < 3000 || (saved.slots.length === 0 && (savedCheckpoint.current?.slots.length ?? 0) > 0)) return;
      const operation = domicile.files.write(FILE, JSON.stringify(saved), { atomic: true });
      writing.current = operation;
      try {
        const result = await operation;
        result.match({ Ok: () => { signature = layout; if (!disposed) setCheckpoint(saved); }, Err: () => { if (!disposed) setError("Chat layout could not be saved"); } });
      } finally { if (writing.current === operation) writing.current = undefined; }
    };
    const attempt = () => { void save().catch(() => { if (!disposed) setError("Chat layout could not be saved"); }); };
    const timer = setInterval(attempt, 1000); attempt();
    return () => { disposed = true; clearInterval(timer); };
  }, [enabled, phase, domicile, windows.layoutIdentity, server]);
  const restore = async () => {
    if (!checkpoint || running.current || blocked || !catalogue.available || !server) return;
    const origin = chatOrigin(windows);
    if (!origin) return;
    running.current = true; setPhase("restoring"); setError(undefined); setMessage(undefined);
    const run = ++generation.current, bindings: RecoveryBinding[] = [];
    let skipped = checkpoint.omitted;
    restoreOrigin.current = origin; restoreReveal.current = true;
    const stopAt = Date.now() + 120000;
    const valid = () => alive.current && generation.current === run;
    const here = () => {
      const current = chatOrigin(latest.current.windows);
      restoreReveal.current &&= !latest.current.blocked && current?.screen === origin.screen && current.workspace === origin.workspace;
      return restoreReveal.current;
    };
    try {
      for (const slot of checkpoint.slots) {
        if (!valid() || latest.current.blocked || Date.now() >= stopAt) { skipped++; continue; }
        here();
        const model = latest.current.catalogue, route = slot.route;
        if (!model.available || route.server !== server || (route.kind !== "web" && !model.rows[route.session])) { skipped++; continue; }
        const terminal = route.kind === "terminal" ? model.terminals.filter(t => t.route.server === server && t.route.session === route.session && t.route.terminal === route.terminal) : [];
        const launcher = route.kind === "terminal" ? terminalLauncher : chatLauncher;
        if (!launcher || (route.kind === "terminal" && terminal.length !== 1)) { skipped++; continue; }
        let tag = route.kind === "terminal" ? terminal[0]!.route.windowClass : route.tag;
        const find = () => latest.current.windows.windows.filter(w => w.kind === WindowKind.App && w.desktopId.includes(tag));
        let found = find();
        if (found.length > 1) { skipped++; continue; }
        if (found.length === 0) {
          const viewerId = crypto.randomUUID();
          if (route.kind !== "terminal") tag = chatLaunchTag(viewerId);
          const old = checkpoint.snapshot.workspaces.find(w => w.enclosedWindows.some(id => id.value === slot.savedWindow));
          // An owned DSH viewer may join its saved split. Placement and native
          // appearance share the same reducer batch, before the first frame.
          const reservation: ChatReservation = { chatPlacement: true, workspace: old?.name ?? origin.workspace, origin, reveal: false, allowOccupied: true };
          latest.current.windows.reserveChat(tag, reservation); claims.current.add(tag);
          const receipt = await runHelperRequest(domicile, route.kind === "terminal" ? [launcher] : [launcher, route.kind === "web" ? "--main" : "--session"],
            route.kind === "terminal" ? terminal[0]!.route : route.kind === "web" ? { viewerId } : { sessionId: route.session, viewerId }, Math.min(110000, Math.max(1, stopAt - Date.now())));
          const returned = route.kind === "terminal" ? receipt.windowClass : receipt.tag;
          if ((route.kind !== "web" && (route.kind === "chat" ? receipt.sessionId : receipt.session) !== route.session) ||
            (route.kind !== "terminal" ? !/^agencychat[a-f0-9]{32}$/.test(returned) : returned !== terminal[0]!.route.windowClass)) throw Error("Recovered viewer identity mismatch");
          if (returned !== tag) {
            latest.current.windows.reserveChat(tag, undefined); claims.current.delete(tag);
            tag = returned;
            latest.current.windows.reserveChat(tag, reservation); claims.current.add(tag);
          }
          const until = Math.min(stopAt, Date.now() + 30000);
          while (valid() && !latest.current.blocked && Date.now() < until && (found = find()).length === 0) {
            here(); await new Promise(resolve => setTimeout(resolve, 50));
          }
          latest.current.windows.reserveChat(tag, undefined); claims.current.delete(tag);
        }
        if (!valid()) return;
        if (found.length === 1 && !bindings.some(b => b.window === found[0]!.id)) bindings.push({ savedWindow: slot.savedWindow, window: found[0]!.id });
        else skipped++;
      }
      if (!valid()) return;
      if (latest.current.blocked) throw Error("Recovery interrupted by another desktop operation");
      const snapshot = rebindRecovery(checkpoint, latest.current.windows, bindings, here());
      if (bindings.length > 0) latest.current.windows.recoverLayout(snapshot);
      setMessage(`${bindings.length} viewer${bindings.length === 1 ? "" : "s"} restored${skipped ? ` · ${skipped} omitted` : ""}`);
      setPhase(bindings.length === checkpoint.slots.length ? "watching" : "offered");
    } catch {
      if (valid()) { setError("Chat layout recovery stopped. Opened viewers and the saved layout are kept."); setPhase("offered"); }
    } finally {
      for (const tag of claims.current) latest.current.windows.reserveChat(tag, undefined); claims.current.clear();
      running.current = false; restoreOrigin.current = undefined;
    }
  };
  const saveCurrent = async (pinned: boolean) => {
    if (running.current || blocked || !enabled || !server || !windows.layoutIdentity || !catalogue.available || !catalogue.viewersAvailable) return;
    running.current = true; setPhase("saving"); setError(undefined);
    try {
      await writing.current;
      if (!alive.current) return;
      const current = latest.current;
      const saved = { ...captureRecovery(current.windows, current.catalogue, server, current.windows.layoutIdentity!), ...(pinned ? { pinned: true as const } : {}) };
      if (pinned && saved.slots.length === 0) throw Error("No DSH viewers are open");
      const result = await domicile.files.write(FILE, JSON.stringify(saved), { atomic: true });
      result.match({ Ok: () => undefined, Err: () => { throw Error("Layout could not be saved"); } });
      if (!alive.current) return;
      setCheckpoint(saved); setPhase(pinned ? "offered" : "watching");
      setMessage(pinned ? "Chat layout saved for restart" : "Keeping the current desktop layout");
    } catch {
      if (alive.current) { setError("Chat layout could not be saved. The previous checkpoint is kept."); setPhase(checkpoint?.slots.length ? "offered" : "watching"); }
    } finally { running.current = false; }
  };
  return { enabled, phase, checkpoint, error, message, restore,
    sameDesktop: checkpoint?.incarnation === windows.layoutIdentity,
    canSave: catalogue.available && catalogue.viewersAvailable && windows.layoutIdentity !== undefined,
    saveForRestart: () => saveCurrent(true), keepCurrent: () => saveCurrent(false) };
}

export function RestartRecovery({ recovery, blocked }: { recovery: ReturnType<typeof useRestartRecovery>; blocked: boolean }) {
  if (!recovery.enabled) return null;
  const saved = recovery.checkpoint;
  return <div className="agency-layout-recovery">
    {recovery.phase === "watching" && <button type="button" className="agency-action-row" disabled={blocked || !recovery.canSave}
      onClick={() => { void recovery.saveForRestart(); }}>Save layout for restart</button>}
    {recovery.phase === "offered" && saved && <>
      <p className="agency-source-status">Saved chat layout · {saved.slots.length} viewer{saved.slots.length === 1 ? "" : "s"}{saved.omitted ? ` · ${saved.omitted} other windows cannot reopen` : ""}</p>
      <button type="button" className="agency-action-row" disabled={blocked} onClick={() => { void recovery.restore(); }}>Restore chat layout</button>
      <button type="button" className="agency-action-row" disabled={blocked} onClick={() => { void recovery.keepCurrent(); }}>{recovery.sameDesktop ? "Resume saving" : "Keep current layout"}</button>
    </>}
    {recovery.phase === "saving" && <p className="agency-source-status" role="status">Saving chat layout…</p>}
    {recovery.phase === "restoring" && <p className="agency-source-status" role="status">Restoring chat layout…</p>}
    {recovery.message && <p className="agency-source-status" role="status">{recovery.message}</p>}
    {recovery.error && <p className="agency-source-status" role="alert">{recovery.error}</p>}
  </div>;
}
