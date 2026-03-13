pragma ComponentBehavior: Bound

import QtQuick

Rectangle {
    id: root
    property var selectedItem: null
    property var controller: null
    property bool expanded: false
    property int selectedActionIndex: 0

    readonly property var actions: {
        var result = [];
        if (selectedItem?.primaryAction) result.push(selectedItem.primaryAction);
        if (selectedItem?.type === "app" && !selectedItem?.isCore) {
            if (SessionService.nvidiaCommand) {
                result.push({ name: I18n.tr("Launch on dGPU"), icon: "memory", action: "launch_dgpu" });
            }
            if (selectedItem?.actions) {
                for (var i = 0; i < selectedItem.actions.length; i++) result.push(selectedItem.actions[i]);
            }
        }
        return result;
    }

    readonly property bool hasActions: {
        if (selectedItem?.type === "app") return !selectedItem?.isCore;
        return actions.length > 1;
    }

    width: parent?.width ?? 200; height: expanded && hasActions ? 52 : 0
    color: Theme.surfaceContainerHigh; radius: Theme.cornerRadius; clip: true
    Behavior on height { NumberAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing } }

    Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Theme.outlineMedium }

    Item {
        anchors.fill: parent; anchors.margins: Theme.spacingS
        Flickable {
            anchors.left: parent.left; anchors.right: tabHint.left; anchors.rightMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter; height: parent.height
            contentWidth: actionsRow.width; contentHeight: height; clip: true
            boundsBehavior: Flickable.StopAtBounds; flickableDirection: Flickable.HorizontalFlick
            Row {
                id: actionsRow; height: parent.height; spacing: Theme.spacingS
                Repeater {
                    model: root.actions
                    Rectangle {
                        required property var modelData; required property int index
                        width: actionContent.implicitWidth + Theme.spacingM * 2; height: actionsRow.height; radius: Theme.cornerRadius
                        color: index === root.selectedActionIndex ? Theme.primaryHover : actionArea.containsMouse ? Theme.surfaceHover : "transparent"
                        Row {
                            id: actionContent; anchors.centerIn: parent; spacing: Theme.spacingXS
                            DankIcon { anchors.verticalCenter: parent.verticalCenter; name: modelData?.icon ?? "play_arrow"; size: 16
                                color: index === root.selectedActionIndex ? Theme.primary : Theme.surfaceText }
                            StyledText { anchors.verticalCenter: parent.verticalCenter; text: modelData?.name ?? ""
                                font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Medium
                                color: index === root.selectedActionIndex ? Theme.primary : Theme.surfaceText }
                        }
                        MouseArea { id: actionArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { if (root.controller && root.selectedItem) root.controller.executeAction(root.selectedItem, modelData); }
                            onEntered: root.selectedActionIndex = index
                        }
                    }
                }
            }
        }
        StyledText { id: tabHint; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            visible: root.hasActions; text: "Tab"; font.pixelSize: Theme.fontSizeSmall - 2; color: Theme.outlineButton }
    }

    function toggle() { expanded = !expanded; selectedActionIndex = 0; }
    function show() { expanded = true; selectedActionIndex = actions.length > 1 ? 1 : 0; }
    function hide() { expanded = false; selectedActionIndex = 0; }
    function cycleAction() { if (actions.length > 0) selectedActionIndex = (selectedActionIndex + 1) % actions.length; }
    function executeSelectedAction() {
        if (!controller || !selectedItem || selectedActionIndex >= actions.length) return;
        controller.executeAction(selectedItem, actions[selectedActionIndex]);
    }
}
