//@ pragma UseWebEngine

// Lockscreen -- STUB
// Uses ext-session-lock-v1 via WlSessionLock.
// Implementation deferred until WlSessionLock + PamContext integration is ready.

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

                settings.javascriptCanAccessClipboard: false
                settings.localContentCanAccessRemoteUrls: false
                settings.localStorageEnabled: true
            }
        }
    }
}
