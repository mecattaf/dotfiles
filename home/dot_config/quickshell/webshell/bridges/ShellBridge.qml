// ShellBridge.qml -- Internal state: surface visibility, privacy aggregation,
// IPC handler for surface toggles. Config-driven via JSON FileView.
// Scorecard Gap 3 fix: reads config from $XDG_CONFIG_HOME/quickshell/webshell/config.json.
// Exposes `config` property on WebChannel for frontend theming/layout.

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    // ======================================================================
    // Public properties: readiness
    // ======================================================================

    property bool ready: false

    // ======================================================================
    // Public properties: shell metadata
    // ======================================================================

    readonly property string version: "0.2.0"
    readonly property string configPath: {
        var xdg = Quickshell.env("XDG_CONFIG_HOME")
        return xdg ? xdg + "/quickshell/webshell" : Quickshell.env("HOME") + "/.config/quickshell/webshell"
    }

    // ======================================================================
    // Public properties: config (read from JSON file, exposed to frontend)
    // ======================================================================

    property var config: ({
        bar: { position: "top", height: 40, zones: {} },
        dock: { position: "bottom", height: 72, autohide: false },
        surfaces: {
            bar: true,
            dock: true,
            overlay: false,
            notifications: true,
            osd: true,
            lockscreen: false,
            ccd: false
        },
        theme: {}
    })

    // ======================================================================
    // Public properties: surface visibility registry
    // ======================================================================

    property bool barVisible: config.surfaces?.bar ?? true
    property bool dockVisible: config.surfaces?.dock ?? true
    property bool overlayVisible: false
    property bool notificationsVisible: config.surfaces?.notifications ?? true
    property bool osdVisible: false
    property bool lockscreenVisible: false
    property bool ccdVisible: false
    // v0.2.0 SHOULD: new surfaces
    property bool settingsVisible: false
    property bool wallpaperVisible: false
    property bool wizardVisible: false

    readonly property var surfaces: _buildSurfaces()

    // ======================================================================
    // Public properties: privacy state (aggregated from AudioBridge)
    // ======================================================================

    property var privacy: ({
        microphoneActive: false,
        cameraActive: false,
        screenshareActive: false,
        microphoneApps: [],
        cameraApps: [],
        screenshareApps: []
    })

    // ======================================================================
    // Public properties: launcher state
    // ======================================================================

    property bool launcherOpen: root.overlayVisible

    // v0.2.0 SHOULD: OSD position from config (#127)
    property string osdPosition: config.osd?.position ?? "bottom-center"

    // v0.2.0 SHOULD: OSD suppressed when panel open (#129)
    readonly property bool osdSuppressed: root.overlayVisible || root.ccdVisible

    // ======================================================================
    // Signals
    // ======================================================================

    signal surfaceChanged(string surfaceId, bool visible)
    signal configReloaded()

    // ======================================================================
    // Public methods: surface control
    // ======================================================================

    function toggleSurface(name) {
        var prop = _surfaceProp(name)
        if (prop === "") {
            console.warn("ShellBridge: unknown surface:", name)
            return
        }
        root[prop] = !root[prop]
        root.surfaceChanged(name, root[prop])
    }

    function showSurface(name) {
        var prop = _surfaceProp(name)
        if (prop === "") return
        if (!root[prop]) {
            root[prop] = true
            root.surfaceChanged(name, true)
        }
    }

    function hideSurface(name) {
        var prop = _surfaceProp(name)
        if (prop === "") return
        if (root[prop]) {
            root[prop] = false
            root.surfaceChanged(name, false)
        }
    }

    function getSurface(surfaceId) {
        return root.surfaces.find(function(s) { return s.id === surfaceId }) ?? null
    }

    function openLauncher() { root.showSurface("overlay") }
    function closeLauncher() { root.hideSurface("overlay") }
    function toggleLauncher() { root.toggleSurface("overlay") }

    function reloadConfig() {
        configFileView.reload()
    }

    // v0.2.0 SHOULD: IPC config changes (#199) — live config mutation
    function updateConfig(key, value) {
        var parts = key.split(".")
        var cfg = JSON.parse(JSON.stringify(root.config))
        var obj = cfg
        for (var i = 0; i < parts.length - 1; i++) {
            if (obj[parts[i]] === undefined) obj[parts[i]] = {}
            obj = obj[parts[i]]
        }
        obj[parts[parts.length - 1]] = value
        root.config = cfg
        // Persist change
        configFileView.setText(JSON.stringify(cfg, null, 2))
        root.configReloaded()
    }

    // ======================================================================
    // Private: IPC handler for surface toggles
    // ======================================================================

    IpcHandler {
        target: "shell"
        function toggleBar(): void { root.toggleSurface("bar") }
        function toggleDock(): void { root.toggleSurface("dock") }
        function toggleOverlay(): void { root.toggleSurface("overlay") }
        function toggleNotifications(): void { root.toggleSurface("notifications") }
        function toggleCcd(): void { root.toggleSurface("ccd") }
        function toggleSettings(): void { root.toggleSurface("settings") }
        function toggleWallpaper(): void { root.toggleSurface("wallpaper") }
        function toggleWizard(): void { root.toggleSurface("wizard") }
        function showSurface(name: string): void { root.showSurface(name) }
        function hideSurface(name: string): void { root.hideSurface(name) }
    }

    // ======================================================================
    // Private: config file loading via FileView
    // ======================================================================

    FileView {
        id: configFileView
        path: Qt.resolvedUrl(root.configPath + "/config.json")
        watchChanges: true

        onLoaded: {
            try {
                var parsed = JSON.parse(configFileView.text())
                // Deep merge with defaults so missing keys don't break anything
                var merged = Object.assign({}, root.config)
                if (parsed.bar) merged.bar = Object.assign({}, merged.bar, parsed.bar)
                if (parsed.dock) merged.dock = Object.assign({}, merged.dock, parsed.dock)
                if (parsed.surfaces) merged.surfaces = Object.assign({}, merged.surfaces, parsed.surfaces)
                if (parsed.theme) merged.theme = Object.assign({}, merged.theme, parsed.theme)
                root.config = merged

                // Apply surface visibility from config (only for stateful surfaces)
                if (merged.surfaces) {
                    if (merged.surfaces.bar !== undefined) root.barVisible = merged.surfaces.bar
                    if (merged.surfaces.dock !== undefined) root.dockVisible = merged.surfaces.dock
                    if (merged.surfaces.notifications !== undefined) root.notificationsVisible = merged.surfaces.notifications
                }

                console.info("ShellBridge: config loaded from", configFileView.path)
                root.configReloaded()
            } catch (e) {
                console.warn("ShellBridge: failed to parse config:", e)
            }
        }

        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) {
                console.info("ShellBridge: no config file found, using defaults")
            } else {
                console.warn("ShellBridge: config load error:", error)
            }
        }

        onFileChanged: {
            Qt.callLater(function() { configFileView.reload() })
        }
    }

    // ======================================================================
    // Private: helpers
    // ======================================================================

    function _surfaceProp(name) {
        var map = {
            "bar": "barVisible",
            "dock": "dockVisible",
            "overlay": "overlayVisible",
            "notifications": "notificationsVisible",
            "osd": "osdVisible",
            "lockscreen": "lockscreenVisible",
            "ccd": "ccdVisible",
            "settings": "settingsVisible",
            "wallpaper": "wallpaperVisible",
            "wizard": "wizardVisible"
        }
        return map[name] ?? ""
    }

    function _buildSurfaces() {
        return [
            { id: "bar",           kind: "bar",           visible: root.barVisible },
            { id: "dock",          kind: "dock",          visible: root.dockVisible },
            { id: "overlay",       kind: "overlay",       visible: root.overlayVisible },
            { id: "notifications", kind: "notifications", visible: root.notificationsVisible },
            { id: "osd",           kind: "osd",           visible: root.osdVisible },
            { id: "lockscreen",    kind: "lockscreen",    visible: root.lockscreenVisible },
            { id: "ccd",           kind: "ccd",           visible: root.ccdVisible },
            { id: "settings",      kind: "settings",      visible: root.settingsVisible },
            { id: "wallpaper",     kind: "wallpaper",     visible: root.wallpaperVisible },
            { id: "wizard",        kind: "wizard",        visible: root.wizardVisible }
        ]
    }

    // ======================================================================
    // Public properties: installed applications (from DesktopEntries singleton)
    // ======================================================================

    property var applications: []

    function _rebuildApps() {
        var apps = []
        var entries = DesktopEntries.applications.values
        console.info("ShellBridge: _rebuildApps — raw entries:", entries ? entries.length : "null")
        for (var i = 0; i < entries.length; i++) {
            var e = entries[i]
            if (e.noDisplay) continue
            apps.push({
                id: e.id,
                name: e.name,
                genericName: e.genericName ?? "",
                comment: e.comment ?? "",
                icon: e.icon ?? "",
                execString: e.execString ?? "",
                categories: e.categories ?? [],
                keywords: e.keywords ?? []
            })
        }
        root.applications = apps
        console.info("ShellBridge: applications populated:", apps.length, "apps")
    }

    // Pull-based alternative: returns applications as a JSON string.
    // WebChannel property hydration can fail for arrays of JS objects,
    // so the frontend can call this method as a reliable fallback.
    function getApplications() {
        return JSON.stringify(root.applications)
    }

    function launchApp(desktopId) {
        var entry = DesktopEntries.heuristicLookup(desktopId)
        if (entry) {
            entry.execute()
        } else {
            console.warn("ShellBridge: launchApp — no entry found for:", desktopId)
        }
    }

    // DMS pattern: watch the DesktopEntries singleton directly for the
    // applicationsChanged signal, not the sub-object's valuesChanged.
    Connections {
        target: DesktopEntries
        function onApplicationsChanged() { root._rebuildApps() }
    }

    // Accept audioBridge as an explicit property for privacy aggregation.
    // Passed from shell.qml: ShellBridge { audioBridge: audioBridge }
    property var audioBridge: null

    // Privacy aggregation: watch AudioBridge.privacy via Connections (no fragile signal.connect)
    Connections {
        target: root.audioBridge
        function onPrivacyChanged() {
            if (root.audioBridge) root.privacy = root.audioBridge.privacy
        }
    }

    // ======================================================================
    // Health check timer
    // ======================================================================

    Timer {
        interval: 3000
        running: true
        repeat: false
        onTriggered: {
            if (!root.ready) {
                console.warn("ShellBridge: HEALTH CHECK — not ready after 3s")
            } else {
                console.info("ShellBridge: healthy")
            }
        }
    }

    Component.onCompleted: {
        configFileView.reload()
        // Sync initial privacy state if audioBridge is already populated
        if (root.audioBridge && root.audioBridge.privacy) {
            root.privacy = root.audioBridge.privacy
        }
        // Build initial app list from DesktopEntries
        root._rebuildApps()
        // Ready after config loaded (will be set via onLoaded, but mark ready
        // even if config file doesn't exist -- defaults are valid)
        root.ready = true
    }
}
