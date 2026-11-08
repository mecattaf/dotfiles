import { ATTENTION_LABELS } from "./SessionCatalogue";
import type { useSessionCatalogue } from "./useSessionCatalogue";

/** Host metadata and real native windows; no browser sidebar or agent controller. */
export function SessionCatalogue({ controller, blocked }: {
  controller: ReturnType<typeof useSessionCatalogue>; blocked: boolean;
}) {
  const { catalogue, rows, busy, error, open, openWeb } = controller;
  return <section aria-label="DSH chats" className="agency-chats">
    <h2 className="agency-section-label">Chats</h2>
    {openWeb && <button type="button" className="agency-action-row" disabled={blocked || busy !== undefined}
      onClick={() => { void openWeb(); }}> {busy === "$web" ? "Opening DSH web…" : "Open DSH web"}</button>}
    {!catalogue.available && <p className="agency-source-status" role="status">Chat status unavailable</p>}
    {catalogue.available && rows.length === 0 && <p className="agency-source-status">No chats yet</p>}
    {rows.map((row) => <div className="agency-chat" key={row.sessionId} data-session-id={row.sessionId}>
      <button type="button" className="agency-workspace-row" data-unseen={row.unseen || undefined}
        disabled={blocked || (busy !== undefined && busy !== row.sessionId) || (!row.available && row.viewers.length === 0)}
        aria-label={`${row.title}, ${row.available ? ATTENTION_LABELS[row.status] : "status unavailable"}`}
        onClick={() => { void open(row); }} title={row.title}>
        <span className="agency-row-text">
          <span className="agency-row-title">{row.title}</span>
          <span className="agency-row-detail">{busy === row.sessionId ? "Opening…" : row.available ? ATTENTION_LABELS[row.status] : "Status unavailable"}
            {row.viewers[0]?.workspace && ` · ${row.viewers[0].workspace}`}
            {row.pendingApprovals > 1 && ` · ${row.pendingApprovals} approvals`}
            {row.pendingQuestions > 1 && ` · ${row.pendingQuestions} questions`}
          </span>
        </span>
        {row.unseen && <span className="agency-urgent-dot" aria-label="New attention" />}
      </button>
      {row.terminals.map((terminal) => <button type="button" className="agency-chat-terminal" key={terminal.route.windowClass}
        disabled={blocked || busy !== undefined || (!row.available && terminal.id === undefined)}
        onClick={() => { void open(row, terminal); }} title={terminal.title}>
        <span className="agency-row-title">{terminal.title}</span>
        <span className="agency-row-detail">{terminal.workspace ? `Workspace ${terminal.workspace}` : "Open terminal"}</span>
      </button>)}
    </div>)}
    {error && <p className="agency-source-status" role="alert">{error}</p>}
  </section>;
}
