import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins
import "./YdotoolService.qml" as YdotoolService

PluginComponent {
    id: root

    // Global variable to track keyboard visibility across instances
    PluginGlobalVar {
        id: keyboardOpen
        varName: "keyboardOpen"
        defaultValue: false
    }

    // Control Center integration
    ccWidgetIcon: "keyboard"
    ccWidgetPrimaryText: "On-Screen Keyboard"
    ccWidgetSecondaryText: keyboardOpen.value ? "Keyboard visible" : "Keyboard hidden"
    ccWidgetIsActive: keyboardOpen.value

    onCcWidgetToggled: {
        keyboardOpen.set(!keyboardOpen.value)
    }

    // DankBar horizontal pill (for top/bottom bars)
    horizontalBarPill: Component {
        Rectangle {
            width: pillContent.implicitWidth + Theme.spacingM * 2
            height: parent.widgetThickness
            radius: Theme.cornerRadius
            color: keyboardOpen.value ? Theme.primary : Theme.surfaceContainer

            Behavior on color {
                ColorAnimation { duration: Theme.shortDuration }
            }

            Row {
                id: pillContent
                anchors.centerIn: parent
                spacing: Theme.spacingS

                DankIcon {
                    name: "keyboard"
                    size: Theme.barIconSize(root.barThickness, -2)
                    color: keyboardOpen.value ? Theme.onPrimary : Theme.surfaceText
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: "OSK"
                    color: keyboardOpen.value ? Theme.onPrimary : Theme.surfaceText
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: keyboardOpen.value ? Font.Medium : Font.Normal
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: keyboardOpen.set(!keyboardOpen.value)
            }
        }
    }

    // DankBar vertical pill (for left/right bars)
    verticalBarPill: Component {
        Rectangle {
            width: parent.widgetThickness
            height: pillContent.implicitHeight + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: keyboardOpen.value ? Theme.primary : Theme.surfaceContainer

            Behavior on color {
                ColorAnimation { duration: Theme.shortDuration }
            }

            Column {
                id: pillContent
                anchors.centerIn: parent
                spacing: Theme.spacingXS

                DankIcon {
                    name: "keyboard"
                    size: Theme.barIconSize(root.barThickness, -2)
                    color: keyboardOpen.value ? Theme.onPrimary : Theme.surfaceText
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    text: "OSK"
                    color: keyboardOpen.value ? Theme.onPrimary : Theme.surfaceText
                    font.pixelSize: Theme.fontSizeSmall
                    rotation: 90
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: keyboardOpen.set(!keyboardOpen.value)
            }
        }
    }

    // Popout content - The main keyboard interface
    popoutContent: Component {
        PopoutComponent {
            id: popout

            headerText: "On-Screen Keyboard"
            detailsText: "Virtual keyboard with ydotool integration"
            showCloseButton: true

            Component.onCompleted: {
                // Release all keys when popout closes
                if (typeof closePopout !== "undefined") {
                    const originalClose = closePopout
                    closePopout = () => {
                        YdotoolService.releaseAllKeys()
                        keyboardOpen.set(false)
                        originalClose()
                    }
                }
            }

            Column {
                width: parent.width
                spacing: Theme.spacingM

                // Control buttons
                Rectangle {
                    width: parent.width
                    implicitHeight: controlRow.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh

                    Row {
                        id: controlRow
                        anchors.centerIn: parent
                        spacing: Theme.spacingM

                        // Pin button (keeps keyboard visible)
                        Rectangle {
                            width: 48
                            height: 48
                            radius: Theme.cornerRadius
                            color: {
                                if (pinArea.containsMouse) return Theme.primaryHover
                                return keyboardOpen.value ? Theme.primary : Theme.surfaceContainer
                            }

                            DankIcon {
                                name: "keep"
                                size: Theme.iconSize
                                color: keyboardOpen.value ? Theme.onPrimary : Theme.surfaceText
                                anchors.centerIn: parent
                            }

                            MouseArea {
                                id: pinArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: keyboardOpen.set(!keyboardOpen.value)
                            }
                        }

                        // Hide keyboard button
                        Rectangle {
                            width: 120
                            height: 48
                            radius: Theme.cornerRadius
                            color: hideArea.containsMouse ? Theme.surfaceLight : Theme.surfaceContainer

                            Row {
                                anchors.centerIn: parent
                                spacing: Theme.spacingS

                                DankIcon {
                                    name: "keyboard_hide"
                                    size: Theme.iconSize - 4
                                    color: Theme.surfaceText
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                StyledText {
                                    text: "Hide"
                                    color: Theme.surfaceText
                                    font.pixelSize: Theme.fontSizeMedium
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            MouseArea {
                                id: hideArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    YdotoolService.releaseAllKeys()
                                    if (typeof popout.closePopout !== "undefined") {
                                        popout.closePopout()
                                    }
                                    keyboardOpen.set(false)
                                }
                            }
                        }
                    }
                }

                // Keyboard layout
                Rectangle {
                    width: parent.width
                    implicitHeight: oskContent.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh

                    OskContent {
                        id: oskContent
                        anchors.centerIn: parent
                        pluginService: root.pluginService
                    }
                }

                // Info section
                Rectangle {
                    width: parent.width
                    implicitHeight: infoColumn.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh

                    Column {
                        id: infoColumn
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        Row {
                            spacing: Theme.spacingS

                            DankIcon {
                                name: "info"
                                size: Theme.iconSize - 4
                                color: Theme.primary
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: "Keyboard Tips"
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceText
                                font.weight: Font.Medium
                            }
                        }

                        Rectangle {
                            height: 1
                            width: parent.width
                            color: Theme.outline
                            opacity: 0.12
                        }

                        StyledText {
                            text: "• Double-tap Shift for Caps Lock\n• Click modifier keys (Ctrl, Alt) to toggle\n• Works with ydotool for touchscreen support\n• Pin the keyboard to keep it visible"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceTextMedium
                            wrapMode: Text.WordWrap
                            width: parent.width
                            lineHeight: 1.4
                        }
                    }
                }
            }
        }
    }

    popoutWidth: 1000
    popoutHeight: 550

    // Custom click action to show keyboard
    pillClickAction: (x, y, width, section, screen) => {
        keyboardOpen.set(!keyboardOpen.value)
        if (popoutService && keyboardOpen.value) {
            popoutService.togglePopout(x, y, width, section, screen, "onscreenkeyboard")
        }
    }
}
