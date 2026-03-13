# Webshell Research — March 13, 2026

Findings from a full-day exploration of shell UI architecture: DankMaterialShell launcher extraction, QML limitations, web-based shell prototyping, and the path to a macOS-level Wayland shell.

---

## 1. The QML Experiment (and Why It Failed)

### What We Did
Extracted the DankMaterialShell LauncherV2 — a 15-file, ~6400-line launcher with fuzzy search, frecency scoring, grid/tile/list views, file search via dsearch, app pinning, context menus, and keyboard navigation — into a self-contained module for the eqsh Quickshell config.

### The Result: 42 Files, Still Broken
To make LauncherV2 standalone (no `qs.Common`, `qs.Services`, `qs.Widgets` imports), we had to create:
- 13 service singletons (Theme, SettingsData, SessionData, I18n, Appearance, ModalManager, AppUsageHistoryData, ListViewTransitions, NiriService, DSearchService, SessionService, AppSearchService, Paths)
- 12 widget components (DankIcon, DankTextField, DankListView, DankRipple, DankDropdown, AppIconRenderer, StyledText, ElevationShadow, DankAnim, StyledRect, DankScrollbar, DankColorAnim)
- 4 JS utility modules (Scorer.js, NavigationHelpers.js, ControllerUtils.js, ItemTransformers.js)
- 10+ launcher QML components
- ScrollConstants.js

The launcher rendered with broken Material Symbols icons (`...` glyphs due to missing font path), flat opaque rectangles instead of glass, wrong theme colors, and no visual polish.

### Root Causes
1. **Font path breakage**: DankIcon.qml referenced Material Symbols from a relative path that didn't resolve from the eqsh directory structure
2. **No glass integration**: The module bundled its own flat MD3 Theme singleton instead of using eqsh's BoxGlass/GlassRim shader system
3. **Widget duplication**: Every DMS widget had to be stubbed — StyledText without Inter fonts, DankRipple without the shader file, DankListView without scroll physics constants
4. **Zero iteration tools**: No devtools, no hot reload — change QML, restart quickshell, pray

### The Fundamental QML Problem
For a *launcher* — one of the simplest shell surfaces — we wrote 42 files and ~4000 lines. The equivalent in web tech (React + CSS) took ~300 lines of TSX + ~200 lines of CSS and looked better on the first render.

| Dimension | QML (42 files) | Web (2 files) |
|---|---|---|
| Typography control | Manual font loading, no subpixel control | `font-family: 'Inter'` — done |
| Layout | Manual anchors, no flexbox/grid | CSS flexbox/grid |
| Hover/selection states | Manual `Behavior on color {}` per property | `transition: background 120ms` |
| Blur/glass | ShaderEffectSource → MultiEffect pipeline | `backdrop-filter: blur(40px)` |
| Iteration | Restart quickshell | Chrome DevTools, hot reload |
| Rich content | Limited HTML subset in QML Text | Full DOM |

---

## 2. What eqsh Already Has (Glass Primitives)

The existing eqsh Quickshell config has a complete glass morphism system:

### Shader-Based Glass
- **`BoxGlass.qml`** — Primary glass container. Properties: `color` (base tint), `light` (rim color), `lightDir` (Qt.vector2d), `rimSize`, `rimStrength`, `radius`. Uses GlassRim internally.
- **`GlassRim.qml`** — Low-level shader component using `grxframe.frag.qsb` and `grxframe.vert.qsb`. Renders edge glow with configurable direction, band width, and color.
- **`Glass.qml`** — Advanced shader using `lgxframe.frag.qsb` / `lgxframe.vert.qsb`. Full refraction, bevel, hairline reflections.
- **`GlassBox.qml`** — Glass + refractive properties: `glassBevel`, `glassMaxRefractionDistance`, `glassHairlineWidthPixels`.

### Blur
- **`BackdropBlur.qml`** — ClippingRectangle + Blur with radius support
- **`Blur.qml`** — Qt MultiEffect wrapper with configurable `blur`, `blurMax`, `blurMultiplier`

### Theme System
- **`Theme.qml`** (singleton) — 8 glass presets via `Config.appearance.glass`:
  - 0: Clear (`#20ffffff`), 1: Tinted (`#50555555`), 2: Room Light, 3: Dark (`#20000000`), 4: Opaque, 5: Room Dark, 6: Thick Dark, 7: Custom
  - `glassRimColor`: `#80ffffff`
  - `glassRimStrength`: 0.5 (weak) / 1.0 (normal) / 1.3 (strong)
- **`AccentColor.qml`** — Wallpaper-derived dynamic accent via ColorQuantizer
- **`Colors.qml`** — Utility: `complementary()`, `tintWhiteWith()`, `tintBlackWith()`
- **`Fonts.qml`** — SF Pro family (Rounded, Display, Mono) loaded from `media/fonts/`

### Working Example: Spotlight Launcher
The existing eqsh spotlight (`ui/components/spotlight/Launcher.qml`, 184 lines) demonstrates the pattern:
```qml
BoxGlass {
    radius: 25
    color: Theme.glassColor        // #20000000
    light: Theme.glassRimColor     // #80ffffff
    rimStrength: search.text == "" ? 0.2 : 1.7
    lightDir: Qt.point(1, 1)
}
```
This works and looks good — but it's limited to a search box + flat list. Extending it to Raycast-level complexity (split panes, grids, rich content, markdown) would fight QML's layout model the entire way.

---

## 3. The Web Prototype

### What We Built
A Vite + React + TypeScript prototype at `localhost:5173` with three pages:

**Page 1: Launchers** (`/`) — 6 Raycast-inspired variations:
1. App launcher with search, sections, hover/selected states, footer tabs
2. Command palette with inline parameter chips
3. Window management commands (warm glass variant)
4. Clipboard manager with split pane + preview
5. Notes/rich content with markdown headings, task checkboxes, links
6. Mixed list + grid view (DMS-style)

**Page 2: Shell + Canvas** (`/shell`) — Reproducing real shell components:
- eqsh-style top bar with app menu + system tray
- WiFi dropdown menu with network list + toggle
- Spotlight launcher overlay with keyboard navigation
- Antigravity agent manager (clean dark input UI)
- Claude Imagine canvas (sticky notes, artifact window with live analog clock, suggestion chips, chat input)
- Claude Imagine chat bubble (dark glass with progress bar)

**Page 3: Design System** (`/design`) — Component library:
- Materials M1-M5 swatches
- Color token palette (text, accent, surface states)
- Typography scale (display through overline)
- Spacing + radius reference
- Buttons (primary, secondary, ghost, danger, icon, kbd)
- Input fields (default, focused, disabled, prefix, search)
- Dropdowns (closed/open, glass menu)
- Tags, chips, badges, action pills
- Linear-style issue list items with hover-reveal actions
- Sidebar navigation tree
- Glass shell panels (bar M3, notification M4, tooltip M2, control center tiles)

### Total Code
- `App.tsx`: ~300 lines (6 launcher variations)
- `ShellPage.tsx`: ~350 lines (shell components + Claude Imagine)
- `DesignSystem.tsx`: ~400 lines (full component library)
- `index.css`: ~600 lines (all styles, all three pages)
- **Total: ~1650 lines for everything**

Compare: the QML launcher extraction was ~4000 lines for a single broken launcher.

---

## 4. Material System (M1–M5)

Adapted from Apple's HIG materials system for Wayland. The compositor provides blur via `ext-background-effect-v1`; the shell controls opacity and tint.

| Level | Opacity | Blur | Border | Shadow | Use Case |
|---|---|---|---|---|---|
| M1 | 8% black | 12px | 3% white | none | Tooltips, barely-there overlays |
| M2 | 22% black | 24px | 5% white | sm | Hover cards, popover hints |
| M3 | 48% black | 40px | 6% white | md | Panels, search bar, dropdowns |
| M4 | 68% black | 48px | 7% white | md | Modals, launcher, control center |
| M5 | 85% black | 60px | 9% white | lg | Focused overlays, sidebars |

Apple equivalents: M1 ≈ Ultra Thin, M2 ≈ Thin, M3 ≈ Regular, M4 ≈ Thick, M5 ≈ Chrome.

Interaction states scale consistently:
- Hover: +4% white over base
- Selected: +7% white over base
- Pressed: +10% white over base
- Border on focus: opacity doubles

---

## 5. Architecture Decision: Hybrid Rendering

### The Answer
Neither pure QML nor pure web. **Hybrid rendering** where:

**QML handles:**
- Window management (`PanelWindow`, layer-shell, `ext-background-effect-v1` blur requests)
- Shell chrome (top bar, notification badges, OSD) — small surfaces where vibrancy matters, using existing eqsh glass shaders
- System service aggregation (DBus → WebChannel bridge)
- The `WebEngineView` host with transparent background

**Web (SolidJS + CSS) handles:**
- Complex interactive surfaces: launcher, control center, settings, clipboard manager
- Rich content: markdown rendering, image previews, file browsers
- Anything requiring flexible layout (grids, split panes, tables)

This mirrors Apple's architecture: AppKit renders window chrome with vibrancy, content views can be WKWebView. Safari web pages don't get per-pixel vibrancy — only native surfaces do.

### Vibrancy
eqsh's fragment shaders (`grxframe.frag.qsb`, `lgxframe.frag.qsb`) already do more than Wayland blur — they compute directional rim lighting and bevel refraction from a `ShaderEffectSource` capture of the background. This is the foundation for vibrancy.

The pipeline for per-pixel luminance adaptation:
1. `ShaderEffectSource` captures pixels behind the panel (live)
2. Custom fragment shader computes blur + luminance map
3. For QML surfaces: shader directly adjusts foreground
4. For web surfaces: downsampled luminance grid (~64×64) pushed via WebChannel at 60fps (~240KB/s — feasible)
5. CSS applies regional opacity adjustments based on luminance data

Approach C (hybrid) is most practical: QML surfaces get full shader vibrancy, web surfaces get background blur + tint from the compositor, foreground stays fixed colors. This is 80% of the Apple look for 20% of the complexity.

---

## 6. QuickshellX Integration

### What's Needed
The "additive fork" principle: add `src/webengine/` to Quickshell without touching `src/core/` or `src/wayland/`.

**New components:**
- `ShellWebEngineView` (C++) — transparent `QQuickWebEngineView` wrapper
- `ShellBridge` (C++) — singleton exposing system services to WebChannel
- `ShellChannel` (C++) — WebSocket transport for WebChannel
- `MaterialSurface.qml` — QML component: ShaderEffectSource + blur + WebEngineView

**From DankMaterialShell (preserve as reference):**
- NiriService — socket-based IPC for workspaces, windows, overview toggle
- DSearchService — dsearch CLI wrapper for file search
- Scorer.js — fuzzy search with Levenshtein distance, frecency scoring, section grouping
- NavigationHelpers.js — keyboard navigation for list/grid/tile views
- The entire plugin architecture pattern (for future extensibility)

**From eqsh (keep native):**
- Glass shader system (`grxframe`, `lgxframe`) — native blur + vibrancy for shell chrome
- `PanelWindow` / `FollowingPanelWindow` — Wayland surface management
- Edge triggers, screen following, multi-monitor logic
- Audio/brightness OSD (simple surfaces, no layout complexity)

**From eqsh (move to web):**
- Control center (complex grid layout with expanding tiles)
- Settings app (forms, dropdowns, toggles)
- Launcher (the whole point of this exercise)
- Notification center (list with actions, grouping)

### Performance on Target Hardware
- AMD Ryzen 9 7900X + NVIDIA RTX 5090 + 64GB RAM
- QtWebEngine: ~150MB RAM (one process, shared across panels)
- GPU compositing: negligible
- WebChannel latency: 1-3ms (imperceptible)
- Chromium cold start: ~400ms; warm (hidden): instant
- For comparison: GNOME Shell runs its entire UI in GJS on integrated graphics

---

## 7. Design Tokens (Faraya Design System)

```typescript
const tokens = {
  material: {
    m1: { bg: 'rgba(10,10,14,0.08)', border: 'rgba(255,255,255,0.03)', blur: 12 },
    m2: { bg: 'rgba(10,10,14,0.22)', border: 'rgba(255,255,255,0.05)', blur: 24 },
    m3: { bg: 'rgba(10,10,14,0.48)', border: 'rgba(255,255,255,0.06)', blur: 40 },
    m4: { bg: 'rgba(10,10,14,0.68)', border: 'rgba(255,255,255,0.07)', blur: 48 },
    m5: { bg: 'rgba(10,10,14,0.85)', border: 'rgba(255,255,255,0.09)', blur: 60 },
  },
  color: {
    text: { primary: '#d4d4d4', secondary: '#888', muted: '#555', dim: '#3a3a3a' },
    surface: { hover: 'rgba(255,255,255,0.04)', selected: 'rgba(255,255,255,0.07)', pressed: 'rgba(255,255,255,0.10)' },
    accent: { blue: '#5b8af5', green: '#4ade80', red: '#f87171', orange: '#fb923c', purple: '#a78bfa', yellow: '#facc15' },
  },
  radius: { xs: 4, sm: 6, md: 8, lg: 12, xl: 16, pill: 9999 },
  spacing: { xs: 4, sm: 8, md: 12, lg: 16, xl: 24, xxl: 32 },
  font: {
    family: "'Inter', -apple-system, system-ui, sans-serif",
    mono: "'JetBrains Mono', 'Fira Code', monospace",
    size: { xs: 10, sm: 11, md: 13, lg: 15, xl: 18, xxl: 24, display: 32 },
    weight: { regular: 400, medium: 500, semibold: 600, bold: 700 },
  },
  shadow: {
    sm: '0 2px 8px rgba(0,0,0,0.3)',
    md: '0 8px 24px rgba(0,0,0,0.4), 0 0 0 0.5px rgba(255,255,255,0.03)',
    lg: '0 24px 80px rgba(0,0,0,0.6), 0 0 0 0.5px rgba(255,255,255,0.03)',
  },
  transition: { fast: '100ms ease', normal: '150ms ease', slow: '250ms ease' },
}
```

---

## 8. Key Decisions Made

1. **QML for plumbing, web for UI.** QML handles Wayland protocols, window management, and shader-based vibrancy. Web handles layout, interaction, and visual polish.

2. **M1-M5 material system.** Five glass tiers mapping to compositor blur + shell-controlled opacity/tint. Directly comparable to Apple HIG materials.

3. **SolidJS for production** (React for prototyping). Solid's fine-grained reactivity avoids React's reconciliation overhead — important for a shell that updates on every system event.

4. **Hybrid vibrancy.** Native QML surfaces (bar, OSD, notifications) get full shader vibrancy via eqsh's existing fragment shaders. Web surfaces get compositor blur + tint. No per-pixel vibrancy for web content (matches Apple's approach — Safari pages don't get vibrancy either).

5. **Additive fork.** QuickshellX adds `src/webengine/` without touching upstream core. Stay rebaseable on mainline Quickshell.

6. **Preserve DMS/eqsh logic, not visuals.** The search scoring, niri integration, dsearch file search, and plugin patterns from DMS are worth keeping. The QML visual components are not — they're replaced by web primitives.

---

## 9. Open Questions

- **SolidJS component library naming**: "Faraya" or something else?
- **WebChannel schema**: What system services to expose first? (Battery, WiFi, Audio, Workspaces, Notifications seem like the minimum viable set)
- **Light mode**: The entire prototype is dark-mode-only. Apple's materials system has light variants. Do we care?
- **Plugin system**: DMS has a full plugin architecture. Do we port the concept to web (npm packages?) or skip it initially?
- **Multi-monitor**: How does WebEngineView handle per-screen surfaces? One Chromium instance with multiple viewports, or separate instances?

---

## 10. Files Created

### Prototype (localhost:5173)
```
~/raycast-demo/
├── src/
│   ├── App.tsx          — 6 Raycast launcher variations
│   ├── ShellPage.tsx    — Top bar, WiFi, spotlight, Antigravity, Claude Imagine
│   ├── DesignSystem.tsx — Full component library (M1-M5, tokens, primitives)
│   ├── index.css        — All styles (~600 lines)
│   └── main.tsx         — Router with 3 pages
```

### QML Launcher (in dotfiles, functional but visually broken)
```
~/.config/quickshell/ui/components/launcherv2/
├── DmsLauncher.qml, LauncherModal.qml, LauncherContent.qml
├── Controller.qml, ResultsList.qml, ResultItem.qml, GridItem.qml, TileItem.qml
├── ActionPanel.qml, Section.qml, SectionHeader.qml, LauncherContextMenu.qml
├── Scorer.js, NavigationHelpers.js, ControllerUtils.js, ItemTransformers.js
├── Theme.qml, SettingsData.qml, SessionData.qml, I18n.qml, Appearance.qml
├── ModalManager.qml, AppUsageHistoryData.qml, ListViewTransitions.qml
├── NiriService.qml, DSearchService.qml, SessionService.qml, AppSearchService.qml, Paths.qml
├── DankIcon.qml, DankTextField.qml, DankListView.qml, DankRipple.qml
├── DankDropdown.qml, AppIconRenderer.qml, StyledText.qml, ElevationShadow.qml
├── DankAnim.qml, StyledRect.qml, DankScrollbar.qml, DankColorAnim.qml
└── ScrollConstants.js
```

### Niri Integration
- `~/.config/niri/scripts/executable_dms-launcher` — IPC toggle script
- `~/.config/niri/binds.kdl` — `Mod+Shift+D` bound to DMS launcher
