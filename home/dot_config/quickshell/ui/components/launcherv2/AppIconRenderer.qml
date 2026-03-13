import QtQuick
import Quickshell

Item {
    id: root
    required property string iconValue
    required property int iconSize
    property string fallbackText: "A"
    property color iconColor: Theme.surfaceText
    property color fallbackBackgroundColor: Theme.surfaceLight
    property color fallbackTextColor: Theme.primary
    property real materialIconSizeAdjustment: Theme.spacingM
    property real unicodeIconScale: 0.7
    property real fallbackTextScale: 0.4
    property real iconMargins: 0

    readonly property bool isMaterial: iconValue && iconValue.startsWith("material:")
    readonly property bool isUnicode: iconValue && iconValue.startsWith("unicode:")
    readonly property bool hasSpecialPrefix: isMaterial || isUnicode || (iconValue && iconValue.startsWith("image:")) || (iconValue && iconValue.startsWith("svg:")) || (iconValue && iconValue.startsWith("svg+corner:"))
    readonly property string materialName: isMaterial ? iconValue.substring(9) : ""
    readonly property string unicodeChar: isUnicode ? iconValue.substring(8) : ""
    readonly property string iconPath: {
        if (hasSpecialPrefix || !iconValue) return "";
        return Quickshell.iconPath(iconValue);
    }

    DankIcon {
        anchors.centerIn: parent
        name: root.materialName
        size: root.iconSize - root.materialIconSizeAdjustment
        color: root.iconColor
        visible: root.isMaterial
    }

    StyledText {
        anchors.centerIn: parent
        text: root.unicodeChar
        font.pixelSize: root.iconSize * root.unicodeIconScale
        color: root.iconColor
        visible: root.isUnicode
    }

    Image {
        id: iconImage
        anchors.fill: parent
        anchors.margins: root.iconMargins
        source: root.iconPath
        sourceSize: Qt.size(root.iconSize * 2, root.iconSize * 2)
        fillMode: Image.PreserveAspectFit
        mipmap: true
        asynchronous: true
        visible: !root.hasSpecialPrefix && root.iconPath !== "" && status === Image.Ready
    }

    Rectangle {
        anchors.fill: parent
        visible: !root.hasSpecialPrefix && (root.iconPath === "" || iconImage.status !== Image.Ready)
        color: root.fallbackBackgroundColor
        radius: Theme.cornerRadius
        StyledText {
            anchors.centerIn: parent
            text: root.fallbackText
            font.pixelSize: root.iconSize * root.fallbackTextScale
            color: root.fallbackTextColor
            font.weight: Font.Bold
        }
    }
}
