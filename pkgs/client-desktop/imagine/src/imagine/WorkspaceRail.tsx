import type { CSSProperties, ReactNode } from "react";
import "./rail.css";

/** Page-space logical bounds of the output the Agency controls are on. */
export type AgencyBounds = {
  x: number;
  y: number;
  width: number;
  height: number;
};

/** A view of real shell workspace state; the shell keeps ownership of it. */
export type AgencyWorkspace = {
  name: string;
  title?: string;
  windowCount: number;
  urgent?: boolean;
};

/** A view of a stock ShellWindow, with its workspace supplied by the shell. */
export type AgencyWindow = {
  id: string;
  title: string;
  appName?: string;
  workspace: string;
};

export const AGENCY_RAIL_WIDTH = 256;

export type WorkspaceRailProps = {
  open?: boolean;
  bounds?: AgencyBounds;
  workspaces: readonly AgencyWorkspace[];
  currentWorkspace: string;
  onSelectWorkspace: (name: string) => void;
  onClose: () => void;
  onOpenFinder: () => void;
  onNewChat?: () => void;
  onOpenNotifications?: () => void;
  /** Real stock controls, provided with their native contexts by the shell. */
  nativeControls?: ReactNode;
  nativeChats?: ReactNode;
  /** An actual data-source failure supplied by the shell, if any. */
  status?: string;
};

export const workspaceTitle = (workspace: AgencyWorkspace): string =>
  workspace.title?.trim() || `Workspace ${workspace.name}`;

const workspaceDetail = (workspace: AgencyWorkspace): string => {
  const count = workspace.windowCount;
  const detail = count === 0 ? "Empty" : `${count} window${count === 1 ? "" : "s"}`;
  return workspace.urgent ? `Needs attention · ${detail}` : detail;
};

/**
 * NSH's workspace rail as an Agency view. The parent reserves its width in
 * the tiling and supplies the focused output's bounds. This component never
 * edits the compositor state or installs a second notification service.
 */
export function WorkspaceRail({
  open = false,
  bounds,
  workspaces,
  currentWorkspace,
  onSelectWorkspace,
  onClose,
  onOpenFinder,
  onNewChat,
  onOpenNotifications,
  nativeControls,
  nativeChats,
  status,
}: WorkspaceRailProps) {
  if (!open) return null;

  const style: CSSProperties = {
    left: bounds?.x ?? 0,
    top: bounds?.y ?? 0,
    width: Math.min(AGENCY_RAIL_WIDTH, bounds?.width ?? AGENCY_RAIL_WIDTH),
    height: bounds?.height ?? "100vh",
  };
  const row = (name: string) => {
    // Stock Manganese always has ten workspaces, including empty ones.
    const workspace = workspaces.find((item) => item.name === name) ?? {
      name,
      windowCount: 0,
    };
    const digit = name === "10" ? "0" : name;
    return (
      <button
        className="agency-workspace-row"
        aria-current={name === currentWorkspace ? "true" : undefined}
        aria-label={`${workspaceTitle(workspace)}, ${workspaceDetail(workspace)}`}
        data-urgent={workspace.urgent || undefined}
        key={name}
        onClick={() => onSelectWorkspace(name)}
        title={`Meta+${digit}`}
        type="button"
      >
        <span className="agency-workspace-slot" aria-hidden="true">{digit}</span>
        <span className="agency-row-text">
          <span className="agency-row-title">{workspaceTitle(workspace)}</span>
          <span className="agency-row-detail">{workspaceDetail(workspace)}</span>
        </span>
        {workspace.urgent && <span className="agency-urgent-dot" aria-hidden="true" />}
      </button>
    );
  };

  return (
    <aside className="agency-rail" aria-label="Workspaces" style={style}>
      <header className="agency-rail-header">
        <span>Workspaces</span>
        <button className="agency-icon-button" aria-label="Hide workspace rail" onClick={onClose} type="button">‹</button>
      </header>
      {onNewChat && (
        <div className="agency-rail-action">
          <button className="agency-action-row" onClick={onNewChat} type="button">New chat</button>
        </div>
      )}
      <nav className="agency-rail-workspaces" aria-label="Numbered workspaces">
        {nativeChats}
        <h2 className="agency-section-label">Pinned</h2>
        {Array.from({ length: 9 }, (_, at) => row(String(at + 1)))}
        <h2 className="agency-section-label">Lower workspace</h2>
        {row("10")}
      </nav>
      {status && <p className="agency-source-status" role="status">{status}</p>}
      <footer className="agency-rail-footer">
        <button className="agency-action-row" onClick={onOpenFinder} type="button"><span>Search</span><kbd>Ctrl+K</kbd></button>
        {onOpenNotifications && (
          <button className="agency-action-row" onClick={onOpenNotifications} type="button">Notifications</button>
        )}
        {nativeControls && <div className="agency-rail-native-controls">{nativeControls}</div>}
      </footer>
    </aside>
  );
}
