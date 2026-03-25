pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

Item {
    id: root
    property var section: null
    property var controller: null
    property string viewMode: "list"
    property int gridColumns: 4
    property int startIndex: 0
    signal itemClicked(int flatIndex)
    signal itemRightClicked(int flatIndex, var item, real mouseX, real mouseY)

    height: headerItem.height + (section?.collapsed ? 0 : contentCol.height + Theme.spacingXS)
    width: parent?.width ?? 200

    SectionHeader {
        id: headerItem; width: parent.width; section: root.section; controller: root.controller
        viewMode: root.viewMode; canChangeViewMode: root.controller?.canChangeSectionViewMode(root.section?.id) ?? true
    }

    Column {
        id: contentCol; anchors.top: headerItem.bottom; anchors.left: parent.left; anchors.right: parent.right
        anchors.topMargin: Theme.spacingXS; visible: !root.section?.collapsed; spacing: 2
        Repeater {
            model: ScriptModel { values: root.section?.items ?? []; objectProp: "id" }
            ResultItem {
                required property var modelData; required property int index
                width: parent?.width ?? 200; item: modelData
                isSelected: (root.startIndex + index) === root.controller?.selectedFlatIndex
                controller: root.controller; flatIndex: root.startIndex + index
                onClicked: root.itemClicked(root.startIndex + index)
                onRightClicked: (mouseX, mouseY) => { root.itemRightClicked(root.startIndex + index, modelData, mouseX, mouseY); }
            }
        }
    }
}
