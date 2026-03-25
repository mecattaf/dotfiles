import QtQuick

Text {
    property bool isMonospace: false
    color: Theme.surfaceText
    font.pixelSize: 14
    font.family: isMonospace ? "monospace" : "Sans"
    font.weight: Theme.fontWeight
    wrapMode: Text.WordWrap
    elide: Text.ElideRight
    verticalAlignment: Text.AlignVCenter
}
