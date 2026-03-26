//@ pragma UseWebEngine

import QtQuick
import Quickshell
import Quickshell.Wayland
import QtWebEngine

PanelWindow {
    id: overlayWindow

    required property var channel
    required property var shellBridge
    required property string baseUrl

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent"
    visible: shellBridge.overlayVisible

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "shell:overlay"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    focusable: true

    // Escape is handled by the WebEngineView's JavaScript (Overlay.tsx keydown
    // listener → os.shell.closeLauncher()). QML Shortcut cannot reliably
    // intercept keypresses that WebEngineView/Chromium consumes first.

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        clip: true
        radius: 0

        WebEngineView {
            anchors.fill: parent
            backgroundColor: "transparent"
            webChannel: channel

            Component.onCompleted: url = baseUrl + "#/overlay"

            onNewWindowRequested: function(request) {
                Qt.openUrlExternally(request.requestedUrl)
            }

            settings.javascriptCanAccessClipboard: false
            settings.localContentCanAccessRemoteUrls: false
            settings.localContentCanAccessFileUrls: true
            settings.localStorageEnabled: true
            settings.focusOnNavigationEnabled: true
            settings.showScrollBars: false
            settings.linksIncludedInFocusChain: false

            onTooltipRequested: function(request) { request.accepted = true }
            onContextMenuRequested: function(request) { request.accepted = true }
        }
    }
}
