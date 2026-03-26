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

    // Defence-in-depth: release exclusive keyboard focus before the surface is
    // unmapped.  This ensures the compositor (niri) sees the focus release as a
    // discrete event *before* the surface disappears, avoiding a race where the
    // compositor never processes the focus-release because the surface is already
    // gone.  Without this, JS-initiated dismissal (async WebChannel round-trip)
    // can leave focus trapped.
    //
    // The Loader recreates this component each time overlayVisible goes true,
    // so the static `WlrLayershell.keyboardFocus: Exclusive` declaration above
    // is sufficient for the initial map — no need to re-set it here.
    onVisibleChanged: {
        if (!visible) {
            WlrLayershell.keyboardFocus = WlrKeyboardFocus.None
        }
    }

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

            // Title-change signaling: JS sets document.title to "__DISMISS_OVERLAY__"
            // when Escape is pressed. This fires synchronously in Qt (no WebChannel
            // round-trip) and works even if WebChannel method calls fail.
            onTitleChanged: {
                if (title === "__DISMISS_OVERLAY__") {
                    shellBridge.hideSurface("overlay")
                }
            }

            onTooltipRequested: function(request) { request.accepted = true }
            onContextMenuRequested: function(request) { request.accepted = true }
        }
    }
}
