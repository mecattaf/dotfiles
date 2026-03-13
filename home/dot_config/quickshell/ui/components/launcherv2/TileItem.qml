pragma ComponentBehavior: Bound

import QtQuick

Rectangle {
    id: root
    property var item: null
    property bool isSelected: false
    property bool isHovered: itemArea.containsMouse
    property var controller: null
    property int flatIndex: -1
    signal clicked
    signal rightClicked(real mouseX, real mouseY)

    readonly property string iconValue: {
        if (!item) return "";
        switch (item.iconType) {
        case "material": case "nerd": return "material:" + (item.icon || "apps");
        case "unicode": return "unicode:" + (item.icon || "");
        case "image": default: return item.icon || "";
        }
    }

    radius: Theme.cornerRadius
    color: isSelected ? Theme.primaryPressed : isHovered ? Theme.primaryPressed : "transparent"
    border.width: isSelected ? 2 : 0; border.color: Theme.primary

    DankRipple { id: rippleLayer; rippleColor: Theme.surfaceText; cornerRadius: root.radius }

    Item {
        anchors.fill: parent; anchors.margins: 4
        Rectangle {
            anchors.fill: parent; radius: Theme.cornerRadius - 2; color: Theme.surfaceContainerHigh; clip: true
            AppIconRenderer {
                anchors.fill: parent; iconValue: root.iconValue
                iconSize: Math.min(parent.width, parent.height)
                fallbackText: (root.item?.name?.length > 0) ? root.item.name.charAt(0).toUpperCase() : "?"
                materialIconSizeAdjustment: Math.min(parent.width, parent.height) * 0.3
            }
            Rectangle {
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                height: labelT.implicitHeight + Theme.spacingS * 2
                color: Theme.withAlpha(Theme.surfaceContainer, 0.85)
                visible: root.item?.name?.length > 0
                Text {
                    id: labelT; anchors.fill: parent; anchors.margins: Theme.spacingXS
                    text: root.item?._hName ?? root.item?.name ?? ""
                    textFormat: root.item?._hRich ? Text.RichText : Text.PlainText
                    font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceText
                    elide: Text.ElideRight; horizontalAlignment: Text.AlignLeft; verticalAlignment: Text.AlignVCenter
                }
            }
            Rectangle {
                anchors.top: parent.top; anchors.right: parent.right; anchors.margins: Theme.spacingXS
                width: 20; height: 20; radius: 10; color: Theme.primary; visible: root.isSelected
                DankIcon { anchors.centerIn: parent; name: "check"; size: 14; color: Theme.primaryText }
            }
        }
    }

    MouseArea {
        id: itemArea; anchors.fill: parent; hoverEnabled: true
        cursorShape: Qt.PointingHandCursor; acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: mouse => { if (mouse.button === Qt.LeftButton) rippleLayer.trigger(mouse.x, mouse.y); }
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) { var sp = mapToItem(null, mouse.x, mouse.y); root.rightClicked(sp.x, sp.y); }
            else root.clicked();
        }
        onPositionChanged: { if (root.controller) root.controller.keyboardNavigationActive = false; }
    }
}
