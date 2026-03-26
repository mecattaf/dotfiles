// WallpaperBridge.qml -- v0.2.0 SHOULD: Wallpaper management (#191, #192, #193)
// Per-output wallpaper, fill modes, directory browsing.
// Uses swaybg for setting wallpaper.

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
        var screens = Quickshell.screens
        for (var i = 0; i < screens.length; i++) {
            setWallpaper(screens[i].name, path, mode || "fill")
        }
    }

    function clearWallpaper(output) {
        var updated = JSON.parse(JSON.stringify(root.wallpapers))
        delete updated[output]
        root.wallpapers = updated
        // Kill swaybg for this output
        Quickshell.execDetached(["pkill", "-f", "swaybg.*-o " + output])
        _persistWallpapers()
    }

    // ======================================================================
    // Private: apply wallpaper via swaybg
    // ======================================================================

    function _applyWallpaper(output, path, mode) {
        // Kill existing swaybg for this output first, then launch new one
        if (output !== "*") {
            Quickshell.execDetached(["bash", "-c",
                "pkill -f 'swaybg.*-o " + output + "' 2>/dev/null; " +
                "sleep 0.1; " +
                "swaybg -o '" + output + "' -i '" + path + "' -m " + mode + " &"
            ])
        } else {
            Quickshell.execDetached(["bash", "-c",
                "pkill swaybg 2>/dev/null; " +
                "sleep 0.1; " +
                "swaybg -i '" + path + "' -m " + mode + " &"
            ])
        }
    }

    // Apply all wallpapers from config
    function _applyAllWallpapers() {
        var outputs = Object.keys(root.wallpapers)
        for (var i = 0; i < outputs.length; i++) {
            var output = outputs[i]
            var wp = root.wallpapers[output]
            if (wp && wp.path) {
                _applyWallpaper(output, wp.path, wp.mode || "fill")
            }
        }
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
                root.wallpapers = parsed
                console.info("WallpaperBridge: loaded wallpaper config")
                root._applyAllWallpapers()
            } catch (e) {
                console.warn("WallpaperBridge: failed to parse wallpaper config:", e)
            }
        }
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) {
                console.info("WallpaperBridge: no wallpaper config found, applying default")
                root._applyDefaultWallpaper()
            }
        }
    }

    function _persistWallpapers() {
        wallpaperFileView.setText(JSON.stringify(root.wallpapers, null, 2))
    }

    // ======================================================================
    // Private: default wallpaper
    // ======================================================================

    function _applyDefaultWallpaper() {
        // Check for common wallpaper locations
        _defaultWallpaperProc.running = true
    }

    Process {
        id: _defaultWallpaperProc
        command: ["bash", "-c",
            "for f in " +
            "/usr/share/backgrounds/harness/wallpaper.jpg " +
            "/usr/share/backgrounds/default.png " +
            "/usr/share/backgrounds/f$(rpm -E %fedora)/default/f$(rpm -E %fedora)-01-day.png " +
            "/usr/share/backgrounds/gnome/adwaita-l.jpg " +
            "/usr/share/backgrounds/default.jpg; do " +
            "[ -f \"$f\" ] && echo \"$f\" && exit 0; " +
            "done; " +
            "echo ''"
        ]
        stdout: SplitParser {
            onRead: data => {
                var wallpaperPath = data.trim()
                if (wallpaperPath) {
                    console.info("WallpaperBridge: using default wallpaper:", wallpaperPath)
                    var screens = Quickshell.screens
                    for (var i = 0; i < screens.length; i++) {
                        root.setWallpaper(screens[i].name, wallpaperPath, "fill")
                    }
                } else {
                    console.warn("WallpaperBridge: no default wallpaper found")
                }
            }
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
                console.warn("WallpaperBridge: HEALTH CHECK -- not ready after 3s")
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
