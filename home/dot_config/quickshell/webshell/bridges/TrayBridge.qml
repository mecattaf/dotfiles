// TrayBridge.qml -- wraps Quickshell.Services.SystemTray
// Flattens tray items for WebChannel serialization.
//
// Fixed: icon is a string (not object with sub-properties),
// tooltipTitle/tooltipDescription are top-level properties (not tooltip.title),
// category enum mapping corrected (was reversed),
// scroll() passes bool for horizontal (not Qt.Horizontal enum).

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
        // NOTE: DBusMenuHandle is a QObject, not directly serializable.
        // Menu traversal via qsItem.menu.items is unreliable from QML.
        // The proper way to display tray menus is via QsMenuAnchor or
        // QsMenuOpener on the QML side. For WebChannel, we return null
        // and let the frontend use activate() / display() instead.
        // If full menu support is needed, it requires a QML-side popup.
        return null
    }

    function scroll(itemId, delta, orientation) {
        var qsItem = _findQsItem(itemId)
        if (qsItem) {
            // StatusNotifierItem.scroll(qint32 delta, bool horizontal)
            // Pass a boolean, NOT Qt.Horizontal enum.
            qsItem.scroll(delta, orientation === "horizontal")
        }
    }

    // ======================================================================
    // Private: tracking state
    // ======================================================================

    property var _lastItemIds: []

    function _findQsItem(itemId) {
        if (!SystemTray.items) return null
        var vals = SystemTray.items.values
        for (var i = 0; i < vals.length; i++) {
            if (_getItemId(vals[i]) === itemId) return vals[i]
        }
        return null
    }

    function _getItemId(qsItem) {
        // StatusNotifierItem has "id" property (Q_PROPERTY).
        // There is no "objectPath" property. Use id alone as the identifier.
        return qsItem.id ?? ""
    }

    function _mapStatus(status) {
        // Status enum: Passive=0, Active=1, NeedsAttention=2
        switch (status) {
            case 0: return "passive"
            case 1: return "active"
            case 2: return "attention"
            default: return "active"
        }
    }

    function _mapCategory(category) {
        // Category enum from item.hpp:
        // Hardware=0, SystemServices=1, ApplicationStatus=2, Communications=3
        // Previously this was reversed -- now corrected.
        switch (category) {
            case 0: return "hardware"
            case 1: return "system"
            case 2: return "application"
            case 3: return "communications"
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
            // icon is a QString (icon source string), NOT an object with sub-properties
            icon: qsItem.icon ?? "",
            // tooltipTitle and tooltipDescription are top-level Q_PROPERTYs,
            // NOT qsItem.tooltip.title / qsItem.tooltip.description
            tooltip: {
                title: qsItem.tooltipTitle ?? "",
                description: qsItem.tooltipDescription ?? ""
            },
            hasMenu: qsItem.hasMenu ?? false,
            onlyMenu: qsItem.onlyMenu ?? false,
            menu: null  // Menu data not serializable over WebChannel; use QsMenuAnchor
        }
    }

    function _rebuildItems() {
        if (!SystemTray.items) {
            root.items = []
            return
        }
        var qsItems = SystemTray.items.values
        var newItems = []
        for (var i = 0; i < qsItems.length; i++) {
            newItems.push(_flattenItem(qsItems[i]))
        }
        root.items = newItems

        var newIds = []
        for (var j = 0; j < newItems.length; j++) {
            newIds.push(newItems[j].id)
        }
        var oldIds = root._lastItemIds

        for (var k = 0; k < newIds.length; k++) {
            if (oldIds.indexOf(newIds[k]) < 0) {
                root.itemAdded(newItems[k])
            } else {
                root.itemUpdated(newItems[k])
            }
        }
        for (var m = 0; m < oldIds.length; m++) {
            if (newIds.indexOf(oldIds[m]) < 0) {
                root.itemRemoved(oldIds[m])
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
