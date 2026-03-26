// ShellBridge.qml -- Internal state: surface visibility, privacy aggregation,
// IPC handler for surface toggles (bar, launcher, dock, notifications, ccd).
// Replaces Runtime.qml's subscriber system.

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    // ======================================================================
    // Shell metadata
    // ======================================================================

    readonly property string version: "0.1.0"
    readonly property string configPath: {
        var xdg = Quickshell.env("XDG_CONFIG_HOME")
        return xdg ? xdg + "/quickshell" : Quickshell.env("HOME") + "/.config/quickshell"
    }

    // ======================================================================
    // Surface visibility registry
    // ======================================================================

    property bool barVisible: true
    property bool dockVisible: true
    property bool overlayVisible: false
    property bool notificationsVisible: true
    property bool osdVisible: false
    property bool lockscreenVisible: false
    property bool ccdVisible: false

    readonly property var surfaces: _buildSurfaces()

    // ======================================================================
    // Privacy state (aggregated from AudioBridge)
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
    // Launcher state
    // ======================================================================

    property bool launcherOpen: root.overlayVisible

    // ======================================================================
    // Signals
    // ======================================================================

    signal surfaceChanged(string surfaceId, bool visible)

    // ======================================================================
    // Methods: surface control
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

    // ======================================================================
    // Methods: launcher
    // ======================================================================

    function openLauncher() { root.showSurface("overlay") }
    function closeLauncher() { root.hideSurface("overlay") }
    function toggleLauncher() { root.toggleSurface("overlay") }

    // ======================================================================
    // IPC handler for surface toggles
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
    // Internal helpers
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
