//@ pragma UseWebEngine

import QtQuick
import Quickshell
import Quickshell.Wayland
import QtWebEngine

PanelWindow {
    id: wallpaperWindow

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
    visible: shellBridge.wallpaperVisible

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "shell:wallpaper"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
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

            Component.onCompleted: url = baseUrl + "#/wallpaper"

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
