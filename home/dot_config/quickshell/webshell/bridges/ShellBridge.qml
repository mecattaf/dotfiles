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
    // Public properties: shell metadata
    // ======================================================================

    readonly property string version: "0.1.0"
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

    // ======================================================================
    // Private: IPC handler for surface toggles
    // ======================================================================

    IpcHandler {
        target: "shell"
        function toggleBar() { root.toggleSurface("bar") }
        function toggleDock() { root.toggleSurface("dock") }
        function toggleOverlay() { root.toggleSurface("overlay") }
        function toggleNotifications() { root.toggleSurface("notifications") }
        function toggleCcd() { root.toggleSurface("ccd") }
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
            "ccd": "ccdVisible"
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
            { id: "ccd",           kind: "ccd",           visible: root.ccdVisible }
        ]
    }

    // Connect privacy aggregation from AudioBridge when available
    Component.onCompleted: {
        configFileView.reload()
        Qt.callLater(function() {
            try {
                if (typeof audioBridge !== "undefined" && audioBridge.privacyChanged) {
                    audioBridge.privacyChanged.connect(function() {
                        root.privacy = audioBridge.privacy
                    })
                }
            } catch (e) {}
        })
    }
}
