import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import "./layouts.js" as Layouts

PluginSettings {
    id: root
    pluginId: "onscreenkeyboard"

    Column {
        width: parent.width
        spacing: Theme.spacingM

        // Header
        StyledText {
            width: parent.width
            text: "On-Screen Keyboard Configuration"
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Font.Bold
            color: Theme.surfaceText
        }

        // Layout selection
        Rectangle {
            width: parent.width
            implicitHeight: layoutColumn.implicitHeight + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            Column {
                id: layoutColumn
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingM

                Row {
                    spacing: Theme.spacingS

                    DankIcon {
                        name: "language"
                        size: Theme.iconSize - 4
                        color: Theme.primary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: "Keyboard Layout"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Medium
                        color: Theme.surfaceText
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Rectangle {
                    height: 1
                    width: parent.width
                    color: Theme.outline
                    opacity: 0.12
                }

                SelectionSetting {
                    settingKey: "layout"
                    label: "Layout"
                    description: "Choose your keyboard layout"
                    options: Object.keys(Layouts.byName).map(key => ({
                        label: `${Layouts.byName[key].name_short} - ${Layouts.byName[key].description}`,
                        value: key
                    }))
                    defaultValue: Layouts.defaultLayout
                }
            }
        }

        // Requirements info
        Rectangle {
            width: parent.width
            implicitHeight: reqColumn.implicitHeight + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            Column {
                id: reqColumn
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingS

                Row {
                    spacing: Theme.spacingS

                    DankIcon {
                        name: "settings"
                        size: Theme.iconSize - 4
                        color: Theme.warning
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: "Requirements"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Medium
                        color: Theme.surfaceText
                    }
                }

                Rectangle {
                    height: 1
                    width: parent.width
                    color: Theme.outline
                    opacity: 0.12
                }

                StyledText {
                    text: "This plugin requires ydotool to be installed and running.\n\nTo set up ydotool:\n1. Install: sudo pacman -S ydotool (Arch) or equivalent\n2. Enable service: sudo systemctl enable --now ydotoold\n3. Add user to input group: sudo usermod -aG input $USER\n4. Reboot or re-login for changes to take effect"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceTextMedium
                    wrapMode: Text.WordWrap
                    width: parent.width
                    lineHeight: 1.4
                }
            }
        }

        // Usage tips
        Rectangle {
            width: parent.width
            implicitHeight: tipsColumn.implicitHeight + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            Column {
                id: tipsColumn
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingS

                Row {
                    spacing: Theme.spacingS

                    DankIcon {
                        name: "info"
                        size: Theme.iconSize - 4
                        color: Theme.success
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: "Usage Tips"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Medium
                        color: Theme.surfaceText
                    }
                }

                Rectangle {
                    height: 1
                    width: parent.width
                    color: Theme.outline
                    opacity: 0.12
                }

                StyledText {
                    text: "• Add the OSK widget to your DankBar for quick access\n• Click the keyboard icon to toggle visibility\n• Use the pin button to keep the keyboard visible\n• Press Escape or click Hide to close the keyboard\n• All modifier keys are released when keyboard closes\n• Useful for touchscreen devices and accessibility"
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
