pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

Popup {
    id: root
    property var item: null
    property var controller: null
    property var searchField: null
    property var parentHandler: null
    signal hideRequested
    signal editAppRequested(var app)

    function hasContextMenuActions(spotlightItem) {
        if (!spotlightItem) return false;
        return spotlightItem.type === "app";
    }

    readonly property var desktopEntry: item?.data ?? null
    readonly property string appId: desktopEntry?.id || desktopEntry?.execString || ""
    readonly property bool isPinned: appId ? SessionData.isPinnedApp(appId) : false
    readonly property bool isRegularApp: item?.type === "app" && desktopEntry

    readonly property var menuItems: {
        var items = [];
        if (item?.type === "app") {
            items.push({ type: "item", icon: isPinned ? "keep_off" : "push_pin",
                text: isPinned ? I18n.tr("Unpin from Dock") : I18n.tr("Pin to Dock"), action: togglePin });
            if (isRegularApp) {
                items.push({ type: "item", icon: "visibility_off", text: I18n.tr("Hide App"), action: hideCurrentApp });
                items.push({ type: "item", icon: "edit", text: I18n.tr("Edit App"), action: editCurrentApp });
            }
            if (item?.actions && item.actions.length > 0) {
                items.push({ type: "separator" });
                for (var i = 0; i < item.actions.length; i++) {
                    items.push({ type: "item", icon: item.actions[i].icon || "play_arrow", text: item.actions[i].name || "", actionData: item.actions[i] });
                }
            }
            items.push({ type: "separator" });
            if (isRegularApp && SessionService.nvidiaCommand) {
                items.push({ type: "item", icon: "memory", text: I18n.tr("Launch on dGPU"), action: launchWithNvidia });
            }
            items.push({ type: "item", icon: "launch", text: I18n.tr("Launch"), action: launchApp });
        }
        return items;
    }

    function show(x, y, spotlightItem, fromKeyboard) {
        if (!spotlightItem?.data) return;
        item = spotlightItem; selectedMenuIndex = fromKeyboard ? 0 : -1; keyboardNavigation = fromKeyboard;
        if (parentHandler) parentHandler.enabled = false;
        Qt.callLater(() => {
            var parentW = parent?.width ?? 500; var parentH = parent?.height ?? 600;
            var posX = Math.min(x + 4, parentW - 200 - 8); var posY = Math.min(y + 4, parentH - 200 - 8);
            root.x = Math.max(8, posX); root.y = Math.max(8, posY); open();
        });
    }
    function hide() { if (parentHandler) parentHandler.enabled = true; close(); }
    function togglePin() { if (!appId) return; if (isPinned) SessionData.removePinnedApp(appId); else SessionData.addPinnedApp(appId); hide(); }
    function hideCurrentApp() { if (!appId) return; SessionData.hideApp(appId); controller?.performSearch(); hide(); }
    function editCurrentApp() { if (!desktopEntry) return; editAppRequested(desktopEntry); hide(); }
    function launchApp() { if (!desktopEntry) return; SessionService.launchDesktopEntry(desktopEntry); AppUsageHistoryData.addAppUsage(desktopEntry); controller?.itemExecuted(); hide(); }
    function launchWithNvidia() { if (!desktopEntry) return; SessionService.launchDesktopEntry(desktopEntry, true); AppUsageHistoryData.addAppUsage(desktopEntry); controller?.itemExecuted(); hide(); }
    function executeDesktopAction(actionData) { if (!desktopEntry || !actionData) return; SessionService.launchDesktopAction(desktopEntry, actionData.actionData || actionData); AppUsageHistoryData.addAppUsage(desktopEntry); controller?.itemExecuted(); hide(); }

    property int selectedMenuIndex: 0
    property bool keyboardNavigation: false
    readonly property int visibleItemCount: { var c = 0; for (var i = 0; i < menuItems.length; i++) { if (menuItems[i].type === "item") c++; } return c; }
    function selectNext() { if (visibleItemCount > 0) selectedMenuIndex = (selectedMenuIndex + 1) % visibleItemCount; }
    function selectPrevious() { if (visibleItemCount > 0) selectedMenuIndex = (selectedMenuIndex - 1 + visibleItemCount) % visibleItemCount; }
    function activateSelected() {
        var itemIndex = 0;
        for (var i = 0; i < menuItems.length; i++) {
            if (menuItems[i].type !== "item") continue;
            if (itemIndex === selectedMenuIndex) {
                if (menuItems[i].action) menuItems[i].action();
                else if (menuItems[i].actionData) executeDesktopAction(menuItems[i]);
                return;
            }
            itemIndex++;
        }
    }

    width: menuContainer.implicitWidth; height: menuContainer.implicitHeight; padding: 0
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside; modal: true; dim: false
    background: Item {}
    onOpened: Qt.callLater(() => keyboardHandler.forceActiveFocus())
    onClosed: { if (parentHandler) parentHandler.enabled = true; if (searchField?.visible) Qt.callLater(() => searchField.forceActiveFocus()); }

    contentItem: Item {
        id: keyboardHandler; focus: true; implicitWidth: menuContainer.implicitWidth; implicitHeight: menuContainer.implicitHeight
        Keys.onPressed: event => {
            switch (event.key) {
            case Qt.Key_Down: root.selectNext(); event.accepted = true; return;
            case Qt.Key_Up: root.selectPrevious(); event.accepted = true; return;
            case Qt.Key_Return: case Qt.Key_Enter: root.activateSelected(); event.accepted = true; return;
            case Qt.Key_Escape: case Qt.Key_Left: root.hide(); event.accepted = true; return;
            }
        }

        Rectangle {
            id: menuContainer; anchors.fill: parent
            implicitWidth: Math.max(180, menuColumn.implicitWidth + Theme.spacingS * 2)
            implicitHeight: menuColumn.implicitHeight + Theme.spacingS * 2
            color: Theme.withAlpha(Theme.surfaceContainer, Theme.popupTransparency)
            radius: Theme.cornerRadius; border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.08); border.width: 1

            Column {
                id: menuColumn; anchors.fill: parent; anchors.margins: Theme.spacingS; spacing: 1
                Repeater {
                    model: root.menuItems
                    Item {
                        id: menuItemDelegate; required property var modelData; required property int index
                        width: menuColumn.width; height: modelData.type === "separator" ? 5 : 32
                        readonly property int itemIndex: { var c = 0; for (var i = 0; i < index; i++) { if (root.menuItems[i].type === "item") c++; } return c; }
                        Rectangle {
                            visible: menuItemDelegate.modelData.type === "separator"; width: parent.width - Theme.spacingS * 2; height: parent.height
                            anchors.horizontalCenter: parent.horizontalCenter; color: "transparent"
                            Rectangle { anchors.centerIn: parent; width: parent.width; height: 1; color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.2) }
                        }
                        Rectangle {
                            visible: menuItemDelegate.modelData.type === "item"; width: parent.width; height: parent.height
                            radius: Theme.cornerRadius
                            color: root.keyboardNavigation && root.selectedMenuIndex === menuItemDelegate.itemIndex
                                ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2)
                                : itemMA.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12) : "transparent"
                            Row {
                                anchors.left: parent.left; anchors.leftMargin: Theme.spacingS; anchors.right: parent.right
                                anchors.rightMargin: Theme.spacingS; anchors.verticalCenter: parent.verticalCenter; spacing: Theme.spacingS
                                DankIcon { visible: (menuItemDelegate.modelData?.icon ?? "").length > 0; name: menuItemDelegate.modelData?.icon ?? ""
                                    size: Theme.iconSize - 2; color: Theme.surfaceText; opacity: 0.7; anchors.verticalCenter: parent.verticalCenter }
                                StyledText { text: menuItemDelegate.modelData.text || ""; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceText
                                    anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight }
                            }
                            MouseArea { id: itemMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onEntered: { root.keyboardNavigation = false; root.selectedMenuIndex = menuItemDelegate.itemIndex; }
                                onClicked: {
                                    var mi = menuItemDelegate.modelData;
                                    if (mi.action) mi.action();
                                    else if (mi.actionData) root.executeDesktopAction(mi);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
