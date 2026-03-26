// TrayBridge.qml -- wraps Quickshell.Services.SystemTray
// Flattens tray items for WebChannel serialization.
//
// Fixed: icon is a string (not object with sub-properties),
// tooltipTitle/tooltipDescription are top-level properties (not tooltip.title),
// category enum mapping corrected (was reversed),
// scroll() passes bool for horizontal (not Qt.Horizontal enum).
//
// Added: showMenu(itemId) -- opens a native QML tray context menu.
// DBusMenuHandle cannot be serialized over WebChannel, so the menu must be
// rendered QML-side. The frontend calls showMenu() and a QML popup appears.

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.SystemTray

Scope {
    id: root

    // ======================================================================
    // Public properties (os.tray)
    // ======================================================================

    property bool ready: false

    property var items: []

    // ======================================================================
    // Required properties -- set by shell.qml
    // ======================================================================

    // The TrayMenuPopup component needs a reference to a parent window for
    // positioning the platform menu. shell.qml passes a reference to the
    // Bar surface's PanelWindow (or any visible surface window).
    property var menuParentWindow: null

    // ======================================================================
    // Signals
    // ======================================================================

    signal itemAdded(var item)
    signal itemRemoved(string itemId)
    signal itemUpdated(var item)

    // Emitted when a tray menu is opened/closed (for frontend UI feedback)
    signal menuOpened(string itemId)
    signal menuClosed(string itemId)

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

    // showMenu: Opens a native QML context menu for the given tray item.
    //
    // The frontend calls this when the user right-clicks a tray icon.
    // The menu is rendered entirely on the QML side using QsMenuOpener to
    // traverse the DBusMenuHandle tree. The frontend does NOT receive menu
    // data -- it simply triggers the popup.
    //
    // Uses StatusNotifierItem.display(parentWindow, x, y) which creates a
    // platform menu via PlatformMenuEntry at the given screen coordinates.
    // If menuParentWindow is not set, falls back to the QsMenuAnchor-based
    // TrayMenuPopup component.
    function showMenu(itemId) {
        var qsItem = _findQsItem(itemId)
        if (!qsItem) {
            console.warn("TrayBridge.showMenu: item not found:", itemId)
            return
        }
        if (!qsItem.hasMenu) {
            console.warn("TrayBridge.showMenu: item has no menu:", itemId)
            return
        }

        // Close any existing popup first
        _closeActivePopup()

        // Open the menu via the custom QML popup with QsMenuOpener.
        // We do NOT use StatusNotifierItem.display() because it requires a
        // direct PanelWindow reference for positioning, and the Bar surface
        // is a Variants (one PanelWindow per screen). The TrayMenuPopup
        // approach works universally: it creates a full-screen overlay on the
        // correct screen and positions the menu at the given coordinates.
        //
        // If in the future a direct PanelWindow reference is available (e.g.,
        // the frontend passes the screen name and we look up the right window),
        // we can add a display() path here.
        _openFallbackPopup(qsItem)
    }

    // showMenuAt: Opens menu at specific screen coordinates.
    // The frontend passes the click position from the tray icon.
    function showMenuAt(itemId, screenX, screenY) {
        root._menuX = screenX
        root._menuY = screenY
        showMenu(itemId)
    }

    // contextMenu: Legacy method -- returns null but triggers showMenu.
    // Kept for backward compatibility with frontends that call contextMenu().
    function contextMenu(itemId) {
        // DBusMenuHandle is a QObject, not serializable over WebChannel.
        // Call showMenu() to open a native QML popup instead.
        showMenu(itemId)
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
    // Private: menu position state
    // ======================================================================

    // Screen coordinates for the next menu open. Set by showMenuAt()
    // or defaulted to a reasonable position.
    property int _menuX: 0
    property int _menuY: 0

    // Track the active fallback popup for cleanup
    property var _activePopup: null

    function _closeActivePopup() {
        if (root._activePopup) {
            root._activePopup.close()
            root._activePopup.destroy()
            root._activePopup = null
        }
    }

    function _openFallbackPopup(qsItem) {
        if (!_trayMenuPopupComponent) {
            console.warn("TrayBridge: TrayMenuPopup component not available")
            return
        }
        var popup = _trayMenuPopupComponent.createObject(root, {
            trayItem: qsItem,
            screenX: root._menuX,
            screenY: root._menuY
        })
        if (!popup) {
            console.warn("TrayBridge: failed to create TrayMenuPopup")
            return
        }
        popup.closed.connect(function() {
            root.menuClosed(_getItemId(qsItem))
            if (root._activePopup === popup) {
                root._activePopup = null
            }
            popup.destroy()
        })
        root._activePopup = popup
        popup.open()
        root.menuOpened(_getItemId(qsItem))
    }

    // Lazy-load the TrayMenuPopup component
    property var _trayMenuPopupComponent: Component {
        TrayMenuPopup {}
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
            menu: null  // Menu data not serializable over WebChannel; use showMenu()
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

    // ======================================================================
    // Pull-data fallback: getData(key)
    // ======================================================================

    function getData(key) {
        if (key === "items") return JSON.stringify(root.items)
        return "{}"
    }

    // ======================================================================
    // Health check timer
    // ======================================================================

    Timer {
        interval: 3000
        running: true
        repeat: false
        onTriggered: {
            if (!root.ready) {
                console.warn("TrayBridge: HEALTH CHECK -- not ready after 3s")
            } else {
                console.info("TrayBridge: healthy")
            }
        }
    }

    Component.onCompleted: {
        _rebuildItems()
        // Tray is ready immediately -- may have no items and that's valid
        root.ready = true
    }
}
