pragma Singleton

import QtQuick
import Quickshell

Singleton {
    readonly property bool isRtl: false
    function tr(text, context) { return text; }
}
