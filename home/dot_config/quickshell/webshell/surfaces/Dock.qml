//@ pragma UseWebEngine

import QtQuick
import Quickshell
import Quickshell.Wayland
import QtWebEngine

PanelWindow {
    id: dockWindow

    required property var channel
    required property var shellBridge
    required property string baseUrl

    anchors {
        bottom: true
        left: true
        right: true
    }

    implicitHeight: 72
    color: "transparent"
    visible: shellBridge.dockVisible

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "shell:dock"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0

    mask: Region {
        item: dockContent
    }

    Rectangle {
        id: dockContent
        anchors.fill: parent
        color: "transparent"
        clip: true
        radius: 0

        WebEngineView {
            anchors.fill: parent
            backgroundColor: "transparent"
            webChannel: channel

            Component.onCompleted: url = baseUrl + "#/dock"

            onNewWindowRequested: function(request) {
                Qt.openUrlExternally(request.requestedUrl)
            }

            settings.javascriptCanAccessClipboard: false
            settings.localContentCanAccessRemoteUrls: false
            settings.localContentCanAccessFileUrls: true
            settings.localStorageEnabled: true
            settings.focusOnNavigationEnabled: false
            settings.showScrollBars: false
            settings.linksIncludedInFocusChain: false

            onTooltipRequested: function(request) { request.accepted = true }
            onContextMenuRequested: function(request) { request.accepted = true }
        }
    }
}
