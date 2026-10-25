# Hyprland + GPUIX/Solid: implementation boundary and a bounded proof

## What can an external shell do, and what remains compositor or application work?

### Takeaway

Tom’s latest clarification fixes the roles: Hyprland is the ordinary compositor with animation/blur; the terminal is Herdr + kitty until Superlogical releases its terminal; the browser is Google Chrome. GPUIX/Solid supplies surrounding native surfaces. This is the user’s current direction, not a proposal for a new compositor.

The useful core needs no Chromium/Aura fork and no Hyprland C++ plugin: a GPUIX/Solid layer-shell client can project work context and drive existing window/workspace operations through IPC. Current upstream also has a Lua-layout route, recorded only as a capability boundary; the clarified baseline does not require it. This is a source audit on 2026-10-13, not a claim that Hyprland is deployed: the current physical client remains Sway and Strix remains headless. [Current display declaration](/home/tom/mecattaf/dotfiles/modules/display.nix)

### Cited Findings

- **Version boundary.** Hyprland source was read at `1bd31aaa579a40680ce876e1547e371b60c45522`, wiki at `fde84d41b9a7154a5d211cfb1de50d5910791231`. Current docs use Lua dispatchers; older 0.52 documentation already supplies groups, focus, workspace moves and group selection through older dispatcher syntax. Choose a compositor pin and its matching API rather than copying commands between eras. [Current dispatchers](https://github.com/hyprwm/hyprland-wiki/blob/fde84d41b9a7154a5d211cfb1de50d5910791231/content/configuring/core/dispatchers.md), [0.52 dispatchers](https://wiki.hypr.land/0.52.0/Configuring/Dispatchers/)
- **Native shell bridge exists.** The GPUIX researcher verified `WindowOptions.layerShell` with namespace, layer, anchors, exclusive zone, margins and keyboard interactivity, mapped directly to GPUI `WindowKind::LayerShell` on Linux. This is not a missing bridge or merely a theoretical upstream GPUI feature. Runtime correctness remains untested. [GPUIX pinned renderer](https://github.com/remorses/gpuix/blob/6a5c7c142ac32f9eb0caefe0121be995cfc18631/packages/native/src/renderer.rs#L7500)
- **IPC gives observation and control.** Request socket `.socket.sock` and event socket `.socket2.sock` live under `$XDG_RUNTIME_DIR/hypr/[HIS]`. Events cover windows, workspaces, focus, groups, titles and outputs. Request connections are handled synchronously and must be promptly closed; do not keep one idle. `hyprctl -j` provides JSON snapshots and batches limit control overhead. [Pinned IPC](https://github.com/hyprwm/hyprland-wiki/blob/fde84d41b9a7154a5d211cfb1de50d5910791231/content/ipc/_index.md), [hyprctl](https://github.com/hyprwm/hyprland-wiki/blob/fde84d41b9a7154a5d211cfb1de50d5910791231/content/configuring/core/advanced-configuration/using-hyprctl.md)
- **Layer-shell is sufficient for ordinary desktop surfaces.** A panel can reserve edge space; a notification can overlay without reserving space. Keyboard `none` prevents focus; `on_demand` permits ordinary focus; `exclusive` captures keyboard focus on top/overlay layers. The protocol also supports attaching xdg popups. These protocol capabilities do not prove GPUIX exposes each dynamic transition correctly. [Protocol](https://github.com/swaywm/wlr-protocols/blob/master/unstable/wlr-layer-shell-unstable-v1.xml)
- **Groups already exist.** A Hyprland group occupies one window slot and selects among windows. Current dispatchers select a group index, reorder windows, move in/out and lock groups. Workspaces are separate containers; naming one does not make it a persistent project. [Group and workspace operations](https://github.com/hyprwm/hyprland-wiki/blob/fde84d41b9a7154a5d211cfb1de50d5910791231/content/configuring/core/dispatchers.md)
- **Custom layout is not automatically a binary plugin.** Current upstream documents `hl.layout.register(name, { recalculate, layout_msg? })`; targets can be placed using columns, rows and grids. `target.window` is not necessarily present and a group can expose only its main window. This exact current capability must be checked against the chosen package version. [Pinned Lua layout docs](https://github.com/hyprwm/hyprland-wiki/blob/fde84d41b9a7154a5d211cfb1de50d5910791231/content/configuring/layouts/custom-layouts.md)
- **Plugins carry a different failure boundary.** Hyprland C++ plugins execute in its process. Official starter code compares compositor/header hashes to avoid crashes from mismatched versions. A custom decoration/rendering/input hook therefore costs coordinated builds and compositor compatibility, unlike an external shell process. [Plugin use](https://github.com/hyprwm/hyprland-wiki/blob/fde84d41b9a7154a5d211cfb1de50d5910791231/content/hyprland-plugins/using-plugins.md), [Hash check](https://github.com/hyprwm/hyprland-wiki/blob/fde84d41b9a7154a5d211cfb1de50d5910791231/content/hyprland-plugins/development/getting-started.md)

### Inferences

| Desired behavior | Implementation ownership | Gap / boundary |
|---|---|---|
| Work-context strip, Goto, attention badges | GPUIX/Solid UI reads domain/session state; Hyprland IPC focuses a matching live view | Need explicit identity mapping and attention semantics; no compositor plugin needed |
| Workspace creation, switching, window movement | Existing Hyprland operations driven by shell | Shell order and project association are application state, not inferred from workspace number |
| Native window groups and tab selection/reorder | Hyprland groups plus shell controls | Top-level/global strip feasible externally; exact per-tile attached decorations are a separate integration problem |
| Chrome-quality drag/reorder/detach | Solid interaction policy plus group/workspace dispatch | Existing group operations are primitives, not proof of Chrome interaction quality; replay historical width/hysteresis tests |
| Special split/column arrangements | Existing layouts first; current Lua layout if required | Pin/version check; only move to C++ if required behavior exceeds documented hooks |
| Workspace originated by a chat | Persist origin chat/session ID before launch, associate resulting view | PID/title heuristics alone are insufficient; browser process reuse complicates matching |
| Recover context after shell restart | Reconnect event streams and reconcile live surfaces against persisted domain IDs | Restarted applications/compositor create new runtime IDs; restore adapters belong to app/session owners |
| Uniform controls | Shell owns common outer navigation/actions | App-internal browser controls, forms, menus remain app-owned |
| Render Chrome/kitty inside a GPUI node | Not supplied by ordinary layer-shell/IPC | Standard xdg-foreign parenting is transient relationship, not arbitrary window embedding; would need a different architecture |
| Browser tabs in global overview | Chrome extension/native bridge or separate browser adapter | Hyprland observes Chrome windows, not Chrome internal tabs |

This table is architectural inference from the cited IPC, dispatcher, layout and protocol interfaces, not a tested implementation.

### Gaps

- GPUIX output selection, hotplug, fractional scale, keyboard focus restoration, popup lifecycle and dynamic layer configuration need a real isolated runtime proof. The sibling found no explicit output selection or dynamic layer update in the inspected binding API.
- A global strip or overview is the simplest supported shape. An exact custom tab strip attached to every moving/resizing tile cannot be asserted as robust merely because a layer surface can be positioned. Investigate only if Tom actually needs that specific geometry.
- No plugin has been selected or justified. Lua layout availability in latest upstream must not be used to claim availability in whatever Nix currently pins.

## Which identities, browser boundaries and preview capabilities matter?

### Takeaway

Persist work identity independently of windows. Hyprland provides live surface control and capture; Herdr and the domain services retain the work. A compositor window, Chrome tab, Herdr session and chat thread remain distinct objects even if one interface presents them coherently.

### Cited Findings

- **Hyprland stable ID is runtime identity.** Current source initializes a static counter at `0x18000000` and increments it when `CWindowMetadata` is constructed. Foreign-toplevel identifiers are its hexadecimal representation. It cannot be used as a durable project/session key across compositor restarts. [Counter implementation](https://github.com/hyprwm/Hyprland/blob/1bd31aaa579a40680ce876e1547e371b60c45522/src/desktop/view/window/WindowMetadata.cpp#L5), [Export](https://github.com/hyprwm/Hyprland/blob/1bd31aaa579a40680ce876e1547e371b60c45522/src/protocols/ForeignToplevel.cpp#L67)
- **The standard identifier is scoped.** `ext_foreign_toplevel_list_v1` identifiers identify the same mapped toplevel across clients; the protocol does not promise restoration across relaunch. [Protocol](https://github.com/wayland-mirror/wayland-protocols/blob/main/staging/ext-foreign-toplevel-list/ext-foreign-toplevel-list-v1.xml#L170)
- **Chrome owns tabs.** Its extension API creates, queries, rearranges and activates tabs; each tab has a `windowId`, and tab IDs are unique within a browser session. Tab groups are a separate Chrome API. This is an available integration seam, not evidence an integration already exists. [Tabs](https://developer.chrome.com/docs/extensions/reference/api/tabs), [Tab groups](https://developer.chrome.com/docs/extensions/reference/api/tabGroups)
- **Foreign parenting is not embedding.** xdg-foreign lets cooperating clients refer to another surface and establish parent-child relationships such as dialogs; its imported interface exposes `set_parent_of`. It does not offer an arbitrary foreign app texture as an interactive child widget. [Protocol](https://github.com/wayland-mirror/wayland-protocols/blob/main/unstable/xdg-foreign/xdg-foreign-unstable-v2.xml)
- **Per-window capture exists.** Current Hyprland implements an ext foreign-toplevel image-capture source and also publishes its older toplevel-export protocol. The latter excludes server decorations and compositor clipping and includes subsurfaces/popups clipped to base geometry. Screen capture is not interactive embedding. [Current implementation](https://github.com/hyprwm/Hyprland/blob/1bd31aaa579a40680ce876e1547e371b60c45522/src/protocols/ImageCaptureSource.cpp), [Export protocol](https://github.com/hyprwm/hyprland-protocols/blob/main/protocols/hyprland-toplevel-export-v1.xml)
- **Portals and permissions matter to capture.** XDPH supplies screen sharing and global shortcuts; its NixOS integration is enabled by the Hyprland module. Current permission controls cover screencopy and input capture but enforcement is disabled by default; direct IPC access requires separate sandbox policy if restricted. Do not infer that ordinary Wayland isolation makes an IPC-enabled shell unprivileged. [Portal](https://github.com/hyprwm/hyprland-wiki/blob/fde84d41b9a7154a5d211cfb1de50d5910791231/content/hypr-ecosystem/user/xdg-desktop-portal-hyprland.md), [Permissions](https://github.com/hyprwm/hyprland-wiki/blob/fde84d41b9a7154a5d211cfb1de50d5910791231/content/configuring/core/advanced-configuration/permissions.md)
- **Herdr lifetime already survives UI churn.** Its current service preserves old running processes across switches and is not bound to graphical-session termination. Historical isolated subscriber work showed an inactive client can receive workspace/agent snapshots; public focus operations could affect other attached clients. Preserve that boundary rather than making shell focus automatically mutate shared Herdr focus. [Current service](/home/tom/mecattaf/dotfiles/home/herdr.nix:100), [Historical protocol evidence](/home/tom/notes/references/archive/2026-10-06-wm-scoping/notes8/otto-kit/herdr-gpui-precedent.md)

### Inferences

- Keep a small mapping: durable context ID and origin chat/session ID → zero or more live view references. Live references include compositor instance plus window stable ID; Herdr workspace IDs and Chrome browser/profile/tab references remain their own typed fields. Titles are labels. Persist domain relationships, reconstruct transient references.
- One context can have a Chrome window, kitty projector and native utility; many detached Herdr sessions need no compositor workspace. This avoids turning the historical ~135 sessions into ~135 mandatory desktops.
- Keep navigation and execution separate: selecting a projector should focus that view; closing its window must not silently terminate the durable session. Reading attention state must not consume it inadvertently.
- Implement previews through a small capture adapter only when useful. The same app can render the resulting image in GPUIX, but GPUIX providing layer-shell does not prove it provides foreign-toplevel capture bindings or zero-copy import.

### Gaps

- Live capture of hidden/group-inactive/off-workspace windows, frame freshness, throttling and hardware cost were not tested. A March 2026 upstream user report describes capture hanging for invisible scrolling-layout windows; that is a historical report, not proof the current source remains broken. [Report](https://github.com/hyprwm/Hyprland/discussions/13710)
- No claim of arbitrary background pointer injection: compositor-supported shortcuts, foreground input and capture do not establish complete non-interfering automation of foreign windows.
- Existing Chrome profile launch/reuse, current Herdr projector targeting and current services need adapter audits before choosing identity heuristics. The research did not open or alter live sessions.

## What bounded proof should precede any migration?

### Takeaway

Prove a work navigation surface with live durable sessions, then decide what desktop changes it earns. A renderer demo alone does not resolve the historical usability problem.

### Cited Findings

- The current repository directs compositor experiments through `runtime-test` and protects live sessions; its physical-seat declaration is Sway. No compositor experiment, installation, service change or migration was performed in this research. [Instructions](/home/tom/mecattaf/dotfiles/AGENTS.md), [Current display](/home/tom/mecattaf/dotfiles/modules/display.nix)
- The historical reset explicitly keeps existing Chrome/kitty/Herdr primitives and treats compositor work as non-core; current user instruction supersedes Aura, not durable session preservation. [Primitives](/home/tom/notes/references/archive/2026-10-06-wm-scoping/notes7/PRIMITIVES.md)

### Inferences

1. **Model and thin adapter proof.** Pin GPUIX/Solid and Hyprland versions. Render real read-only work/session labels and attention states in one native surface. Keep a tiny explicit mapping to views, not a second work/session database. Use replayed IPC fixtures for ordinary parser work; no live runtime cleanup.
2. **Isolated compositor proof.** In a disposable VM or explicitly runtime-isolated experiment, show a layer-shell strip and keyboard-invoked Goto over a terminal plus stock browser. Demonstrate focus, group selection and workspace switching. Verify typing stays with the app unless Goto is invoked, Escape restores focus, and closing/restarting shell preserves applications. Require the repository wrapper for tests; do not borrow live D-Bus/systemd sockets.
3. **One real workflow proof.** On a deliberate test seat, associate one origin chat with a Herdr projector, browser view and artifact. Hide/reopen/restart only the shell; recover the same work and show detached work remains reachable. Distinguish close-view from terminate-work. This is the acceptance test for the actual concept.
4. **Only then add richness.** Port the proven Chrome interaction policies, add one capture preview, and test multi-output/scaling/input with the actual Zenbook devices. Try ordinary Hyprland grouping/layout first; use current Lua custom geometry if necessary; justify any C++ compositor hook with a demonstrated missing capability.
5. **Deliberate migration separately.** Compare the working proof with Sway on daily navigation, focus correctness, recovery and attention resolution. A Hyprland switch is a separately reviewable deployment with the existing Herdr preservation requirements, not an assumed outcome of this research.

### Gaps

- This proposal is a research recommendation, not a ratified implementation scope or permission to activate a compositor. No performance or quality claims were measured.
- Core proof uses long-standing layer-shell, IPC, groups and workspace primitives. New Lua layouts, newest capture protocols and stable-ID selectors are optional improvements; source/API pins decide whether adapters use them or older supported operations.
