import type { AppSearch } from "@domicile-desktop/manganese-launcher/app-search";
import { useEffect, useId, useMemo, useRef, useState } from "react";
import type { CSSProperties, KeyboardEvent } from "react";
import { workspaceTitle } from "./WorkspaceRail";
import type { AgencyBounds, AgencyWindow, AgencyWorkspace } from "./WorkspaceRail";
import "./rail.css";

type InstalledApp = Awaited<ReturnType<AppSearch["opening"]>>["apps"][number];
/** Uses the public launcher's app model without importing private files. */
export type AgencyApp = Pick<InstalledApp, "id" | "name"> &
  Partial<Pick<InstalledApp, "comment" | "icon">> & { detail?: string };

export type FinderProps = {
  open?: boolean;
  bounds?: AgencyBounds;
  apps: readonly AgencyApp[];
  workspaces: readonly AgencyWorkspace[];
  windows: readonly AgencyWindow[];
  onLaunchApp: (id: string) => void;
  onSelectWorkspace: (name: string) => void;
  onSelectWindow: (id: string) => void;
  onClose: () => void;
  /** Refresh the stock application's capped search results for this query. */
  onQueryChange?: (query: string) => void;
  loading?: boolean;
  /** An actual discovery/launch failure supplied by the shell, if any. */
  status?: string;
};

type Filter = "all" | "apps" | "workspaces" | "windows";
const FILTERS: readonly Filter[] = ["all", "apps", "workspaces", "windows"];
const FILTER_NAMES: Record<Filter, string> = {
  all: "All",
  apps: "Apps",
  workspaces: "Workspaces",
  windows: "Windows",
};

type Row = {
  id: string;
  target: string;
  title: string;
  detail: string;
  kind: Exclude<Filter, "all">;
  icon?: string;
};

const normalized = (text: string): string => text.normalize("NFKC").toLocaleLowerCase();

/** A bounded local search over facts the parent already discovered. */
export function finderRows(
  apps: readonly AgencyApp[],
  workspaces: readonly AgencyWorkspace[],
  windows: readonly AgencyWindow[],
  query: string,
  filter: Filter,
): readonly Row[] {
  const rows: Row[] = [
    ...workspaces.map((workspace): Row => ({
      id: `workspace:${workspace.name}`,
      target: workspace.name,
      kind: "workspaces",
      title: workspaceTitle(workspace),
      detail: `Workspace ${workspace.name} · ${workspace.windowCount} window${workspace.windowCount === 1 ? "" : "s"}`,
    })),
    ...windows.map((window): Row => ({
      id: `window:${window.id}`,
      target: window.id,
      kind: "windows",
      title: window.title.trim() || window.appName || "Untitled window",
      detail: `${window.appName ? `${window.appName} · ` : ""}Workspace ${window.workspace}`,
    })),
    ...apps.map((app): Row => ({
      id: `app:${app.id}`,
      target: app.id,
      kind: "apps",
      title: app.name,
      detail: app.detail || app.comment || "Application",
      ...(app.icon ? { icon: app.icon } : {}),
    })),
  ];
  const wanted = normalized(query.trim());
  const words = wanted.split(/\s+/).filter(Boolean);
  return rows
    .filter((row) => filter === "all" || row.kind === filter)
    .map((row, order) => {
      const title = normalized(row.title);
      const text = `${title} ${normalized(row.detail)} ${normalized(row.target)}`;
      const score = words.every((word) => text.includes(word))
        ? title === wanted && wanted !== "" ? 0 : title.startsWith(wanted) && wanted !== "" ? 1 : 2
        : -1;
      return { row, order, score };
    })
    .filter(({ score }) => score !== -1)
    .sort((one, other) => one.score - other.score || one.order - other.order)
    .slice(0, 80)
    .map(({ row }) => row);
}

/** Finder UI only: the shell owns discovery, window focus and launching. */
export function Finder({
  open = false,
  bounds,
  apps,
  workspaces,
  windows,
  onLaunchApp,
  onSelectWorkspace,
  onSelectWindow,
  onClose,
  onQueryChange,
  loading = false,
  status,
}: FinderProps) {
  const [query, setQuery] = useState("");
  const [filter, setFilter] = useState<Filter>("all");
  const [selected, setSelected] = useState(0);
  const input = useRef<HTMLInputElement>(null);
  const list = useRef<HTMLDivElement>(null);
  const instance = useId();
  const listId = `${instance}-results`;
  const rows = useMemo(
    () => finderRows(apps, workspaces, windows, query, filter),
    [apps, workspaces, windows, query, filter],
  );
  const at = Math.min(selected, Math.max(0, rows.length - 1));

  useEffect(() => {
    if (open) {
      setQuery("");
      setFilter("all");
      setSelected(0);
      input.current?.focus();
    }
  }, [open]);
  useEffect(() => {
    if (open) {
      list.current?.querySelector(`[data-result-index="${at}"]`)
        ?.scrollIntoView({ block: "nearest" });
    }
  }, [at, open, rows]);

  if (!open) return null;

  const choose = (row: Row) => {
    if (row.kind === "apps") onLaunchApp(row.target);
    else if (row.kind === "workspaces") onSelectWorkspace(row.target);
    else onSelectWindow(row.target);
    onClose();
  };
  const keyPressed = (event: KeyboardEvent<HTMLDivElement>) => {
    if (event.nativeEvent.isComposing) return;
    if (event.key === "Escape") {
      event.preventDefault();
      event.stopPropagation();
      onClose();
    } else if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault();
      event.stopPropagation();
      const step = event.key === "ArrowDown" ? 1 : -1;
      setSelected(rows.length === 0 ? 0 : (at + step + rows.length) % rows.length);
    } else if (event.key === "Enter") {
      event.preventDefault();
      event.stopPropagation();
      const row = rows[at];
      if (row) choose(row);
    } else if (event.key === "Tab") {
      event.preventDefault();
      event.stopPropagation();
      const next = (FILTERS.indexOf(filter) + (event.shiftKey ? -1 : 1) + FILTERS.length) % FILTERS.length;
      setFilter(FILTERS[next] ?? "all");
      setSelected(0);
      input.current?.focus();
    }
  };
  const style: CSSProperties = {
    left: bounds?.x ?? 0,
    top: bounds?.y ?? 0,
    width: bounds?.width ?? "100vw",
    height: bounds?.height ?? "100vh",
  };

  return (
    <div className="agency-finder-layer" onKeyDown={keyPressed} style={style}>
      <button className="agency-finder-backdrop" aria-label="Close finder" onClick={onClose} tabIndex={-1} type="button" />
      <section className="agency-finder" aria-label="Find an app, workspace or window" aria-modal="true" role="dialog">
        <header className="agency-finder-header">
          <input
            aria-activedescendant={rows[at] ? `${instance}-result-${at}` : undefined}
            aria-autocomplete="list"
            aria-controls={listId}
            aria-expanded="true"
            aria-label="Search apps, workspaces and windows"
            autoComplete="off"
            className="agency-finder-input"
            onChange={(event) => {
              const next = event.currentTarget.value;
              setQuery(next);
              setSelected(0);
              onQueryChange?.(next);
            }}
            placeholder="Search apps, workspaces and windows"
            ref={input}
            role="combobox"
            spellCheck={false}
            value={query}
          />
          <button className="agency-icon-button" aria-label="Close finder" onClick={onClose} type="button">×</button>
        </header>
        <div className="agency-finder-filters" aria-label="Search in">
          {FILTERS.map((name) => (
            <button
              aria-pressed={name === filter}
              key={name}
              onClick={() => { setFilter(name); setSelected(0); input.current?.focus(); }}
              tabIndex={-1}
              type="button"
            >{FILTER_NAMES[name]}</button>
          ))}
        </div>
        <div className="agency-finder-results" id={listId} ref={list} role="listbox" aria-label="Search results">
          {rows.map((row, index) => (
            <div
              aria-selected={index === at}
              className="agency-finder-result"
              data-result-index={index}
              id={`${instance}-result-${index}`}
              key={row.id}
              onClick={() => choose(row)}
              role="option"
            >
              {row.icon ? <img alt="" className="agency-result-icon" src={row.icon} /> : <span className="agency-result-kind" aria-hidden="true">{row.kind === "apps" ? "A" : row.kind === "windows" ? "W" : "#"}</span>}
              <span className="agency-row-text"><span className="agency-row-title">{row.title}</span><span className="agency-row-detail">{row.detail}</span></span>
              <span className="agency-result-label">{row.kind === "apps" ? "App" : row.kind === "windows" ? "Window" : "Workspace"}</span>
            </div>
          ))}
          {rows.length === 0 && <p className="agency-finder-empty" role="status">{loading ? "Reading applications…" : "No matching apps, workspaces or windows."}</p>}
        </div>
        {status && <p className="agency-source-status" role="status">{status}</p>}
        <footer className="agency-finder-footer"><span><kbd>↑</kbd><kbd>↓</kbd> select</span><span><kbd>Enter</kbd> open</span><span><kbd>Tab</kbd> filter</span><span><kbd>Esc</kbd> close</span></footer>
      </section>
    </div>
  );
}
