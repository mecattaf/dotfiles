import QtQuick

Item {
    id: root
    property alias name: icon.text
    property alias size: icon.font.pixelSize
    property alias color: icon.color
    property bool filled: false
    property real fill: filled ? 1.0 : 0.0
    property int grade: -25
    property int weight: filled ? 500 : 400

    implicitWidth: Math.round(size)
    implicitHeight: Math.round(size)

    FontLoader {
        id: materialSymbolsFont
        source: Qt.resolvedUrl("../../../../DankMaterialShell/quickshell/assets/fonts/material-design-icons/variablefont/MaterialSymbolsRounded[FILL,GRAD,opsz,wght].ttf")
    }

    StyledText {
        id: icon
        anchors.fill: parent
        font.family: materialSymbolsFont.name
        font.pixelSize: 14
        font.weight: root.weight
        color: Theme.surfaceText
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignHCenter
        font.variableAxes: {
            "FILL": root.fill.toFixed(1),
            "GRAD": root.grade,
            "opsz": 24,
            "wght": root.weight
        }
    }
}
