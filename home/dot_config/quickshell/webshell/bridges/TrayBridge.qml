// TrayBridge.qml -- wraps Quickshell.Services.SystemTray
// Flattens tray items for WebChannel serialization.

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.SystemTray

Scope {
    id: root

    // ======================================================================
    // Public properties (os.tray)
    // ======================================================================

    property var items: []

    // ======================================================================
    // Signals
    // ======================================================================

    signal itemAdded(var item)
    signal itemRemoved(string itemId)
    signal itemUpdated(var item)

    // ======================================================================
    // Public methods (os.tray)
    // ======================================================================

    function activate(itemId) {
        var qsItem = _findQsItem(itemId)
        if (qsItem) qsItem.activate()
    }

    function secondaryActivate(itemId) {
        var qsItem = _findQsItem(itemId)
        if (qsItem) qsItem.secondaryActivate()
    }

    function contextMenu(itemId) {
        var qsItem = _findQsItem(itemId)
        if (!qsItem || !qsItem.hasMenu) return null

        var menu = _flattenMenu(qsItem.menu)
        root._menuCache[itemId] = menu

        root.items = root.items.map(function(item) {
            if (item.id === itemId) {
                return Object.assign({}, item, { menu: menu })
            }
            return item
        })

        return menu
    }

    function activateMenuItem(itemId, menuItemId) {
        var qsItem = _findQsItem(itemId)
        if (!qsItem) return

        var menuItem = _findMenuItemDeep(qsItem.menu, menuItemId)
        if (menuItem && menuItem.enabled) menuItem.activate()
    }

    function scroll(itemId, delta, orientation) {
        var qsItem = _findQsItem(itemId)
        if (qsItem) {
            qsItem.scroll(delta, orientation === "horizontal" ? Qt.Horizontal : Qt.Vertical)
        }
    }

    // ======================================================================
    // Private: tracking state
    // ======================================================================

    property var _lastItemIds: []
    property var _menuCache: ({})

    function _findQsItem(itemId) {
        if (!SystemTray.items?.values) return null
        return SystemTray.items.values.find(function(i) { return _getItemId(i) === itemId }) ?? null
    }

    function _getItemId(qsItem) {
        return (qsItem.id ?? "") + "/" + (qsItem.objectPath ?? "")
    }

    function _flattenIcon(icon) {
        if (!icon) return { name: "", themePath: null, pixmap: null }
        return {
            name: icon.name ?? "",
            themePath: icon.themePath ?? null,
            pixmap: icon.pixmapData ? {
                width: icon.pixmapData.width ?? 0,
                height: icon.pixmapData.height ?? 0,
                dataUrl: icon.pixmapData.dataUrl ?? ""
            } : null
        }
    }

    function _flattenTooltip(tooltip) {
        if (!tooltip) return null
        return {
            title: tooltip.title ?? "",
            description: tooltip.description ?? ""
        }
    }

    function _flattenMenuItem(menuItem) {
        if (!menuItem) return null
        var children = []
        if (menuItem.children) {
            for (var i = 0; i < menuItem.children.length; i++) {
                var child = _flattenMenuItem(menuItem.children[i])
                if (child) children.push(child)
            }
        }

        var type = "standard"
        if (menuItem.isSeparator) type = "separator"
        else if (menuItem.toggleType === "checkmark") type = "checkbox"
        else if (menuItem.toggleType === "radio") type = "radio"

        var toggleState = null
        if (type === "checkbox" || type === "radio") {
            toggleState = menuItem.toggleState === 1 ? "on" : (menuItem.toggleState === 0 ? "off" : "indeterminate")
        }

        return {
            id: menuItem.id ?? 0,
            type: type,
            label: menuItem.label ?? "",
            enabled: menuItem.enabled ?? true,
            visible: menuItem.visible ?? true,
            icon: menuItem.iconName ? { name: menuItem.iconName } : null,
            toggleState: toggleState,
            children: children
        }
    }

    function _flattenMenu(menu) {
        if (!menu || !menu.items) return null
        var items = []
        for (var i = 0; i < menu.items.length; i++) {
            var item = _flattenMenuItem(menu.items[i])
            if (item) items.push(item)
        }
        return { items: items }
    }

    function _findMenuItemDeep(menu, menuItemId) {
        if (!menu || !menu.items) return null
        for (var i = 0; i < menu.items.length; i++) {
            if (menu.items[i].id === menuItemId) return menu.items[i]
            if (menu.items[i].children) {
                var found = _findMenuItemDeep({ items: menu.items[i].children }, menuItemId)
                if (found) return found
            }
        }
        return null
    }

    function _mapStatus(status) {
        switch (status) {
            case 0: return "passive"
            case 1: return "active"
            case 2: return "attention"
            default: return "active"
        }
    }

    function _mapCategory(category) {
        switch (category) {
            case 0: return "application"
            case 1: return "communications"
            case 2: return "system"
            case 3: return "hardware"
            default: return "application"
        }
    }

    function _flattenItem(qsItem) {
        var itemId = _getItemId(qsItem)
        return {
            id: itemId,
            title: qsItem.title ?? "",
            status: _mapStatus(qsItem.status),
            category: _mapCategory(qsItem.category),
            icon: _flattenIcon(qsItem.icon),
            tooltip: _flattenTooltip(qsItem.tooltip),
            menu: root._menuCache[itemId] ?? null,
            hasMenu: qsItem.hasMenu ?? false
        }
    }

    function _rebuildItems() {
        if (!SystemTray.items?.values) {
            root.items = []
            return
        }
        var qsItems = SystemTray.items.values
        var newItems = qsItems.map(function(i) { return _flattenItem(i) })
        root.items = newItems

        var newIds = newItems.map(function(i) { return i.id })
        var oldIds = root._lastItemIds

        for (var i = 0; i < newIds.length; i++) {
            if (!oldIds.includes(newIds[i])) {
                var item = newItems.find(function(it) { return it.id === newIds[i] })
                if (item) root.itemAdded(item)
            } else {
                var item2 = newItems.find(function(it) { return it.id === newIds[i] })
                if (item2) root.itemUpdated(item2)
            }
        }
        for (var j = 0; j < oldIds.length; j++) {
            if (!newIds.includes(oldIds[j])) {
                root.itemRemoved(oldIds[j])
            }
        }
        root._lastItemIds = newIds
    }

    // ======================================================================
    // Private: watch for changes
    // ======================================================================

    Timer {
        id: rebuildDebounce
        interval: 50
        repeat: false
        onTriggered: root._rebuildItems()
    }

    Connections {
        target: SystemTray.items ?? null
        function onValuesChanged() { rebuildDebounce.restart() }
    }

    Component.onCompleted: {
        _rebuildItems()
    }
}
