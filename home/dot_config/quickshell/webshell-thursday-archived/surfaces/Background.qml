// Background.qml -- Native QML wallpaper surface.
// PanelWindow on WlrLayer.Background with a QML Image element.
// Rendered per-screen via Variants. No swaybg dependency.

import QtQuick
import Quickshell
import Quickshell.Wayland

Variants {
    required property var wallpaperBridge

    model: Quickshell.screens

    PanelWindow {
        id: bgWindow

        required property var modelData
        screen: modelData

        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "shell:wallpaper-bg"

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        exclusiveZone: -1
        color: "#000000"

        Image {
            anchors.fill: parent
            source: wallpaperBridge.path ? ("file://" + wallpaperBridge.path) : ""
            fillMode: {
                var mode = wallpaperBridge.mode ?? "fill"
                switch (mode) {
                    case "fit": return Image.PreserveAspectFit
                    case "stretch": return Image.Stretch
                    case "tile": return Image.Tile
                    case "center": return Image.Pad
                    default: return Image.PreserveAspectCrop  // "fill"
                }
            }
            asynchronous: true
            cache: false
        }
    }
}
