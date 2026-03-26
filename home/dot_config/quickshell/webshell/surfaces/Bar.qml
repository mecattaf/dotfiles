//@ pragma UseWebEngine

import QtQuick
import Quickshell
import Quickshell.Wayland
import QtWebEngine

Variants {
    required property var channel
    required property var shellBridge
    required property string baseUrl

    model: Quickshell.screens

    PanelWindow {
        id: barWindow

        required property var modelData

        screen: modelData

        anchors {
            top: true
            left: true
            right: true
        }

        implicitHeight: 40
        color: "transparent"
        visible: shellBridge.barVisible

        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "shell:bar"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        exclusionMode: ExclusionMode.Normal
        exclusiveZone: 40

        Rectangle {
            anchors.fill: parent
            color: "transparent"
            clip: true
            radius: 0

            WebEngineView {
                anchors.fill: parent
                backgroundColor: "transparent"
                webChannel: channel

                Component.onCompleted: url = baseUrl + "#/bar?screen=" + barWindow.modelData.name

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
}
