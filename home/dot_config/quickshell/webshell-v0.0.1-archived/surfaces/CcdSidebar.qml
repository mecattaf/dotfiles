//@ pragma UseWebEngine

// CcdSidebar -- STUB
// Claude Code session sidebar. Right-anchored, full height.
// Content pending kmux integration.

import QtQuick
import Quickshell
import Quickshell.Wayland
import QtWebEngine

PanelWindow {
    id: ccdSidebar

    required property var channel
    required property var shellBridge
    required property string baseUrl

    anchors {
        top: true
        right: true
        bottom: true
    }

    implicitWidth: 400
    color: "transparent"
    visible: shellBridge.ccdVisible

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "shell:ccd"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    // CcdSidebar claims exclusive zone per spec
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 400
    focusable: true

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        clip: true
        radius: 0

        WebEngineView {
            anchors.fill: parent
            backgroundColor: "transparent"
            webChannel: channel

            Component.onCompleted: url = baseUrl + "#/ccd"

            onNewWindowRequested: function(request) {
                Qt.openUrlExternally(request.requestedUrl)
            }

            settings.javascriptCanAccessClipboard: false
            settings.localContentCanAccessRemoteUrls: false
            settings.localStorageEnabled: true
        }
    }
}
