// Native Imagine controllers for the historical F9 and Shift+F9 actions.
import { useEffect, useRef, useState } from "react";
import type { Domicile } from "@domicile-desktop/sdk/desktop/desktop";
import type { AgencyBounds } from "./WorkspaceRail";
import { runHelperRequest } from "./HelperRequest";

export function AudioMenu({ domicile, kind, bounds, onClose }: {
  domicile: Domicile; kind?: "audio" | "recording"; bounds?: AgencyBounds; onClose: () => void;
}) {
  const [choices, setChoices] = useState<{ id: string; label: string; detail?: string }[]>([]);
  const [detail, setDetail] = useState("");
  const [message, setMessage] = useState("");
  const [busy, setBusy] = useState(false);
  const pending = useRef(false);
  const panel = useRef<HTMLElement>(null);
  const generation = useRef(0);
  const request = (action: string, route?: string) => runHelperRequest(domicile,
    ["imagine-audio-control"], { action, route }, 600000);
  useEffect(() => {
    const version = ++generation.current;
    setChoices([]); setMessage(""); setDetail("");
    if (kind === undefined) return;
    panel.current?.focus(); setBusy(true);
    void request(`${kind}-menu`).then(reply => {
      if (version !== generation.current) return;
      if (!reply.ok) throw Error(reply.message);
      setChoices(reply.choices); setDetail(reply.detail);
    }).catch((error: unknown) => { if (version === generation.current) setMessage(String(error)); })
      .finally(() => { if (version === generation.current) setBusy(false); });
    return () => { generation.current++; };
  }, [kind, domicile]);
  if (kind === undefined) return null;
  const choose = async (id: string) => {
    if (pending.current || busy || !choices.some(choice => choice.id === id)) return;
    pending.current = true; setBusy(true); setMessage("");
    const version = generation.current;
    try {
      const reply = await request(kind === "audio" ? "audio-select" : `recording-${id}`, id);
      if (version !== generation.current) return;
      setMessage(reply.message ?? "");
      const menu = await request(`${kind}-menu`);
      if (version !== generation.current) return;
      if (menu.ok) { setChoices(menu.choices); setDetail(menu.detail); }
    } catch (error) { if (version === generation.current) setMessage(String(error)); }
    finally { pending.current = false; if (version === generation.current) setBusy(false); }
  };
  const title = kind === "audio" ? "Output + microphone" : "Call recording";
  return <div className="agency-finder-layer" style={{ left: bounds?.x ?? 0, top: bounds?.y ?? 0,
    width: bounds?.width ?? "100vw", height: bounds?.height ?? "100vh" }} onKeyDown={event => {
      if (event.key === "Escape") { event.preventDefault(); event.stopPropagation(); onClose(); }
      if (event.key === "ArrowDown" || event.key === "ArrowUp") {
        event.preventDefault(); event.stopPropagation();
        const buttons = Array.from(panel.current?.querySelectorAll<HTMLButtonElement>("button:not(:disabled)") ?? []);
        const index = buttons.indexOf(document.activeElement as HTMLButtonElement);
        buttons[(index + (event.key === "ArrowDown" ? 1 : -1) + buttons.length) % buttons.length]?.focus();
      }
    }}>
    <button className="agency-finder-backdrop" aria-label="Close audio menu" onClick={onClose} tabIndex={-1} type="button" />
    <section className="agency-finder" role="dialog" aria-modal="true" aria-label={title} ref={panel} tabIndex={-1}>
      <header className="agency-finder-header"><span className="agency-row-text">{title}</span>
        <button className="agency-icon-button" aria-label="Close audio menu" onClick={onClose} type="button">×</button></header>
      <p className="agency-source-status">{detail}</p>
      <div className="agency-finder-results">
        {choices.map(choice => <button className="agency-action-row" key={choice.id} disabled={busy || pending.current}
          type="button" onClick={() => { void choose(choice.id); }}>
          <span className="agency-row-text"><span className="agency-row-title">{choice.label}</span>
            {choice.detail && <span className="agency-row-detail">{choice.detail}</span>}</span></button>)}
        {busy && <p className="agency-source-status" role="status">Working…</p>}
      </div>
      {message && <p className="agency-source-status" role="status" style={{ whiteSpace: "pre-wrap" }}>{message}</p>}
      <footer className="agency-finder-footer"><span><kbd>↑</kbd><kbd>↓</kbd> select</span><span><kbd>Enter</kbd> choose</span><span><kbd>Esc</kbd> close</span></footer>
    </section>
  </div>;
}
