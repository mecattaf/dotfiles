<!-- Local graft. Diagram-thinking adapted from figma-generate-diagram/references/gantt.md (figma-plugin-jun2026); Mermaid/FigJam syntax stripped, retargeted to this skill's HTML+SVG output. -->

# Gantt / project timeline

**Best for:** project roadmaps, release plans, sprint/iteration plans, event schedules —
anything where the primary dimension is time and items have a start, a duration, and
optionally a dependency on earlier items.

## Gantt vs timeline vs flowchart (selection)

- **Gantt** — tasks with start + duration on a time axis, grouped into lanes, with
  dependencies (task B starts after task A). Bars, not points.
- **Timeline** (`type-timeline.md`) — discrete *events* positioned in time, no durations or
  dependencies. If items are moments, not spans, use timeline.
- **Flowchart** (`type-flowchart.md`) — abstract dependency without dates ("A depends on
  B"). If there's no time axis, it's a flowchart, not a gantt.

## Layout conventions

- **Time runs left → right.** A horizontal axis with uniform units (day / week / month).
  Pick one unit for the whole chart — a 12-week sprint plan and a 3-year roadmap don't
  belong on the same axis; the units make one of them look wrong.
- **Sections are horizontal lanes.** Group tasks by phase (Discovery / Build / Launch),
  owner (Design / Eng / Marketing), or workstream (Frontend / Backend / Infra). Use lanes
  liberally once a chart passes ~8 tasks — a single lane beyond that is hard to scan.
- **Tasks are bars** spanning start→end. Sequential tasks chain: the next bar begins where
  its dependency ends, so a slip in the anchor visibly shifts everything downstream.
- **Milestones are single-point markers**, not bars — launches, gates, review points. Keep
  their names to 1–3 words; the marker is small.
- **1–2 accent bars max** — the critical path or the active task. Reserve the accent for
  genuinely critical items; if everything is critical, nothing is.
- **Keep task names short** (2–5 words) — long names stretch the left gutter.

## Anti-patterns

- Two incompatible timeframes in one chart (sprint + multi-year roadmap).
- Marking every task critical/accent — the signal dies.
- Using a gantt when items are dated *events* with no duration — that's a timeline.
- More than ~25 tasks in one chart — split into phase-specific charts (overview + detail),
  per the complexity budget.

## Examples

No bundled example yet — start from `assets/template.html` (light) or
`assets/template-dark.html` and lay bars on a horizontal time axis using the shared node /
arrow primitives.
