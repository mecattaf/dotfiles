pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

Item {
    id: root
    property var controller: null
    property int gridColumns: controller?.gridColumns ?? 4
    property var _visualRows: []
    property var _flatIndexToRowMap: ({})
    property var _cumulativeHeights: []

    signal itemRightClicked(int index, var item, real mouseX, real mouseY)

    function _rebuildVisualModel() {
        var sections = root.controller?.sections ?? [];
        var rows = []; var indexMap = {}; var cumHeights = []; var cumY = 0;
        for (var s = 0; s < sections.length; s++) {
            var section = sections[s]; var sectionId = section.id;
            cumHeights.push(cumY);
            rows.push({ _rowId: "h_" + sectionId, type: "header", section: section, sectionId: sectionId, height: 32 });
            cumY += 32;
            if (section.collapsed) continue;
            var versionTrigger = root.controller?.viewModeVersion ?? 0; void(versionTrigger);
            var mode = root.controller?.getSectionViewMode(sectionId) ?? "list";
            var items = section.items ?? []; var flatStartIndex = section.flatStartIndex ?? 0;
            if (mode === "list") {
                for (var i = 0; i < items.length; i++) {
                    var flatIdx = flatStartIndex + i; indexMap[flatIdx] = rows.length;
                    cumHeights.push(cumY);
                    rows.push({ _rowId: items[i].id, type: "list_item", item: items[i], flatIndex: flatIdx, sectionId: sectionId, height: 52 });
                    cumY += 52;
                }
            } else {
                var cols = root.gridColumns;
                var cellWidth = mode === "tile" ? Math.floor(root.width / 3) : Math.floor(root.width / root.gridColumns);
                var cellHeight = mode === "tile" ? cellWidth * 0.75 : cellWidth + 24;
                var numRows = Math.ceil(items.length / cols);
                for (var r = 0; r < numRows; r++) {
                    var rowItems = [];
                    for (var c = 0; c < cols; c++) {
                        var idx = r * cols + c; if (idx >= items.length) break;
                        var fi = flatStartIndex + idx; indexMap[fi] = rows.length;
                        rowItems.push({ item: items[idx], flatIndex: fi });
                    }
                    cumHeights.push(cumY);
                    rows.push({ _rowId: "gr_" + sectionId + "_" + r, type: "grid_row", items: rowItems, sectionId: sectionId, viewMode: mode, cols: cols, height: cellHeight });
                    cumY += cellHeight;
                }
            }
        }
        root._flatIndexToRowMap = indexMap; root._cumulativeHeights = cumHeights; root._visualRows = rows;
    }

    onGridColumnsChanged: Qt.callLater(_rebuildVisualModel)
    onWidthChanged: Qt.callLater(_rebuildVisualModel)

    Connections {
        target: root.controller
        function onSectionsChanged() { Qt.callLater(root._rebuildVisualModel); }
        function onViewModeVersionChanged() { Qt.callLater(root._rebuildVisualModel); }
        function onSearchModeChanged() { root._visualRows = []; root._cumulativeHeights = []; root._flatIndexToRowMap = {}; }
    }

    function resetScroll() { mainListView.contentY = mainListView.originY; }

    function ensureVisible(index) {
        if (index < 0 || !controller?.flatModel || index >= controller.flatModel.length) return;
        var entry = controller.flatModel[index]; if (!entry || entry.isHeader) return;
        var rowIndex = _flatIndexToRowMap[index]; if (rowIndex === undefined) return;
        mainListView.positionViewAtIndex(rowIndex, ListView.Contain);
        if (stickyHeader.visible && rowIndex < _cumulativeHeights.length) {
            var rowY = _cumulativeHeights[rowIndex];
            var scrollY = mainListView.contentY - mainListView.originY;
            if (rowY < scrollY + stickyHeader.height)
                mainListView.contentY = Math.max(mainListView.originY, rowY - stickyHeader.height + mainListView.originY);
        }
    }

    function getSelectedItemPosition() {
        var fallback = mapToItem(null, width / 2, height / 2);
        if (!controller?.flatModel || controller.selectedFlatIndex < 0) return fallback;
        return fallback;
    }

    Connections {
        target: root.controller
        function onSelectedFlatIndexChanged() {
            if (root.controller?.keyboardNavigationActive)
                Qt.callLater(() => root.ensureVisible(root.controller.selectedFlatIndex));
        }
    }

    DankListView {
        id: mainListView; anchors.fill: parent; clip: true
        scrollBarTopMargin: (root.controller?.sections?.length > 0) ? 32 : 0
        model: ScriptModel { values: root._visualRows; objectProp: "_rowId" }
        add: null; remove: null; displaced: null; move: null

        delegate: Item {
            id: delegateRoot
            required property var modelData; required property int index
            width: mainListView.width; height: modelData?.height ?? 52

            SectionHeader {
                anchors.fill: parent; visible: delegateRoot.modelData?.type === "header"
                section: delegateRoot.modelData?.section ?? null; controller: root.controller
                viewMode: { var vt = root.controller?.viewModeVersion ?? 0; void(vt);
                    return root.controller?.getSectionViewMode(delegateRoot.modelData?.sectionId ?? "") ?? "list"; }
                canChangeViewMode: root.controller?.canChangeSectionViewMode(delegateRoot.modelData?.sectionId ?? "") ?? false
                canCollapse: root.controller?.canCollapseSection(delegateRoot.modelData?.sectionId ?? "") ?? false
            }

            ResultItem {
                anchors.fill: parent; visible: delegateRoot.modelData?.type === "list_item"
                item: delegateRoot.modelData?.type === "list_item" ? (delegateRoot.modelData?.item ?? null) : null
                isSelected: delegateRoot.modelData?.type === "list_item" && (delegateRoot.modelData?.flatIndex ?? -1) === root.controller?.selectedFlatIndex
                controller: root.controller; flatIndex: delegateRoot.modelData?.type === "list_item" ? (delegateRoot.modelData?.flatIndex ?? -1) : -1
                onClicked: { if (root.controller && delegateRoot.modelData?.item) root.controller.executeItem(delegateRoot.modelData.item); }
                onRightClicked: (mouseX, mouseY) => { root.itemRightClicked(delegateRoot.modelData?.flatIndex ?? -1, delegateRoot.modelData?.item ?? null, mouseX, mouseY); }
            }

            Row {
                anchors.fill: parent; visible: delegateRoot.modelData?.type === "grid_row"
                Repeater {
                    model: delegateRoot.modelData?.type === "grid_row" ? (delegateRoot.modelData?.items ?? []) : []
                    Item {
                        id: gridCellDelegate; required property var modelData; required property int index
                        readonly property real cellWidth: delegateRoot.modelData?.viewMode === "tile" ? Math.floor(delegateRoot.width / 3) : Math.floor(delegateRoot.width / (delegateRoot.modelData?.cols ?? root.gridColumns))
                        width: cellWidth; height: delegateRoot.height
                        GridItem {
                            width: parent.width - 4; height: parent.height - 4; anchors.centerIn: parent
                            visible: delegateRoot.modelData?.viewMode === "grid"
                            item: gridCellDelegate.modelData?.item ?? null
                            isSelected: (gridCellDelegate.modelData?.flatIndex ?? -1) === root.controller?.selectedFlatIndex
                            controller: root.controller; flatIndex: gridCellDelegate.modelData?.flatIndex ?? -1
                            onClicked: { if (root.controller && gridCellDelegate.modelData?.item) root.controller.executeItem(gridCellDelegate.modelData.item); }
                            onRightClicked: (mouseX, mouseY) => { root.itemRightClicked(gridCellDelegate.modelData?.flatIndex ?? -1, gridCellDelegate.modelData?.item ?? null, mouseX, mouseY); }
                        }
                        TileItem {
                            width: parent.width - 4; height: parent.height - 4; anchors.centerIn: parent
                            visible: delegateRoot.modelData?.viewMode === "tile"
                            item: gridCellDelegate.modelData?.item ?? null
                            isSelected: (gridCellDelegate.modelData?.flatIndex ?? -1) === root.controller?.selectedFlatIndex
                            controller: root.controller; flatIndex: gridCellDelegate.modelData?.flatIndex ?? -1
                            onClicked: { if (root.controller && gridCellDelegate.modelData?.item) root.controller.executeItem(gridCellDelegate.modelData.item); }
                            onRightClicked: (mouseX, mouseY) => { root.itemRightClicked(gridCellDelegate.modelData?.flatIndex ?? -1, gridCellDelegate.modelData?.item ?? null, mouseX, mouseY); }
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        id: bottomShadow; anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        height: 24; z: 100
        visible: mainListView.contentHeight > mainListView.height && mainListView.contentY < mainListView.contentHeight - mainListView.height + mainListView.originY - 5
        gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 1.0; color: Theme.withAlpha(Theme.surfaceContainer, Theme.popupTransparency) }
        }
    }

    Rectangle {
        id: stickyHeader; anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
        height: 32; z: 101; color: Theme.withAlpha(Theme.surfaceContainer, Theme.popupTransparency)
        visible: stickyHeaderSection !== null
        readonly property var stickyHeaderSection: {
            var scrollY = mainListView.contentY - mainListView.originY; if (scrollY <= 0) return null;
            var rows = root._visualRows; var heights = root._cumulativeHeights;
            if (rows.length === 0 || heights.length === 0) return null;
            var lo = 0; var hi = rows.length - 1;
            while (lo < hi) { var mid = (lo + hi + 1) >> 1; if (mid < heights.length && heights[mid] <= scrollY) lo = mid; else hi = mid - 1; }
            for (var i = lo; i >= 0; i--) { if (rows[i].type === "header") return rows[i].section; }
            return null;
        }
        SectionHeader {
            width: parent.width; section: stickyHeader.stickyHeaderSection; controller: root.controller
            viewMode: root.controller?.getSectionViewMode(stickyHeader.stickyHeaderSection?.id) ?? "list"
            canChangeViewMode: root.controller?.canChangeSectionViewMode(stickyHeader.stickyHeaderSection?.id) ?? false
            canCollapse: root.controller?.canCollapseSection(stickyHeader.stickyHeaderSection?.id) ?? false
            isSticky: true
        }
    }

    Item {
        anchors.centerIn: parent
        visible: (!root.controller?.sections || root.controller.sections.length === 0) && !root.controller?.isFileSearching
        width: emptyCol.implicitWidth; height: emptyCol.implicitHeight
        Column {
            id: emptyCol; spacing: Theme.spacingM
            DankIcon { anchors.horizontalCenter: parent.horizontalCenter
                name: root.controller?.searchQuery?.length > 0 ? "search_off" : "search"
                size: 48; color: Theme.outlineButton }
            StyledText { anchors.horizontalCenter: parent.horizontalCenter
                text: root.controller?.searchQuery?.length > 0 ? I18n.tr("No results found") : I18n.tr("Type to search")
                font.pixelSize: Theme.fontSizeMedium; color: Theme.surfaceVariantText; horizontalAlignment: Text.AlignHCenter }
        }
    }
}
