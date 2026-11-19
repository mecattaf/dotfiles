import type { WorkspaceMode } from "./WorkspaceModes";

/** The two owned desktop modes, always named in the workspace rail. */
export const WorkspaceModeToggle = ({mode, onSelect, disabled = false}: {
  mode: WorkspaceMode;
  onSelect: (mode: WorkspaceMode) => void;
  disabled?: boolean;
}) => <div role="group" aria-label="Workspace layout" style={{display: "flex", gap: 4, margin: "8px 12px 12px",
  padding: 3, border: "1px solid #ffffff1a", borderRadius: 6}}>
  {([['scrolling', 'Scrolling'], ['floating', 'Floating']] as const).map(([value, label]) =>
    <button key={value} type="button" aria-pressed={value === mode} disabled={disabled}
      onClick={() => onSelect(value)} style={{flex: 1, padding: "5px 8px", border: 0, borderRadius: 3,
        font: "inherit", fontSize: 12, color: value === mode ? "#eee9df" : "#a7a29a",
        background: value === mode ? "#ffffff15" : "transparent", cursor: disabled ? "default" : "pointer"}}>{label}</button>)}
</div>;
