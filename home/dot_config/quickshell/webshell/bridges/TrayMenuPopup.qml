// TrayMenuPopup.qml -- QML-side context menu for tray items.
//
// Renders a DBusMenu tree using QsMenuOpener. This is the fallback when
// StatusNotifierItem.display() is not usable (e.g., no parent window reference).
//
// The popup is a full-screen transparent PanelWindow on the overlay layer.
// Menu entries are rendered as a Column of rectangles with text, icons,
// separators, checkbox/radio states, and submenu indicators.
//
// Architecture: The frontend NEVER receives menu data. It calls
// TrayBridge.showMenu(itemId) and this popup appears on the QML side.
// When the user clicks a menu entry, QsMenuEntry.triggered() fires (which
// sends the click to the remote application via D-Bus) and the popup closes.

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.SystemTray

Scope {
    id: root

    // The tray item whose menu we are displaying
    required property var trayItem

    // Screen coordinates where the menu should appear
    property int screenX: 0
    property int screenY: 0

    signal closed()

    function open() {
        if (!root.trayItem || !root.trayItem.hasMenu) {
            root.closed()
            return
        }
        menuWindow.visible = true
    }

    function close() {
        menuWindow.visible = false
        root.closed()
    }

    // ======================================================================
    // Menu window: full-screen transparent overlay
    // ======================================================================

    PanelWindow {
        id: menuWindow

        visible: false
        color: "transparent"

        WlrLayershell.namespace: "webshell-tray-menu"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusiveZone: -1
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        anchors {
            top: true
            left: true
            right: true
            bottom: true
        }

        // Click outside menu to dismiss
        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }

        // ======================================================================
        // Menu content container
        // ======================================================================

        Rectangle {
            id: menuContainer

            // Position near the requested screen coordinates.
            // Clamp to keep the menu on-screen.
            x: Math.max(8, Math.min(root.screenX, menuWindow.width - width - 8))
            y: Math.max(8, Math.min(root.screenY, menuWindow.height - height - 8))

            width: menuColumn.width + 16
            height: menuColumn.height + 16

            radius: 8
            color: "#e0181818"
            border.color: "#40ffffff"
            border.width: 1

            // Prevent clicks inside the menu from dismissing it
            MouseArea {
                anchors.fill: parent
                onClicked: function(mouse) { mouse.accepted = true }
            }

            // ======================================================================
            // QsMenuOpener: reads the tray item's DBusMenuHandle tree
            // ======================================================================

            QsMenuOpener {
                id: menuOpener
                // StatusNotifierItem.menu is a DBusMenuHandle* (subclass of QsMenuHandle).
                // QsMenuOpener.menu accepts QsMenuHandle*.
                menu: root.trayItem ? root.trayItem.menu : null
            }

            // ======================================================================
            // Submenu stack for navigating into submenus
            // ======================================================================

            property var submenuStack: []
            property var currentOpener: menuOpener

            function pushSubmenu(entry) {
                if (!entry || !entry.hasChildren) return
                submenuStack.push(currentOpener)
                submenuOpener.menu = entry
                currentOpener = submenuOpener
            }

            function popSubmenu() {
                if (submenuStack.length === 0) return
                currentOpener = submenuStack.pop()
                if (currentOpener === menuOpener) {
                    submenuOpener.menu = null
                }
            }

            QsMenuOpener {
                id: submenuOpener
            }

            // ======================================================================
            // Menu items column
            // ======================================================================

            Column {
                id: menuColumn
                anchors.centerIn: parent
                width: 220
                spacing: 2

                // Header: tray item name
                Rectangle {
                    width: parent.width
                    height: 28
                    color: "transparent"
                    visible: menuContainer.submenuStack.length === 0

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.trayItem ? (root.trayItem.title || root.trayItem.id || "Menu") : "Menu"
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        color: "#80ffffff"
                        elide: Text.ElideRight
                        width: parent.width - 16
                    }
                }

                // Separator after header
                Rectangle {
                    width: parent.width - 16
                    height: 1
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: "#30ffffff"
                    visible: menuContainer.submenuStack.length === 0
                }

                // Back button for submenus
                Rectangle {
                    width: parent.width
                    height: 28
                    color: backArea.containsMouse ? "#20ffffff" : "transparent"
                    radius: 4
                    visible: menuContainer.submenuStack.length > 0

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: "< Back"
                        font.pixelSize: 12
                        color: "#c0ffffff"
                    }

                    MouseArea {
                        id: backArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: menuContainer.popSubmenu()
                    }
                }

                // Menu entries from QsMenuOpener
                Repeater {
                    // Use the active opener's children (root or submenu)
                    model: menuContainer.currentOpener ? menuContainer.currentOpener.children : null

                    delegate: Rectangle {
                        id: entryDelegate

                        required property var modelData

                        width: menuColumn.width
                        height: modelData.isSeparator ? 9 : 28
                        color: {
                            if (modelData.isSeparator) return "transparent"
                            if (!modelData.enabled) return "transparent"
                            return entryArea.containsMouse ? "#20ffffff" : "transparent"
                        }
                        radius: 4

                        // Separator
                        Rectangle {
                            visible: modelData.isSeparator
                            width: parent.width - 16
                            height: 1
                            anchors.centerIn: parent
                            color: "#30ffffff"
                        }

                        // Entry content (non-separator)
                        Row {
                            visible: !modelData.isSeparator
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6

                            // Checkbox / radio indicator
                            Text {
                                visible: modelData.buttonType !== 0  // QsMenuButtonType.None = 0
                                anchors.verticalCenter: parent.verticalCenter
                                font.pixelSize: 12
                                color: modelData.enabled ? "#c0ffffff" : "#60ffffff"
                                text: {
                                    if (modelData.buttonType === 1) {  // CheckBox
                                        return modelData.checkState === Qt.Checked ? "\u2611" : "\u2610"
                                    }
                                    if (modelData.buttonType === 2) {  // RadioButton
                                        return modelData.checkState === Qt.Checked ? "\u25C9" : "\u25CB"
                                    }
                                    return ""
                                }
                            }

                            // Icon
                            Image {
                                visible: modelData.icon !== ""
                                source: modelData.icon
                                width: 16
                                height: 16
                                sourceSize.width: 16
                                sourceSize.height: 16
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            // Label
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.text
                                font.pixelSize: 12
                                color: modelData.enabled ? "#e0ffffff" : "#60ffffff"
                                elide: Text.ElideRight
                                width: menuColumn.width - 50
                            }
                        }

                        // Submenu arrow
                        Text {
                            visible: !modelData.isSeparator && modelData.hasChildren
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: ">"
                            font.pixelSize: 12
                            color: "#80ffffff"
                        }

                        MouseArea {
                            id: entryArea
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !modelData.isSeparator && modelData.enabled
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

                            onClicked: {
                                if (modelData.hasChildren) {
                                    menuContainer.pushSubmenu(modelData)
                                    return
                                }
                                // Trigger the menu action -- this sends the click
                                // to the remote application via D-Bus
                                modelData.triggered()
                                root.close()
                            }
                        }
                    }
                }
            }
        }

        // Escape key closes menu
        Keys.onEscapePressed: root.close()
    }
}
