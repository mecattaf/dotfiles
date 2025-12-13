# Kanban Board Plugin

A fully featured kanban widget for DankMaterialShell that mirrors the functionality of the Fabric reference implementation while adding native DMS integrations and persistence.

## Features

- Three default columns (To Do, In Progress, Done) with customizable titles.
- Drag-and-drop cards between columns with positional insertion.
- Inline editing with Shift+Enter for multi-line notes.
- Quick add cards per column with keyboard shortcuts.
- Persistent storage via the DMS plugin service (`~/.config/DankMaterialShell/state/plugins/kanban`).
- Control Center integration with pop-out kanban board and live task counts in the bar.
- Settings page to rename columns and clear the entire board.

## Usage

1. Enable the plugin from DMS Settings → Plugins → Kanban Board.
2. Right-click or left-click the bar widget to open the pop-out board.
3. Drag cards by holding the left mouse button; drop between cards to reorder.
4. Double-click a card to edit, or use the delete icon to remove it.
5. Use the settings page to rename columns or reset the board.

## Notes

- The bundled calendar module in this repository (`dms-modules/calendar/calendar.py`) is self-contained; it does not rely on an external backend. It renders calendar data locally using Python's `calendar` module and system locale commands (`locale week-1stday`, `locale first_weekday`) to derive the regional first day of the week.
- No additional services are required for this kanban plugin beyond the standard DMS plugin infrastructure.

