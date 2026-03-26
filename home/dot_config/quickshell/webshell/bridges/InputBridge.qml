// InputBridge.qml -- Keyboard layout from niri event stream via NiriBridge.
// Reads NiriBridge.keyboardLayouts and .keyboardLayoutIndex, re-emits for frontend.

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

Scope {
    id: root

    // ======================================================================
    // Public properties (os.input)
    // ======================================================================

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
    // Signals
    // ======================================================================

    signal layoutChanged(var layout)

    // ======================================================================
    // Private: watch NiriBridge keyboard properties
    // ======================================================================

    property var _niriBridge: null

    function _connectToNiriBridge() {
        try {
            if (typeof niriBridge !== "undefined") {
                _niriBridge = niriBridge
                _niriBridge.keyboardLayoutsChanged.connect(_syncLayout)
                _niriBridge.keyboardLayoutIndexChanged.connect(_syncLayout)
                _syncLayout()
            }
        } catch (e) {
            // niriBridge not yet available
        }
    }

    function _syncLayout() {
        if (!_niriBridge) return
        var layouts = _niriBridge.keyboardLayouts ?? []
        var idx = _niriBridge.keyboardLayoutIndex ?? 0
        var name = layouts.length > idx ? layouts[idx] : "unknown"

        var newLayout = {
            name: name,
            description: name,
            index: idx
        }

        if (root.keyboardLayout.name !== newLayout.name || root.keyboardLayout.index !== newLayout.index) {
            root.keyboardLayout = newLayout
            root.layoutChanged(newLayout)
        }
    }

    Component.onCompleted: {
        Qt.callLater(_connectToNiriBridge)
    }
}
