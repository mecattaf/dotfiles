import QtQuick
import Quickshell
import Quickshell.Io
import Tacit.Kit

FloatingWindow {
    id: window
    property string heading: "Tacit Kit"
    property var details: ({})
    default property alias body: content.data
    title: "Tacit Kit · " + heading
    implicitWidth: Kit.tokens.width.panel * 2 + Kit.tokens.space.xl * 2
    implicitHeight: Kit.tokens.height.header * 7
    color: "transparent"
    Component.onCompleted: Kit.watchKeys(window)

    WindowGround {}
    PageHeader {
        id: header
        width: parent.width
        here: window.heading
        canGoBack: false
        Slab {
            anchors.verticalCenter: parent.verticalCenter
            text: "Close window"
            onActivated: Qt.quit()
        }
    }
    Item {
        id: content
        anchors {
            top: header.bottom; bottom: parent.bottom
            left: parent.left; right: parent.right
            margins: Kit.tokens.space.xl
        }
    }
    IpcHandler {
        target: "trial"
        function snapshot(): string {
            return JSON.stringify({visible: window.visible, heading: window.heading,
                reducedMotion: Kit.reducedMotion, accent: String(Kit.tokens.accent), details: window.details});
        }
        function motion(reduced: bool): void { Kit.reducedMotion = reduced; }
    }
}
