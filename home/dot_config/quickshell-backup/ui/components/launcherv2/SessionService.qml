pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property string nvidiaCommand: ""
    property bool wtypeAvailable: false

    Component.onCompleted: {
        nvidiaProc.running = true;
        wtypeProc.running = true;
    }

    Process {
        id: nvidiaProc
        command: ["which", "prime-run"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                if (nvidiaProc.exitCode === 0)
                    root.nvidiaCommand = "prime-run";
            }
        }
    }

    Process {
        id: wtypeProc
        command: ["which", "wtype"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                root.wtypeAvailable = (wtypeProc.exitCode === 0);
            }
        }
    }

    function launchDesktopEntry(entry, useNvidia) {
        if (!entry) return;
        var execStr = entry.execString || entry.exec || "";
        if (!execStr) {
            entry.execute();
            return;
        }
        if (useNvidia && nvidiaCommand) {
            Quickshell.execDetached([nvidiaCommand].concat(execStr.split(" ")));
        } else {
            entry.execute();
        }
    }

    function launchDesktopAction(entry, action, useNvidia) {
        if (!entry || !action) return;
        if (typeof action.execute === "function") {
            action.execute();
        } else {
            entry.execute();
        }
    }
}
