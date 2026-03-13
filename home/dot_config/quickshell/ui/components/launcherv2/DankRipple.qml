import QtQuick

Item {
    id: root
    property color rippleColor: Theme.primary
    property real cornerRadius: 0
    property bool enableRipple: true
    anchors.fill: parent

    function trigger(x, y) {
        if (!enableRipple) return;
        rippleRect.x = x - 20;
        rippleRect.y = y - 20;
        rippleAnim.restart();
    }

    Rectangle {
        id: rippleRect
        width: 40
        height: 40
        radius: 20
        color: root.rippleColor
        opacity: 0
        visible: rippleAnim.running

        SequentialAnimation {
            id: rippleAnim
            ParallelAnimation {
                NumberAnimation { target: rippleRect; property: "opacity"; from: 0.12; to: 0; duration: 400; easing.type: Easing.OutCubic }
                NumberAnimation { target: rippleRect; property: "scale"; from: 1; to: 8; duration: 400; easing.type: Easing.OutCubic }
            }
        }
    }
}
