import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    // Tailscale service instance
    TailscaleService {
        id: tsService
    }

    // Control Center integration
    ccWidgetIcon: tsService.isBusy ? "sync" : (tsService.connected ? "vpn_lock" : "vpn_key_off")
    ccWidgetPrimaryText: "Tailscale"
    ccWidgetSecondaryText: {
        if (!tsService.running)
            return "Disconnected"
        if (!tsService.connected)
            return "Connecting..."
        if (tsService.exitNodeName)
            return "Exit Node: " + tsService.exitNodeName
        return "Connected"
    }
    ccWidgetIsActive: tsService.connected

    onCcWidgetToggled: {
        tsService.toggleRunning()
    }

    // DankBar horizontal pill (for top/bottom bars)
    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DankIcon {
                name: tsService.connected ? "vpn_lock" : "vpn_key_off"
                color: tsService.connected ? Theme.primary : Theme.surfaceVariantText
                size: Theme.barIconSize(root.barThickness, -4)
                opacity: tsService.isBusy ? 0.5 : 1.0
                anchors.verticalCenter: parent.verticalCenter

                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.shortDuration
                        easing.type: Easing.InOutQuad
                    }
                }
            }

            StyledText {
                text: {
                    if (!tsService.running) return "Off"
                    if (tsService.exitNodeName) return tsService.exitNodeName
                    return "On"
                }
                color: tsService.connected ? Theme.primary : Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeMedium
                opacity: tsService.isBusy ? 0.5 : 1.0
                anchors.verticalCenter: parent.verticalCenter
                visible: text.length > 0
            }
        }
    }

    // DankBar vertical pill (for left/right bars)
    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS

            DankIcon {
                name: tsService.connected ? "vpn_lock" : "vpn_key_off"
                color: tsService.connected ? Theme.primary : Theme.surfaceVariantText
                size: Theme.barIconSize(root.barThickness, -4)
                opacity: tsService.isBusy ? 0.5 : 1.0
                anchors.horizontalCenter: parent.horizontalCenter

                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.shortDuration
                        easing.type: Easing.InOutQuad
                    }
                }
            }
        }
    }

    // Popout content
    popoutContent: Component {
        PopoutComponent {
            id: popout

            headerText: "Tailscale"
            detailsText: tsService.connected ? ("Connected" + (tsService.exitNodeName ? " via " + tsService.exitNodeName : "")) : "Disconnected"
            showCloseButton: true

            Column {
                width: parent.width
                spacing: Theme.spacingM

                // Main status and toggle
                Rectangle {
                    width: parent.width
                    height: 60
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingM

                        DankIcon {
                            name: tsService.connected ? "vpn_lock" : "vpn_key_off"
                            size: Theme.iconSize
                            color: tsService.connected ? Theme.primary : Theme.surfaceVariantText
                            Layout.alignment: Qt.AlignVCenter
                        }

                        Column {
                            spacing: 2
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter

                            StyledText {
                                text: "Connection"
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceText
                                font.weight: Font.Medium
                            }

                            StyledText {
                                text: tsService.running ? (tsService.connected ? "Active" : "Starting...") : "Inactive"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceTextMedium
                            }
                        }

                        Rectangle {
                            width: 100
                            height: 32
                            radius: 16
                            color: toggleArea.containsMouse ? (tsService.running ? Theme.errorHover : Theme.primaryHover) : (tsService.running ? Theme.error : Theme.primary)
                            Layout.alignment: Qt.AlignVCenter
                            opacity: tsService.isBusy ? 0.5 : 1.0

                            StyledText {
                                anchors.centerIn: parent
                                text: tsService.running ? "Disconnect" : "Connect"
                                color: Theme.onPrimary
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.Medium
                            }

                            MouseArea {
                                id: toggleArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: tsService.isBusy ? Qt.BusyCursor : Qt.PointingHandCursor
                                enabled: !tsService.isBusy
                                onClicked: tsService.toggleRunning()
                            }
                        }
                    }
                }

                // Exit node section
                Rectangle {
                    width: parent.width
                    visible: tsService.running
                    implicitHeight: exitNodeColumn.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh

                    Column {
                        id: exitNodeColumn
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        RowLayout {
                            width: parent.width
                            spacing: Theme.spacingS

                            StyledText {
                                text: "Exit Node: " + (tsService.exitNodeName || "None")
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceText
                                font.weight: Font.Medium
                                Layout.fillWidth: true
                            }

                            Rectangle {
                                height: 28
                                width: 100
                                radius: 14
                                color: disconnectArea.containsMouse ? Theme.errorHover : Theme.surfaceLight
                                visible: tsService.exitNodeName !== ""
                                Layout.alignment: Qt.AlignVCenter
                                opacity: tsService.isBusy ? 0.5 : 1.0

                                Row {
                                    anchors.centerIn: parent
                                    spacing: Theme.spacingXS

                                    DankIcon {
                                        name: "link_off"
                                        size: Theme.fontSizeSmall
                                        color: Theme.surfaceText
                                    }

                                    StyledText {
                                        text: "Disable"
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceText
                                        font.weight: Font.Medium
                                    }
                                }

                                MouseArea {
                                    id: disconnectArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: tsService.isBusy ? Qt.BusyCursor : Qt.PointingHandCursor
                                    enabled: !tsService.isBusy
                                    onClicked: tsService.disconnectExitNode()
                                }
                            }
                        }

                        Rectangle {
                            height: 1
                            width: parent.width
                            color: Theme.outline
                            opacity: 0.12
                        }

                        // Nodes list
                        DankFlickable {
                            width: parent.width
                            height: Math.min(200, nodesColumn.implicitHeight)
                            contentHeight: nodesColumn.implicitHeight
                            clip: true

                            Column {
                                id: nodesColumn
                                width: parent.width
                                spacing: Theme.spacingXS

                                Repeater {
                                    model: tsService.nodes

                                    delegate: Rectangle {
                                        required property var modelData

                                        width: parent.width
                                        height: 50
                                        radius: Theme.cornerRadius
                                        color: nodeArea.containsMouse ? Theme.primaryHoverLight : (modelData.exitNode ? Theme.primaryPressed : "transparent")
                                        border.width: modelData.exitNode ? 2 : 0
                                        border.color: modelData.exitNode ? Theme.primary : "transparent"
                                        opacity: tsService.isBusy ? 0.5 : 1.0

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: Theme.spacingM
                                            spacing: Theme.spacingS

                                            DankIcon {
                                                name: {
                                                    if (!modelData.online) return "cloud_off"
                                                    if (modelData.mullvad) return "shield"
                                                    if (modelData.os === "android" || modelData.os === "iOS") return "smartphone"
                                                    return "computer"
                                                }
                                                size: Theme.iconSize - 4
                                                color: modelData.exitNode ? Theme.primary : Theme.surfaceText
                                                Layout.alignment: Qt.AlignVCenter
                                            }

                                            Column {
                                                spacing: 2
                                                Layout.fillWidth: true
                                                Layout.alignment: Qt.AlignVCenter

                                                StyledText {
                                                    text: modelData.name
                                                    font.pixelSize: Theme.fontSizeMedium
                                                    color: modelData.exitNode ? Theme.primary : Theme.surfaceText
                                                    elide: Text.ElideRight
                                                }

                                                StyledText {
                                                    text: {
                                                        if (modelData.exitNode) return "Active Exit Node"
                                                        if (!modelData.online) return "Offline"
                                                        if (modelData.exitNodeOption) return "Available Exit Node"
                                                        return modelData.os || "Device"
                                                    }
                                                    font.pixelSize: Theme.fontSizeSmall
                                                    color: Theme.surfaceTextMedium
                                                }
                                            }
                                        }

                                        MouseArea {
                                            id: nodeArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: (tsService.isBusy || !modelData.exitNodeOption) ? Qt.ArrowCursor : Qt.PointingHandCursor
                                            enabled: !tsService.isBusy && modelData.exitNodeOption
                                            onClicked: {
                                                if (modelData.exitNode) {
                                                    tsService.disconnectExitNode()
                                                } else {
                                                    tsService.setExitNode(modelData.id)
                                                }
                                            }
                                        }
                                    }
                                }

                                Item {
                                    width: parent.width
                                    height: 100
                                    visible: tsService.nodes.length === 0

                                    Column {
                                        anchors.centerIn: parent
                                        spacing: Theme.spacingS

                                        DankIcon {
                                            name: "cloud_off"
                                            size: 32
                                            color: Theme.surfaceVariantText
                                            anchors.horizontalCenter: parent.horizontalCenter
                                        }

                                        StyledText {
                                            text: "No nodes available"
                                            font.pixelSize: Theme.fontSizeMedium
                                            color: Theme.surfaceVariantText
                                            anchors.horizontalCenter: parent.horizontalCenter
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Settings section
                Rectangle {
                    width: parent.width
                    visible: tsService.running
                    implicitHeight: settingsColumn.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh

                    Column {
                        id: settingsColumn
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        StyledText {
                            text: "Settings"
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceText
                            font.weight: Font.Medium
                        }

                        Rectangle {
                            height: 1
                            width: parent.width
                            color: Theme.outline
                            opacity: 0.12
                        }

                        // Accept DNS
                        SettingRow {
                            label: "Accept DNS"
                            checked: tsService.acceptDns
                            enabled: !tsService.isBusy
                            onToggled: tsService.setSetting("acceptDns", !tsService.acceptDns)
                        }

                        // Accept Routes
                        SettingRow {
                            label: "Accept Routes"
                            checked: tsService.acceptRoutes
                            enabled: !tsService.isBusy
                            onToggled: tsService.setSetting("acceptRoutes", !tsService.acceptRoutes)
                        }

                        // Allow LAN Access
                        SettingRow {
                            label: "Allow LAN Access"
                            checked: tsService.allowLanAccess
                            enabled: !tsService.isBusy
                            onToggled: tsService.setSetting("allowLanAccess", !tsService.allowLanAccess)
                        }

                        // Shields Up
                        SettingRow {
                            label: "Shields Up"
                            checked: tsService.shieldsUp
                            enabled: !tsService.isBusy
                            onToggled: tsService.setSetting("shieldsUp", !tsService.shieldsUp)
                        }

                        // SSH
                        SettingRow {
                            label: "SSH"
                            checked: tsService.runSsh
                            enabled: !tsService.isBusy
                            onToggled: tsService.setSetting("runSsh", !tsService.runSsh)
                        }
                    }
                }
            }
        }
    }

    popoutWidth: 400
    popoutHeight: 600
}
