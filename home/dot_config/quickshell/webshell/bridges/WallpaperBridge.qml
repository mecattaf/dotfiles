// WallpaperBridge.qml -- Wallpaper state management.
// Exposes path and mode properties. Actual rendering is done by
// surfaces/Background.qml (a PanelWindow on WlrLayer.Background with a
// native QML Image). No swaybg dependency.

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    // ======================================================================
    // Public properties (os.wallpaper)
    // ======================================================================

    property bool ready: false

    // Current wallpaper path and fill mode — consumed by Background.qml surface
    property string path: "/usr/share/backgrounds/harness/wallpaper.jpg"
    property string mode: "fill"  // "fill", "fit", "stretch", "center", "tile"

    // Per-output wallpaper map: { "eDP-1": { path: "/path/to/img", mode: "fill" }, ... }
    property var wallpapers: ({})

    // Available fill modes
    readonly property var wallpaperModes: ["fill", "fit", "stretch", "center", "tile"]

    // ======================================================================
    // Public methods
    // ======================================================================

    function change(newPath) {
        root.path = newPath
        _persistWallpapers()
    }

    function setMode(newMode) {
        root.mode = newMode
        _persistWallpapers()
    }

    function setWallpaper(output, wallpaperPath, wallpaperMode) {
        var updated = JSON.parse(JSON.stringify(root.wallpapers))
        updated[output] = {
            path: wallpaperPath,
            mode: wallpaperMode || "fill"
        }
        root.wallpapers = updated
        // Also update the global path/mode for the primary case
        root.path = wallpaperPath
        root.mode = wallpaperMode || "fill"
        _persistWallpapers()
    }

    function setWallpaperAll(wallpaperPath, wallpaperMode) {
        root.path = wallpaperPath
        root.mode = wallpaperMode || "fill"
        var screens = Quickshell.screens
        var updated = {}
        for (var i = 0; i < screens.length; i++) {
            updated[screens[i].name] = {
                path: wallpaperPath,
                mode: wallpaperMode || "fill"
            }
        }
        root.wallpapers = updated
        _persistWallpapers()
    }

    function clearWallpaper(output) {
        var updated = JSON.parse(JSON.stringify(root.wallpapers))
        delete updated[output]
        root.wallpapers = updated
        _persistWallpapers()
    }

    // ======================================================================
    // IPC handler for wallpaper changes
    // ======================================================================

    IpcHandler {
        target: "wallpaper"
        function change(wallpaperPath: string): void { root.change(wallpaperPath) }
        function setMode(wallpaperMode: string): void { root.setMode(wallpaperMode) }
    }

    // ======================================================================
    // Private: persistence
    // ======================================================================

    readonly property string _filePath: {
        var xdg = Quickshell.env("XDG_CONFIG_HOME")
        if (!xdg) xdg = Quickshell.env("HOME") + "/.config"
        return xdg + "/quickshell/webshell/wallpapers.json"
    }

    FileView {
        id: wallpaperFileView
        path: root._filePath
        onLoaded: {
            try {
                var parsed = JSON.parse(wallpaperFileView.text())
                if (parsed.path) root.path = parsed.path
                if (parsed.mode) root.mode = parsed.mode
                if (parsed.wallpapers) root.wallpapers = parsed.wallpapers
                console.info("WallpaperBridge: loaded wallpaper config, path:", root.path)
            } catch (e) {
                console.warn("WallpaperBridge: failed to parse wallpaper config:", e)
            }
        }
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) {
                console.info("WallpaperBridge: no config found, using default:", root.path)
            } else {
                console.warn("WallpaperBridge: config load error:", error)
            }
        }
    }

    function _persistWallpapers() {
        var data = {
            path: root.path,
            mode: root.mode,
            wallpapers: root.wallpapers
        }
        wallpaperFileView.setText(JSON.stringify(data, null, 2))
    }

    // ======================================================================
    // Pull-data fallback: getData(key)
    // ======================================================================

    function getData(key) {
        if (key === "path") return root.path
        if (key === "mode") return root.mode
        if (key === "wallpapers") return JSON.stringify(root.wallpapers)
        return "{}"
    }

    // ======================================================================
    // Health check
    // ======================================================================

    Timer {
        interval: 3000
        running: true
        repeat: false
        onTriggered: {
            if (!root.ready) {
                console.warn("WallpaperBridge: HEALTH CHECK -- not ready after 3s")
            } else {
                console.info("WallpaperBridge: healthy, path:", root.path)
            }
        }
    }

    Component.onCompleted: {
        wallpaperFileView.reload()
        root.ready = true
    }
}
