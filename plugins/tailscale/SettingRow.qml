import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets

Rectangle {
    id: root

    property string label: ""
    property bool checked: false
    property bool enabled: true
    signal toggled()

    width: parent ? parent.width : 300
    height: 40
    radius: Theme.cornerRadius
    color: mouseArea.containsMouse ? Theme.surfaceLight : "transparent"

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.spacingS
        anchors.rightMargin: Theme.spacingS
        spacing: Theme.spacingM

        StyledText {
            text: root.label
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.surfaceText
            Layout.fillWidth: true
        }

        DankToggle {
            checked: root.checked
            enabled: root.enabled
            Layout.alignment: Qt.AlignVCenter
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        enabled: root.enabled
        onClicked: root.toggled()
    }
}
