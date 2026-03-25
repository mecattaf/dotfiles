import QtQuick
import QtQuick.Effects

Item {
    id: root
    property var level: Theme.elevationLevel2
    property real fallbackOffset: 4
    property color targetColor: "white"
    property real targetRadius: Theme.cornerRadius
    property color borderColor: "transparent"
    property real borderWidth: 0
    property bool shadowEnabled: Theme.elevationEnabled

    layer.enabled: shadowEnabled
    layer.effect: MultiEffect {
        autoPaddingEnabled: true
        shadowEnabled: true
        blurEnabled: false
        shadowBlur: Math.max(0, Math.min(1, (root.level?.blurPx ?? 8) / 64))
        shadowHorizontalOffset: root.level?.offsetX ?? 0
        shadowVerticalOffset: root.level?.offsetY ?? root.fallbackOffset
        blurMax: 64
        shadowColor: Qt.rgba(0, 0, 0, root.level?.alpha ?? 0.25)
        shadowOpacity: 1
    }

    Rectangle {
        id: sourceRect
        anchors.fill: parent
        radius: root.targetRadius
        color: root.targetColor
        border.color: root.borderColor
        border.width: root.borderWidth
    }
}
