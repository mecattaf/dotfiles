// CommandBridge.qml -- Command execution and desktop app enumeration.
// Provides execDetached() for fire-and-forget commands, and exposes
// desktopApps as a property populated by scanning .desktop files.

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
    // Frontend reads this reactively via os.command.desktopApps
    property var desktopApps: []

    // ======================================================================
    // Public methods
    // ======================================================================

    function exec(command) {
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
    // Accumulates lines via SplitParser, parses on process exit.
    // ======================================================================

    property var _appScanLines: []

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
                // Accumulate each line
                var lines = root._appScanLines.slice()
                lines.push(data)
                root._appScanLines = lines
            }
        }
        onExited: {
            // Parse accumulated lines into app objects
            var lines = root._appScanLines
            var apps = []
            for (var i = 0; i < lines.length; i++) {
                var line = lines[i].trim()
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
            root._appScanLines = []
            console.info("CommandBridge: scanned", apps.length, "desktop apps")
        }
    }

    // Refresh apps list periodically (apps don't change often)
    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: {
            root._appScanLines = []
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
