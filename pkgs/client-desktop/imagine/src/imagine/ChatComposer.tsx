import type { Domicile } from "@domicile-desktop/sdk/desktop/desktop";
import type { WindowState } from "@domicile-desktop/manganese-window-management/window-state";
import { WindowKind } from "@domicile-desktop/manganese-window-management/window";
import { useEffect, useEffectEvent, useRef, useState } from "react";
import { runHelperRequest } from "./HelperRequest";
import type { AgencyBounds } from "./WorkspaceRail";
import { chatLaunchTag, chatOrigin, emptyChatWorkspace } from "./ChatWindow";
import type { ChatOrigin, ChatPlacement, ChatWindowOptions, ChatReservation } from "./ChatWindow";

type Pending = { id: string; prompt: string; workspace: string; origin: ChatOrigin; accepted: boolean; reveal: boolean };
const MAX_PROMPT_BYTES = 48000;

/** Bounded capture from the fixed helper. Never log its streams or an SDK error. */
export async function sendChatRequest(domicile: Domicile, launcher: string, request: {requestId: string; prompt: string}) {
  const receipt = await runHelperRequest(domicile, [launcher, "--new"], request);
  if (receipt.requestId !== request.requestId || receipt.sessionId !== "session-" + request.requestId ||
    receipt.tag !== chatLaunchTag(request.requestId)) throw Error("Chat handoff returned a different identity.");
  return receipt;
}

export function useChatComposer({ domicile, config, state, blocked, place, reserve }: {
  domicile: Domicile; config?: ChatWindowOptions; state: WindowState; blocked: boolean;
  place: (placement: ChatPlacement) => void;
  reserve?: (tag: string, placement: ChatReservation | undefined) => void;
}) {
  const [open, setOpen] = useState(false);
  const [draft, setDraft] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const pending = useRef<Pending | undefined>(undefined);
  const inFlight = useRef(false);
  const appearanceDeadline = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const alive = useRef(true);
  useEffect(() => { alive.current = true; return () => { alive.current = false; clearTimeout(appearanceDeadline.current);
    if (pending.current) reserve?.(chatLaunchTag(pending.current.id), undefined);
  }; }, [reserve]);
  useEffect(() => {
    if (blocked) { setOpen(false); if (pending.current) {
      pending.current.reveal = false;
      reserve?.(chatLaunchTag(pending.current.id), { chatPlacement: true, workspace: pending.current.workspace, origin: pending.current.origin, reveal: false });
    } }
    const request = pending.current;
    if (request === undefined) return;
    const tag = chatLaunchTag(request.id);
    const current = chatOrigin(state);
    request.reveal &&= !blocked && current?.screen === request.origin.screen && current.workspace === request.origin.workspace;
    if (!request.reveal) reserve?.(tag, { chatPlacement: true, workspace: request.workspace, origin: request.origin, reveal: false });
    if (!request.accepted) return;
    const matches = state.windows.filter((window) => window.kind === WindowKind.App && window.desktopId.includes(tag));
    if (matches.length === 1) {
      clearTimeout(appearanceDeadline.current);
      reserve?.(tag, undefined);
      place({ chatPlacement: true, id: matches[0]!.id, workspace: request.workspace,
        origin: request.origin, reveal: request.reveal && !blocked });
      pending.current = undefined;
    } else if (matches.length > 1) {
      request.reveal = false;
      clearTimeout(appearanceDeadline.current); reserve?.(tag, undefined); pending.current = undefined;
      setError("More than one chat viewer matched. No window was moved.");
    }
  }, [blocked, state, place, reserve, busy]);
  const close = () => { setOpen(false); if (pending.current) {
    pending.current.reveal = false;
    reserve?.(chatLaunchTag(pending.current.id), { chatPlacement: true, workspace: pending.current.workspace, origin: pending.current.origin, reveal: false });
  } };
  const command = useEffectEvent((args: readonly string[]) => {
    if (args[0] !== "chat-window") return false;
    if (args.length !== 2 || !["open", "toggle"].includes(args[1] ?? "")) return true;
    if (config === undefined || blocked || busy) return true;
    if (open && args[1] === "toggle") close();
    else { setOpen(true); domicile.windows.focusShell(); }
    return true;
  });
  const submit = async () => {
    if (config === undefined || inFlight.current || busy || blocked || !draft.trim()) return;
    if (new TextEncoder().encode(draft).length > MAX_PROMPT_BYTES) {
      setError("Keep the prompt under 48000 bytes."); return;
    }
    let request = pending.current;
    if (request?.accepted) { setError("The chat has started; waiting for its Chrome window."); return; }
    if (request === undefined || request.prompt !== draft) {
      const workspace = emptyChatWorkspace(state), origin = chatOrigin(state);
      if (workspace === undefined || origin === undefined) {
        setError("No empty workspace is available for a new chat."); return;
      }
      request = { id: crypto.randomUUID(), prompt: draft, workspace, origin, accepted: false, reveal: true };
      pending.current = request;
    }
    // Retrying is a new local placement intent, while the NAS request and
    // prompt identity stay fixed after a refusal or lost acknowledgement.
    if (pending.current === request && !request.accepted) {
      const workspace = emptyChatWorkspace(state), origin = chatOrigin(state);
      if (workspace === undefined || origin === undefined) { setError("No empty workspace is available for a new chat."); return; }
      request.workspace = workspace; request.origin = origin; request.reveal = true;
    }
    reserve?.(chatLaunchTag(request.id), { chatPlacement: true, workspace: request.workspace,
      origin: request.origin, reveal: request.reveal });
    inFlight.current = true;
    setBusy(true); setError(undefined);
    try {
      await sendChatRequest(domicile, config.launcher, { requestId: request.id, prompt: request.prompt });
      request.accepted = true;
      if (!alive.current) return;
      const accepted = request;
      appearanceDeadline.current = setTimeout(() => {
        if (pending.current !== accepted) return;
        reserve?.(chatLaunchTag(accepted.id), undefined); pending.current = undefined;
        const message = "The chat started, but Chrome did not report its window. Find it in Agency Web.";
        console.error(message);
        if (alive.current) setError(message);
      }, 30000);
      if (alive.current) { setDraft(""); setOpen(false); }
    } catch {
      reserve?.(chatLaunchTag(request.id), undefined);
      if (alive.current) setError("Chat handoff did not finish. Your draft is kept; retry uses the same request.");
    } finally { inFlight.current = false; if (alive.current) setBusy(false); }
  };
  return { open, draft, setDraft, busy, error, close, command, submit };
}

export function ChatComposer({ composer, bounds }: {composer: ReturnType<typeof useChatComposer>; bounds?: AgencyBounds}) {
  const input = useRef<HTMLTextAreaElement>(null);
  useEffect(() => { if (composer.open) input.current?.focus(); }, [composer.open]);
  if (!composer.open || bounds === undefined) return null;
  return <div role="presentation" style={{ position: "fixed", zIndex: 1500, left: bounds.x, top: bounds.y,
    width: bounds.width, height: bounds.height, display: "grid", placeItems: "center", background: "#0006" }}
    onPointerDown={(event) => { if (event.target === event.currentTarget && !composer.busy) composer.close(); }}>
    <form role="dialog" aria-modal="true" aria-label="New chat" onSubmit={(event) => { event.preventDefault(); void composer.submit(); }}
      onKeyDown={(event) => { if (event.key === "Escape") { event.preventDefault(); event.stopPropagation(); composer.close(); } }}
      style={{ width: "min(640px, 90%)", padding: 16, background: "#111", color: "#d8d8d8", border: "1px solid #303030", borderRadius: 8, fontFamily: "inherit" }}>
      <label htmlFor="agency-new-chat">New chat</label>
      <textarea id="agency-new-chat" ref={input} value={composer.draft} readOnly={composer.busy} rows={5}
        placeholder="What would you like to work on?" onChange={(event) => composer.setDraft(event.target.value)}
        onKeyDown={(event) => {
          if (event.key === "Tab") { event.preventDefault(); input.current?.focus(); }
          if (event.key === "Enter" && !event.shiftKey && !event.nativeEvent.isComposing && event.nativeEvent.keyCode !== 229) {
            event.preventDefault(); event.stopPropagation(); void composer.submit();
          }
        }} style={{ display: "block", boxSizing: "border-box", width: "100%", resize: "vertical", margin: "12px 0",
          padding: 12, font: "inherit", color: "inherit", background: "#000", border: "1px solid #444", borderRadius: 4 }} />
      {composer.error && <p role="alert">{composer.error}</p>}
      <div aria-live="polite" style={{ fontSize: 12, color: "#999" }}>{composer.busy ? "Opening chat…" : "Enter opens the chat in a new workspace · Shift+Enter adds a line · Esc closes"}</div>
    </form>
  </div>;
}
