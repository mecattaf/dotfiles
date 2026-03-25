import QtQuick
import QtQuick.Controls

Item {
    id: root
    property string text: ""
    property string description: ""
    property string currentValue: ""
    property var options: []
    property bool enableFuzzySearch: false
    property int maxPopupHeight: 400
    property int popupWidth: 0
    property int dropdownWidth: 200
    property bool compactMode: text === "" && description === ""
    property bool addHorizontalPadding: false
    signal valueChanged(string value)

    function closeDropdownMenu() { dropdownMenu.close(); }

    width: compactMode ? dropdownWidth : parent.width
    implicitHeight: compactMode ? 40 : 60

    Rectangle {
        id: dropdown
        width: root.compactMode ? parent.width : root.dropdownWidth
        height: 40
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        radius: Theme.cornerRadius
        color: dropdownArea.containsMouse || dropdownMenu.visible ? Theme.surfaceContainerHigh : Theme.surfaceContainer
        border.color: dropdownMenu.visible ? Theme.primary : Theme.outlineMedium
        border.width: dropdownMenu.visible ? 2 : 1

        MouseArea {
            id: dropdownArea
            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (dropdownMenu.visible) { dropdownMenu.close(); return; }
                var pos = dropdown.mapToItem(Overlay.overlay, 0, 0);
                dropdownMenu.x = pos.x;
                dropdownMenu.y = pos.y + dropdown.height + 4;
                dropdownMenu.open();
            }
        }

        Row {
            anchors.left: parent.left; anchors.right: expandIcon.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Theme.spacingM; anchors.rightMargin: Theme.spacingS
            StyledText {
                text: root.currentValue; font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceText; anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
            }
        }
        DankIcon {
            id: expandIcon; name: dropdownMenu.visible ? "expand_less" : "expand_more"
            size: 20; color: Theme.surfaceText
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin: Theme.spacingS
        }
    }

    Popup {
        id: dropdownMenu
        parent: Overlay.overlay
        width: root.popupWidth > 0 ? root.popupWidth : dropdown.width
        height: Math.min(root.maxPopupHeight, Math.min(root.options.length, 10) * 36 + 16)
        padding: 0; modal: true; dim: false
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle { color: "transparent" }

        contentItem: Rectangle {
            color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 1)
            border.color: Theme.primary; border.width: 2; radius: Theme.cornerRadius

            ListView {
                anchors.fill: parent; anchors.margins: Theme.spacingS
                model: root.options; spacing: 2; clip: true

                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: ListView.view.width; height: 32; radius: Theme.cornerRadius
                    color: root.currentValue === modelData ? Theme.primaryHover : optArea.containsMouse ? Theme.primaryHoverLight : "transparent"
                    StyledText {
                        anchors.left: parent.left; anchors.leftMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData; font.pixelSize: Theme.fontSizeMedium
                        color: root.currentValue === modelData ? Theme.primary : Theme.surfaceText
                        font.weight: root.currentValue === modelData ? Font.Medium : Font.Normal
                    }
                    MouseArea {
                        id: optArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { root.currentValue = modelData; root.valueChanged(modelData); dropdownMenu.close(); }
                    }
                }
            }
        }
    }
}
