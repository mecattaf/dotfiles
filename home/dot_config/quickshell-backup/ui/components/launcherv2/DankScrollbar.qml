import QtQuick
import QtQuick.Controls

ScrollBar {
    id: root
    property bool _scrollBarActive: false

    width: active || _scrollBarActive ? 10 : 0
    policy: ScrollBar.AsNeeded

    contentItem: Rectangle {
        implicitWidth: 6
        radius: 3
        color: Theme.outlineButton
        opacity: root.active || root._scrollBarActive ? 0.8 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
    }

    Timer {
        id: hideTimer
        interval: 1200
        onTriggered: root._scrollBarActive = false
    }
}
