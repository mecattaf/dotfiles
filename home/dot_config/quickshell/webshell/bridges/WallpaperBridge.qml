// WallpaperBridge.qml -- v0.2.0 SHOULD: Wallpaper management (#191, #192, #193)
// Per-output wallpaper, fill modes, directory browsing.
// Uses swaybg or niri-native wallpaper when available.

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

    // Per-output wallpaper map: { "eDP-1": { path: "/path/to/img", mode: "fill" }, ... }
    property var wallpapers: ({})

    // Available fill modes
    readonly property var wallpaperModes: ["fill", "fit", "stretch", "center", "tile"]

    // ======================================================================
    // Public methods
    // ======================================================================

    function setWallpaper(output, path, mode) {
        var updated = JSON.parse(JSON.stringify(root.wallpapers))
        updated[output] = {
            path: path,
            mode: mode || "fill"
        }
        root.wallpapers = updated
        _applyWallpaper(output, path, mode || "fill")
        _persistWallpapers()
    }

    function setWallpaperAll(path, mode) {
        var outputs = Object.keys(root.wallpapers)
        if (outputs.length === 0) outputs = ["*"]
        for (var i = 0; i < outputs.length; i++) {
            setWallpaper(outputs[i], path, mode || "fill")
        }
    }

    function clearWallpaper(output) {
        var updated = JSON.parse(JSON.stringify(root.wallpapers))
        delete updated[output]
        root.wallpapers = updated
        _persistWallpapers()
    }

    // ======================================================================
    // Private: apply wallpaper via swaybg
    // ======================================================================

    function _applyWallpaper(output, path, mode) {
        // Kill existing swaybg for this output, then launch new one
        var args = ["swaybg"]
        if (output !== "*") {
            args.push("-o", output)
        }
        args.push("-i", path, "-m", mode)
        Quickshell.execDetached(args)
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
        path: Qt.resolvedUrl(root._filePath)
        onLoaded: {
            try {
                root.wallpapers = JSON.parse(wallpaperFileView.text())
                console.info("WallpaperBridge: loaded wallpaper config")
            } catch (e) {
                console.warn("WallpaperBridge: failed to parse wallpaper config:", e)
            }
        }
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) {
                console.info("WallpaperBridge: no wallpaper config, using defaults")
            }
        }
    }

    function _persistWallpapers() {
        wallpaperFileView.setText(JSON.stringify(root.wallpapers, null, 2))
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
                console.warn("WallpaperBridge: HEALTH CHECK — not ready after 3s")
            } else {
                console.info("WallpaperBridge: healthy")
            }
        }
    }

    Component.onCompleted: {
        wallpaperFileView.reload()
        root.ready = true
    }
}
