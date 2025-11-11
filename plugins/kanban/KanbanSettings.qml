import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "kanban"

    function defaultTitle(key, fallback) {
        const value = pluginService?.loadPluginData(pluginId, key, "")
        if (value && value.length)
            return value
        return fallback
    }

    function resetBoard() {
        if (!pluginService)
            return
        const board = [
            { id: "todo", title: defaultTitle("todoTitle", "To Do"), cards: [] },
            { id: "inProgress", title: defaultTitle("inProgressTitle", "In Progress"), cards: [] },
            { id: "done", title: defaultTitle("doneTitle", "Done"), cards: [] }
        ]
        pluginService?.savePluginData(pluginId, "board", JSON.stringify(board))
        ToastService.showSuccess("Kanban board cleared")
        PluginService.pluginDataChanged(pluginId)
    }

    Column {
        width: parent.width
        spacing: Theme.spacingL

        StyledText {
            width: parent.width
            text: "Kanban Board"
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Font.Bold
            color: Theme.surfaceText
        }

        StyledText {
            width: parent.width
            text: "Customize column titles and reset your kanban state."
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }

        Rectangle {
            width: parent.width
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh
            border.width: 1
            border.color: Theme.outline

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingS

                StringSetting {
                    Layout.fillWidth: true
                    settingKey: "todoTitle"
                    label: "To Do column"
                    description: "Displayed name for the first column"
                    placeholder: "To Do"
                    defaultValue: "To Do"
                }

                StringSetting {
                    Layout.fillWidth: true
                    settingKey: "inProgressTitle"
                    label: "In Progress column"
                    description: "Displayed name for the in-progress column"
                    placeholder: "In Progress"
                    defaultValue: "In Progress"
                }

                StringSetting {
                    Layout.fillWidth: true
                    settingKey: "doneTitle"
                    label: "Done column"
                    description: "Displayed name for the completed column"
                    placeholder: "Done"
                    defaultValue: "Done"
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 56
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh
            border.width: 1
            border.color: Theme.outline

            RowLayout {
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingM

                DankIcon {
                    name: "refresh"
                    size: Theme.iconSize
                    color: Theme.primary
                    Layout.alignment: Qt.AlignVCenter
                }

                Column {
                    spacing: 2
                    Layout.alignment: Qt.AlignVCenter
                    Layout.fillWidth: true

                    StyledText {
                        text: "Reset Board"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Medium
                        color: Theme.surfaceText
                    }

                    StyledText {
                        text: "Remove all cards and restore empty columns"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceTextMedium
                    }
                }

                Rectangle {
                    width: 96
                    height: 36
                    radius: 18
                    color: Theme.error
                    Layout.alignment: Qt.AlignVCenter

                    StyledText {
                        anchors.centerIn: parent
                        text: "Clear"
                        color: Theme.onPrimary
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Medium
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: resetBoard()
                    }
                }
            }
        }

        StyledText {
            width: parent.width
            text: "Tip: Use Shift + Enter to add multi-line notes when editing a card."
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }
    }
}
