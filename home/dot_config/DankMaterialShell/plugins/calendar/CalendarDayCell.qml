import QtQuick
import qs.Common
import qs.Widgets

Item {
    id: root
    property var cellData
    property real size: 44

    implicitWidth: size
    implicitHeight: size

    Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadius
        color: cellData && cellData.isToday ? Theme.primary : Theme.surfaceContainerHigh
        opacity: cellData && cellData.inMonth === false ? 0.4 : 1.0
        border.width: cellData && cellData.isToday ? 0 : 1
        border.color: Theme.surfaceVariant
    }

    StyledText {
        anchors.centerIn: parent
        text: cellData ? cellData.day : ""
        color: cellData && cellData.isToday ? Theme.onPrimary : Theme.surfaceText
        font.pixelSize: Theme.fontSizeMedium
        font.weight: cellData && cellData.isToday ? Font.DemiBold : Font.Normal
    }
}
