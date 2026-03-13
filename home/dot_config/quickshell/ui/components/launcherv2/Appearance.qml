pragma Singleton

import QtQuick
import Quickshell

Singleton {
    readonly property var fontSize: ({ normal: 14, small: 12, large: 16 })
    readonly property var rounding: ({ normal: 12 })
    readonly property var spacing: ({ normal: 8 })
    readonly property var anim: ({
        durations: { quick: 150, normal: 300, slow: 500 },
        curves: { standard: [0.2, 0, 0, 1, 1, 1] }
    })
}
