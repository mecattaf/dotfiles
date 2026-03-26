//@ pragma UseWebEngine

import QtQuick
import Quickshell
import Quickshell.Wayland
import QtWebEngine

WlSessionLock {
    id: sessionLock

    required property var channel
    required property string baseUrl

    Variants {
        model: Quickshell.screens

        WlSessionLockSurface {
            required property var modelData

            WebEngineView {
                anchors.fill: parent
                // Opaque background for security: lockscreen must NEVER leak desktop content
                backgroundColor: "#0a0a0a"
                webChannel: channel

                Component.onCompleted: url = baseUrl + "#/lock"

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
