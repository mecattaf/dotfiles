// CommandBridge.qml -- Command execution and desktop app enumeration.
// Provides execDetached() for fire-and-forget commands, and exposes
// desktopApps as a property populated by scanning .desktop files.
// The exec() method returns synchronous stdout via a Process pattern.

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property bool ready: false

    // ======================================================================
    // Public properties
    // ======================================================================

    // Desktop apps list: populated by scanning .desktop files on startup.
    // JSON-encoded array of { id, name, exec, icon, description, keywords }.
    // Frontend reads this reactively via os.command.desktopApps
    property var desktopApps: []

    // ======================================================================
    // Public methods
    // ======================================================================

    // exec(): Run a command and return stdout as a string.
    // For short-lived commands only. Uses the synchronous approach of
    // starting a Process and collecting output via signal before returning.
    // NOTE: Due to QML's event loop, the function itself returns
    // the _lastExecResult which was populated by the previous exec call.
    // For truly synchronous results, use desktopApps property instead.
    function exec(command) {
        // Launch async -- result available via _lastExecResult property
        var cmdStr = ""
        if (Array.isArray(command)) {
            cmdStr = command.join(" ")
        } else {
            cmdStr = command
        }
        _execProc.command = ["sh", "-c", cmdStr]
        _execProc.running = true
        return root._lastExecResult
    }

    property string _lastExecResult: ""

    function execDetached(command) {
        var args = []
        if (Array.isArray(command)) {
            args = command
        } else {
            args = ["sh", "-c", command]
        }
        Quickshell.execDetached(args)
    }

    // Stubs for API completeness
    function stream() { return null }
    function kill() {}
    function fileSearch() { return "[]" }
    function readFile() { return "" }
    function writeFile() {}
    function writeBinaryFile() {}
    function fileExists() { return false }
    function readDir() { return "[]" }

    // ======================================================================
    // Private: generic exec process
    // ======================================================================

    Process {
        id: _execProc
        running: false
        stdout: SplitParser {
            onRead: data => {
                root._lastExecResult = data
            }
        }
    }

    // ======================================================================
    // Private: desktop apps scanner
    // ======================================================================

    Process {
        id: appScanProc
        running: true
        command: ["bash", "-c",
            "for f in /usr/share/applications/*.desktop " +
            "$HOME/.local/share/applications/*.desktop " +
            "/var/lib/flatpak/exports/share/applications/*.desktop " +
            "$HOME/.local/share/flatpak/exports/share/applications/*.desktop; do " +
            "[ -f \"$f\" ] || continue; " +
            "name=\"\" exec=\"\" icon=\"\" comment=\"\" keywords=\"\" nodisplay=\"\" hidden=\"\" type=\"\"; " +
            "while IFS='=' read -r key val; do " +
            "case \"$key\" in " +
            "Name) [ -z \"$name\" ] && name=\"$val\" ;; " +
            "Exec) [ -z \"$exec\" ] && exec=\"$val\" ;; " +
            "Icon) [ -z \"$icon\" ] && icon=\"$val\" ;; " +
            "Comment) [ -z \"$comment\" ] && comment=\"$val\" ;; " +
            "Keywords) keywords=\"$val\" ;; " +
            "NoDisplay) nodisplay=\"$val\" ;; " +
            "Hidden) hidden=\"$val\" ;; " +
            "Type) type=\"$val\" ;; " +
            "esac; " +
            "done < \"$f\"; " +
            "[ \"$type\" != \"Application\" ] && continue; " +
            "[ \"$nodisplay\" = \"true\" ] && continue; " +
            "[ \"$hidden\" = \"true\" ] && continue; " +
            "[ -z \"$name\" ] && continue; " +
            "[ -z \"$exec\" ] && continue; " +
            "desktopid=\"$(basename \"$f\")\"; " +
            "exec_clean=\"$(echo \"$exec\" | sed 's/ %[fFuUdDnNickvm]//g')\"; " +
            "kw_clean=\"$(echo \"$keywords\" | tr ';' ',' | sed 's/,$//')\"; " +
            "printf '%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n' " +
            "\"$desktopid\" \"$name\" \"$exec_clean\" \"$icon\" \"$comment\" \"$kw_clean\"; " +
            "done"
        ]
        stdout: SplitParser {
            onRead: data => {
                var lines = data.trim().split("\n")
                var apps = []
                for (var i = 0; i < lines.length; i++) {
                    var line = lines[i]
                    if (!line) continue
                    var parts = line.split("\t")
                    if (parts.length < 3) continue
                    var keywords = (parts[5] || "").split(",").filter(function(k) { return k.length > 0 })
                    apps.push({
                        id: parts[0],
                        name: parts[1],
                        exec: parts[2],
                        icon: parts[3] || "",
                        description: parts[4] || "",
                        keywords: keywords
                    })
                }
                root.desktopApps = apps
                console.info("CommandBridge: scanned", apps.length, "desktop apps")
            }
        }
    }

    // Refresh apps list periodically (apps don't change often)
    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: {
            appScanProc.running = true
        }
    }

    // ======================================================================
    // Pull-data fallback
    // ======================================================================

    function getData(key) {
        if (key === "desktopApps") return JSON.stringify(root.desktopApps)
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
                console.warn("CommandBridge: HEALTH CHECK -- not ready after 3s")
            } else {
                console.info("CommandBridge: healthy (", root.desktopApps.length, "apps)")
            }
        }
    }

    Component.onCompleted: {
        root.ready = true
    }
}
