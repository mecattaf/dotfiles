pragma ComponentBehavior: Bound

import QtQuick

Rectangle {
    id: root
    property var section: null
    property var controller: null
    property string viewMode: "list"
    property bool canChangeViewMode: true
    property bool canCollapse: true
    property bool isSticky: false
    signal viewModeToggled

    width: parent?.width ?? 200; height: 32
    color: isSticky ? "transparent" : (hoverArea.containsMouse ? Theme.surfaceHover : "transparent")
    radius: Theme.cornerRadius

    MouseArea { id: hoverArea; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }

    Row {
        anchors.left: parent.left; anchors.leftMargin: Theme.spacingXS; anchors.verticalCenter: parent.verticalCenter; spacing: Theme.spacingS
        DankIcon { anchors.verticalCenter: parent.verticalCenter; name: root.section?.icon ?? "folder"; size: 16; color: Theme.surfaceVariantText }
        StyledText { anchors.verticalCenter: parent.verticalCenter; text: root.section?.title ?? ""
            font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Medium; color: Theme.surfaceVariantText }
        StyledText { anchors.verticalCenter: parent.verticalCenter; text: root.section?.items?.length ?? 0
            font.pixelSize: Theme.fontSizeSmall; color: Theme.outlineButton }
    }

    Row {
        id: rightContent; anchors.right: parent.right; anchors.rightMargin: Theme.spacingXS
        anchors.verticalCenter: parent.verticalCenter; spacing: Theme.spacingS
        Row {
            anchors.verticalCenter: parent.verticalCenter; spacing: 2
            visible: root.canChangeViewMode && !root.section?.collapsed
            Repeater {
                model: [ { mode: "list", icon: "view_list" }, { mode: "grid", icon: "grid_view" }, { mode: "tile", icon: "view_module" } ]
                Rectangle {
                    required property var modelData; required property int index
                    width: 20; height: 20; radius: 4
                    color: root.viewMode === modelData.mode ? Theme.primaryHover : modeArea.containsMouse ? Theme.surfaceHover : "transparent"
                    DankIcon { anchors.centerIn: parent; name: parent.modelData.icon; size: 14
                        color: root.viewMode === parent.modelData.mode ? Theme.primary : Theme.surfaceVariantText }
                    MouseArea { id: modeArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { if (root.viewMode !== parent.modelData.mode && root.controller && root.section)
                            root.controller.setSectionViewMode(root.section.id, parent.modelData.mode); } }
                }
            }
        }
        Item {
            width: root.canCollapse ? 24 : 0; height: 24; visible: root.canCollapse; anchors.verticalCenter: parent.verticalCenter
            DankIcon { anchors.centerIn: parent; name: root.section?.collapsed ? "expand_more" : "expand_less"
                size: 16; color: collapseArea.containsMouse ? Theme.primary : Theme.surfaceVariantText }
            MouseArea { id: collapseArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: { if (root.controller && root.section) root.controller.toggleSection(root.section.id); } }
        }
    }

    MouseArea {
        anchors.fill: parent; anchors.rightMargin: rightContent.width + Theme.spacingS
        cursorShape: root.canCollapse ? Qt.PointingHandCursor : Qt.ArrowCursor; enabled: root.canCollapse
        onClicked: { if (root.canCollapse && root.controller && root.section) root.controller.toggleSection(root.section.id); }
    }

    Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        height: 1; color: Theme.outlineMedium; visible: root.isSticky }
}
