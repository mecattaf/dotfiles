pragma Singleton

import QtQuick
import Quickshell

Singleton {
    readonly property var add: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200 }
    }
    readonly property var remove: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 150 }
    }
    readonly property var displaced: Transition {
        NumberAnimation { properties: "y"; duration: 300; easing.type: Easing.OutCubic }
    }
    readonly property var move: Transition {
        NumberAnimation { properties: "y"; duration: 300; easing.type: Easing.OutCubic }
    }
}
