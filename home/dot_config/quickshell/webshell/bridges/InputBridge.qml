// InputBridge.qml -- Keyboard layout from niri event stream via NiriBridge.
// Reads NiriBridge.keyboardLayouts and .keyboardLayoutIndex, re-emits for frontend.

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

Scope {
    id: root

    // ======================================================================
    // Required: NiriBridge reference (passed from shell.qml)
    // ======================================================================

    required property var niriBridge

    // ======================================================================
    // Public properties (os.input)
    // ======================================================================

    property bool ready: false

    property var keyboardLayout: ({
        name: "unknown",
        description: "Unknown",
        index: 0
    })

    property var lockKeys: ({
        capsLock: false,
        numLock: false,
        scrollLock: false
    })

    // ======================================================================
    // Private: watch NiriBridge keyboard properties via Connections
    // ======================================================================

    Connections {
        target: root.niriBridge
        function onKeyboardLayoutsChanged() { root._syncLayout() }
        function onKeyboardLayoutIndexChanged() { root._syncLayout() }
    }

    function _syncLayout() {
        if (!root.niriBridge) return
        var layouts = root.niriBridge.keyboardLayouts ?? []
        var idx = root.niriBridge.keyboardLayoutIndex ?? 0
        var name = layouts.length > idx ? layouts[idx] : "unknown"

        var newLayout = {
            name: name,
            description: name,
            index: idx
        }

        if (root.keyboardLayout.name !== newLayout.name || root.keyboardLayout.index !== newLayout.index) {
            root.keyboardLayout = newLayout
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
                console.warn("InputBridge: HEALTH CHECK — not ready after 3s")
            } else {
                console.info("InputBridge: healthy")
            }
        }
    }

    Component.onCompleted: {
        _syncLayout()
        root.ready = true
    }
}
