pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property bool inOverview: false

    readonly property string socketPath: Quickshell.env("NIRI_SOCKET") || ""

    function toggleOverview() {
        if (socketPath)
            Quickshell.execDetached(["niri", "msg", "action", "toggle-overview"]);
    }
}
