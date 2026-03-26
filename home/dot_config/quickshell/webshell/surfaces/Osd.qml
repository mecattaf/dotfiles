//@ pragma UseWebEngine

import QtQuick
import Quickshell
import Quickshell.Wayland
import QtWebEngine

Variants {
    required property var channel
    required property var audioBridge
    required property var brightnessBridge
    required property var shellBridge
    required property string baseUrl

    model: Quickshell.screens

    PanelWindow {
        id: osdWindow

        required property var modelData

        screen: modelData

        anchors {
            bottom: true
        }

        margins {
            bottom: 48
        }

        implicitWidth: 240
        implicitHeight: 64
        color: "transparent"
        visible: false

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "shell:osd"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        focusable: false
        mask: Region {}

        function show() {
            if (shellBridge && shellBridge.osdSuppressed) return
            osdWindow.visible = true
            hideTimer.restart()
        }

        function hide() {
            osdWindow.visible = false
        }

        Timer {
            id: hideTimer
            interval: 1500
            repeat: false
            onTriggered: osdWindow.hide()
        }

        Connections {
            target: audioBridge
            function onVolumeOsd(event) {
                osdWindow.show()
            }
        }

        Connections {
            target: brightnessBridge
            function onBrightnessOsd(event) {
                osdWindow.show()
            }
        }

        Rectangle {
            anchors.fill: parent
            color: "transparent"
            clip: true
            radius: 12

            WebEngineView {
                anchors.fill: parent
                backgroundColor: "transparent"
                webChannel: channel

                Component.onCompleted: url = baseUrl + "#/osd?screen=" + osdWindow.modelData.name

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
