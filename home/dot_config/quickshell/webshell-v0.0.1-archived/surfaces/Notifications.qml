//@ pragma UseWebEngine

import QtQuick
import Quickshell
import Quickshell.Wayland
import QtWebEngine

Variants {
    required property var channel
    required property var shellBridge
    required property var notificationBridge
    required property string baseUrl

    model: Quickshell.screens

    PanelWindow {
        id: notifWindow

        required property var modelData

        screen: modelData

        anchors {
            top: true
            right: true
        }

        margins {
            top: 48
            right: 8
        }

        implicitWidth: 380
        implicitHeight: contentHeight
        color: "transparent"

        visible: shellBridge.notificationsVisible && notificationBridge.popups.length > 0

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "shell:notifications"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        focusable: false

        mask: Region {
            item: notifContent
        }

        property int contentHeight: Math.min(notificationBridge.popups.length * 120 + 20, 600)

        Rectangle {
            id: notifContent
            anchors.fill: parent
            color: "transparent"
            clip: true
            radius: 0

            WebEngineView {
                anchors.fill: parent
                backgroundColor: "transparent"
                webChannel: channel

                Component.onCompleted: url = baseUrl + "#/notifications?screen=" + notifWindow.modelData.name

                onNewWindowRequested: function(request) {
                    Qt.openUrlExternally(request.requestedUrl)
                }

                settings.javascriptCanAccessClipboard: false
                settings.localContentCanAccessRemoteUrls: false
                settings.localStorageEnabled: true
            }
        }
    }
}
