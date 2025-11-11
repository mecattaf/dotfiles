Goal: This must extend the VPN service check, into a separate widget on the dms bar that lets us check the tailscale status

find attached a functionality that is for gnome qs but i want it instead for dms
this must be like the DankMaterialShell/Modules/DankBar/Widgets/Vpn.qml as found in the reference repo:
```

import QtQuick
import Quickshell
import qs.Common
import qs.Modules.Plugins
import qs.Services
import qs.Widgets

BasePill {
    id: root

    Ref {
        service: DMSNetworkService
    }

    property var popoutTarget: null
    property bool isHovered: clickArea.containsMouse

    signal toggleVpnPopup()

    content: Component {
        Item {
            implicitWidth: root.widgetThickness - root.horizontalPadding * 2
            implicitHeight: root.widgetThickness - root.horizontalPadding * 2

            DankIcon {
                id: icon

                name: DMSNetworkService.connected ? "vpn_lock" : "vpn_key_off"
                size: Theme.barIconSize(root.barThickness, -4)
                color: DMSNetworkService.connected ? Theme.primary : Theme.surfaceText
                opacity: DMSNetworkService.isBusy ? 0.5 : 1.0
                anchors.centerIn: parent

                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.shortDuration
                        easing.type: Easing.InOutQuad
                    }
                }
            }
        }
    }

    Loader {
        id: tooltipLoader
        active: false
        sourceComponent: DankTooltip {}
    }

    MouseArea {
        id: clickArea

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: DMSNetworkService.isBusy ? Qt.BusyCursor : Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton
        enabled: !DMSNetworkService.isBusy
        onPressed: {
            if (popoutTarget && popoutTarget.setTriggerPosition) {
                const globalPos = root.visualContent.mapToGlobal(0, 0)
                const currentScreen = parentScreen || Screen
                const pos = SettingsData.getPopupTriggerPosition(globalPos, currentScreen, barThickness, root.visualWidth)
                popoutTarget.setTriggerPosition(pos.x, pos.y, pos.width, section, currentScreen)
            }
            root.toggleVpnPopup();
        }
        onEntered: {
            if (root.parentScreen && !(popoutTarget && popoutTarget.shouldBeVisible)) {
                tooltipLoader.active = true
                if (tooltipLoader.item) {
                    let tooltipText = ""
                    if (!DMSNetworkService.connected) {
                        tooltipText = "VPN Disconnected"
                    } else {
                        const names = DMSNetworkService.activeNames || []
                        if (names.length <= 1) {
                            const name = names[0] || ""
                            const maxLength = 25
                            const displayName = name.length > maxLength ? name.substring(0, maxLength) + "..." : name
                            tooltipText = "VPN Connected • " + displayName
                        } else {
                            const name = names[0]
                            const maxLength = 20
                            const displayName = name.length > maxLength ? name.substring(0, maxLength) + "..." : name
                            tooltipText = "VPN Connected • " + displayName + " +" + (names.length - 1)
                        }
                    }

                    if (root.isVerticalOrientation) {
                        const globalPos = mapToGlobal(width / 2, height / 2)
                        const screenX = root.parentScreen ? root.parentScreen.x : 0
                        const screenY = root.parentScreen ? root.parentScreen.y : 0
                        const relativeY = globalPos.y - screenY
                        const tooltipX = root.axis?.edge === "left" ? (Theme.barHeight + SettingsData.dankBarSpacing + Theme.spacingXS) : (root.parentScreen.width - Theme.barHeight - SettingsData.dankBarSpacing - Theme.spacingXS)
                        const isLeft = root.axis?.edge === "left"
                        tooltipLoader.item.show(tooltipText, screenX + tooltipX, relativeY, root.parentScreen, isLeft, !isLeft)
                    } else {
                        const globalPos = mapToGlobal(width / 2, height)
                        const tooltipY = Theme.barHeight + SettingsData.dankBarSpacing + Theme.spacingXS
                        tooltipLoader.item.show(tooltipText, globalPos.x, tooltipY, root.parentScreen, false, false)
                    }
                }
            }
        }
        onExited: {
            if (tooltipLoader.item) {
                tooltipLoader.item.hide()
            }
            tooltipLoader.active = false
        }
    }
}
```


Modules/DankBar/Popouts/VpnPopout.qml
```
// No external details import; content inlined for consistency

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.Widgets

DankPopout {
    id: root

    layerNamespace: "dms:vpn"

    Ref {
        service: DMSNetworkService
    }

    property bool wasVisible: false

    onShouldBeVisibleChanged: {
        if (shouldBeVisible && !wasVisible) {
            DMSNetworkService.getState()
        }
        wasVisible = shouldBeVisible
    }

    property var triggerScreen: null

    function setTriggerPosition(x, y, width, section, screen) {
        triggerX = x;
        triggerY = y;
        triggerWidth = width;
        triggerSection = section;
        triggerScreen = screen;
    }

    popupWidth: 360
    popupHeight: Math.min(Screen.height - 100, contentLoader.item ? contentLoader.item.implicitHeight : 260)
    triggerX: Screen.width - 380 - Theme.spacingL
    triggerY: Theme.barHeight - 4 + SettingsData.dankBarSpacing
    triggerWidth: 70
    positioning: ""
    screen: triggerScreen
    shouldBeVisible: false
    visible: shouldBeVisible

    content: Component {
        Rectangle {
            id: content

            implicitHeight: contentColumn.height + Theme.spacingL * 2
            color: Theme.withAlpha(Theme.surfaceContainer, Theme.popupTransparency)
            radius: Theme.cornerRadius
            border.color: Theme.outlineMedium
            border.width: 0
            antialiasing: true
            smooth: true
            focus: true
            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                    root.close();
                    event.accepted = true;
                }
            }

            // Outer subtle shadow rings to match BatteryPopout
            Rectangle {
                anchors.fill: parent
                anchors.margins: -3
                color: "transparent"
                radius: parent.radius + 3
                border.color: Qt.rgba(0, 0, 0, 0.05)
                border.width: 0
                z: -3
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: -2
                color: "transparent"
                radius: parent.radius + 2
                border.color: Theme.shadowMedium
                border.width: 0
                z: -2
            }

            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.color: Theme.outlineStrong
                border.width: 0
                radius: parent.radius
                z: -1
            }

            Column {
                id: contentColumn

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.spacingL
                spacing: Theme.spacingM

                Item {
                    width: parent.width
                    height: 32

                    StyledText {
                        text: I18n.tr("VPN Connections")
                        font.pixelSize: Theme.fontSizeLarge
                        color: Theme.surfaceText
                        font.weight: Font.Medium
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    // Close button (matches BatteryPopout)
                    Rectangle {
                        width: 32
                        height: 32
                        radius: 16
                        color: closeArea.containsMouse ? Theme.errorHover : "transparent"
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter

                        DankIcon {
                            anchors.centerIn: parent
                            name: "close"
                            size: Theme.iconSize - 4
                            color: closeArea.containsMouse ? Theme.error : Theme.surfaceText
                        }

                        MouseArea {
                            id: closeArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onPressed: root.close()
                        }

                    }

                }

                // Inlined VPN details
                Rectangle {
                    id: vpnDetail

                    width: parent.width
                    implicitHeight: detailsColumn.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                    border.color: Theme.outlineStrong
                    border.width: 0
                    clip: true

                    Column {
                        id: detailsColumn

                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        RowLayout {
                            spacing: Theme.spacingS
                            width: parent.width

                            StyledText {
                                text: {
                                    if (!DMSNetworkService.connected) {
                                        return "Active: None";
                                    }

                                    const names = DMSNetworkService.activeNames || [];
                                    if (names.length <= 1) {
                                        return "Active: " + (names[0] || "VPN");
                                    }

                                    return "Active: " + names[0] + " +" + (names.length - 1);
                                }
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceText
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                                wrapMode: Text.NoWrap
                                Layout.fillWidth: true
                                Layout.maximumWidth: parent.width - 140
                            }

                            // Removed Quick Connect for clarity
                            Item {
                                width: 1
                                height: 1
                            }

                            // Disconnect all (shown only when any active)
                            Rectangle {
                                height: 28
                                radius: 14
                                color: discAllArea.containsMouse ? Theme.errorHover : Theme.surfaceLight
                                visible: DMSNetworkService.connected
                                width: 130
                                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                                border.width: 0
                                border.color: Theme.outlineLight
                                opacity: DMSNetworkService.isBusy ? 0.5 : 1.0

                                Row {
                                    anchors.centerIn: parent
                                    spacing: Theme.spacingXS

                                    DankIcon {
                                        name: "link_off"
                                        size: Theme.fontSizeSmall
                                        color: Theme.surfaceText
                                    }

                                    StyledText {
                                        text: I18n.tr("Disconnect")
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceText
                                        font.weight: Font.Medium
                                    }

                                }

                                MouseArea {
                                    id: discAllArea

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: DMSNetworkService.isBusy ? Qt.BusyCursor : Qt.PointingHandCursor
                                    enabled: !DMSNetworkService.isBusy
                                    onClicked: DMSNetworkService.disconnectAllActive()
                                }

                            }

                        }

                        Rectangle {
                            height: 1
                            width: parent.width
                            color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.12)
                        }

                        DankFlickable {
                            width: parent.width
                            height: 160
                            contentHeight: listCol.height
                            clip: true

                            Column {
                                id: listCol

                                width: parent.width
                                spacing: Theme.spacingXS

                                Item {
                                    width: parent.width
                                    height: DMSNetworkService.profiles.length === 0 ? 120 : 0
                                    visible: height > 0

                                    Column {
                                        anchors.centerIn: parent
                                        spacing: Theme.spacingS

                                        DankIcon {
                                            name: "playlist_remove"
                                            size: 36
                                            color: Theme.surfaceVariantText
                                            anchors.horizontalCenter: parent.horizontalCenter
                                        }

                                        StyledText {
                                            text: I18n.tr("No VPN profiles found")
                                            font.pixelSize: Theme.fontSizeMedium
                                            color: Theme.surfaceVariantText
                                            anchors.horizontalCenter: parent.horizontalCenter
                                        }

                                        StyledText {
                                            text: I18n.tr("Add a VPN in NetworkManager")
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceVariantText
                                            anchors.horizontalCenter: parent.horizontalCenter
                                        }

                                    }

                                }

                                Repeater {
                                    model: DMSNetworkService.profiles

                                    delegate: Rectangle {
                                        required property var modelData

                                        width: parent ? parent.width : 300
                                        height: 50
                                        radius: Theme.cornerRadius
                                        color: rowArea.containsMouse ? Theme.primaryHoverLight : (DMSNetworkService.isActiveUuid(modelData.uuid) ? Theme.primaryPressed : Theme.surfaceLight)
                                        border.width: DMSNetworkService.isActiveUuid(modelData.uuid) ? 2 : 1
                                        border.color: DMSNetworkService.isActiveUuid(modelData.uuid) ? Theme.primary : Theme.outlineLight
                                        opacity: DMSNetworkService.isBusy ? 0.5 : 1.0

                                        RowLayout {
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.margins: Theme.spacingM
                                            spacing: Theme.spacingS

                                            DankIcon {
                                                name: DMSNetworkService.isActiveUuid(modelData.uuid) ? "vpn_lock" : "vpn_key_off"
                                                size: Theme.iconSize - 4
                                                color: DMSNetworkService.isActiveUuid(modelData.uuid) ? Theme.primary : Theme.surfaceText
                                                Layout.alignment: Qt.AlignVCenter
                                            }

                                            Column {
                                                spacing: 2
                                                Layout.alignment: Qt.AlignVCenter
                                                Layout.fillWidth: true

                                                StyledText {
                                                    text: modelData.name
                                                    font.pixelSize: Theme.fontSizeMedium
                                                    color: DMSNetworkService.isActiveUuid(modelData.uuid) ? Theme.primary : Theme.surfaceText
                                                    elide: Text.ElideRight
                                                    wrapMode: Text.NoWrap
                                                    width: parent.width
                                                }

                                                StyledText {
                                                    text: {
                                                        if (modelData.type === "wireguard") {
                                                            return "WireGuard";
                                                        }

                                                        const svc = modelData.serviceType || "";
                                                        if (svc.indexOf("openvpn") !== -1) {
                                                            return "OpenVPN";
                                                        }

                                                        if (svc.indexOf("wireguard") !== -1) {
                                                            return "WireGuard (plugin)";
                                                        }

                                                        if (svc.indexOf("openconnect") !== -1) {
                                                            return "OpenConnect";
                                                        }

                                                        if (svc.indexOf("fortissl") !== -1 || svc.indexOf("forti") !== -1) {
                                                            return "Fortinet";
                                                        }

                                                        if (svc.indexOf("strongswan") !== -1) {
                                                            return "IPsec (strongSwan)";
                                                        }

                                                        if (svc.indexOf("libreswan") !== -1) {
                                                            return "IPsec (Libreswan)";
                                                        }

                                                        if (svc.indexOf("l2tp") !== -1) {
                                                            return "L2TP/IPsec";
                                                        }

                                                        if (svc.indexOf("pptp") !== -1) {
                                                            return "PPTP";
                                                        }

                                                        if (svc.indexOf("vpnc") !== -1) {
                                                            return "Cisco (vpnc)";
                                                        }

                                                        if (svc.indexOf("sstp") !== -1) {
                                                            return "SSTP";
                                                        }

                                                        if (svc) {
                                                            const parts = svc.split('.');
                                                            return parts[parts.length - 1];
                                                        }
                                                        return "VPN";
                                                    }
                                                    font.pixelSize: Theme.fontSizeSmall
                                                    color: Theme.surfaceTextMedium
                                                }

                                            }

                                            Item {
                                                Layout.fillWidth: true
                                                height: 1
                                            }

                                        }

                                        MouseArea {
                                            id: rowArea

                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: DMSNetworkService.isBusy ? Qt.BusyCursor : Qt.PointingHandCursor
                                            enabled: !DMSNetworkService.isBusy
                                            onClicked: DMSNetworkService.toggle(modelData.uuid)
                                        }

                                    }

                                }

                                Item {
                                    height: 1
                                    width: 1
                                }

                            }

                        }

                    }

                }

            }

        }

    }

}
```

Modules/ControlCenter/BuiltinPlugins/VpnWidget.qml
```
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    Ref {
        service: DMSNetworkService
    }


    ccWidgetIcon: DMSNetworkService.isBusy ? "sync" : (DMSNetworkService.connected ? "vpn_lock" : "vpn_key_off")
    ccWidgetPrimaryText: "VPN"
    ccWidgetSecondaryText: {
        if (!DMSNetworkService.connected)
            return "Disconnected"
        const names = DMSNetworkService.activeNames || []
        if (names.length <= 1)
            return names[0] || "Connected"
        return names[0] + " +" + (names.length - 1)
    }
    ccWidgetIsActive: DMSNetworkService.connected

    onCcWidgetToggled: {
        DMSNetworkService.toggleVpn()
    }

    ccDetailContent: Component {
        Rectangle {
            id: detailRoot
            implicitHeight: detailColumn.implicitHeight + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)

            Column {
                id: detailColumn
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingS

                RowLayout {
                    spacing: Theme.spacingS
                    width: parent.width

                    StyledText {
                        text: {
                            if (!DMSNetworkService.connected)
                                return "Active: None"
                            const names = DMSNetworkService.activeNames || []
                            if (names.length <= 1)
                                return "Active: " + (names[0] || "VPN")
                            return "Active: " + names[0] + " +" + (names.length - 1)
                        }
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceText
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                        wrapMode: Text.NoWrap
                        Layout.fillWidth: true
                        Layout.maximumWidth: parent.width - 120
                    }

                    Rectangle {
                        height: 28
                        radius: 14
                        color: discAllArea.containsMouse ? Theme.errorHover : Theme.surfaceLight
                        visible: DMSNetworkService.connected
                        width: 110
                        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                        opacity: DMSNetworkService.isBusy ? 0.5 : 1.0

                        Row {
                            anchors.centerIn: parent
                            spacing: Theme.spacingXS

                            DankIcon {
                                name: "link_off"
                                size: Theme.fontSizeSmall
                                color: Theme.surfaceText
                            }

                            StyledText {
                                text: I18n.tr("Disconnect")
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceText
                                font.weight: Font.Medium
                            }
                        }

                        MouseArea {
                            id: discAllArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: DMSNetworkService.isBusy ? Qt.BusyCursor : Qt.PointingHandCursor
                            enabled: !DMSNetworkService.isBusy
                            onClicked: DMSNetworkService.disconnectAllActive()
                        }
                    }
                }

                Rectangle {
                    height: 1
                    width: parent.width
                    color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.12)
                }

                DankFlickable {
                    width: parent.width
                    height: 160
                    contentHeight: listCol.height
                    clip: true

                    Column {
                        id: listCol
                        width: parent.width
                        spacing: Theme.spacingXS

                        Item {
                            width: parent.width
                            height: DMSNetworkService.profiles.length === 0 ? 120 : 0
                            visible: height > 0

                            Column {
                                anchors.centerIn: parent
                                spacing: Theme.spacingS

                                DankIcon {
                                    name: "playlist_remove"
                                    size: 36
                                    color: Theme.surfaceVariantText
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }

                                StyledText {
                                    text: I18n.tr("No VPN profiles found")
                                    font.pixelSize: Theme.fontSizeMedium
                                    color: Theme.surfaceVariantText
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }

                                StyledText {
                                    text: I18n.tr("Add a VPN in NetworkManager")
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                            }
                        }

                        Repeater {
                            model: DMSNetworkService.profiles

                            delegate: Rectangle {
                                required property var modelData

                                width: parent ? parent.width : 300
                                height: 50
                                radius: Theme.cornerRadius
                                color: rowArea.containsMouse ? Theme.primaryHoverLight : (DMSNetworkService.isActiveUuid(modelData.uuid) ? Theme.primaryPressed : Theme.surfaceLight)
                                border.width: DMSNetworkService.isActiveUuid(modelData.uuid) ? 2 : 1
                                border.color: DMSNetworkService.isActiveUuid(modelData.uuid) ? Theme.primary : Theme.outlineLight
                                opacity: DMSNetworkService.isBusy ? 0.5 : 1.0

                                RowLayout {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.margins: Theme.spacingM
                                    spacing: Theme.spacingS

                                    DankIcon {
                                        name: DMSNetworkService.isActiveUuid(modelData.uuid) ? "vpn_lock" : "vpn_key_off"
                                        size: Theme.iconSize - 4
                                        color: DMSNetworkService.isActiveUuid(modelData.uuid) ? Theme.primary : Theme.surfaceText
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    Column {
                                        spacing: 2
                                        Layout.alignment: Qt.AlignVCenter
                                        Layout.fillWidth: true

                                        StyledText {
                                            text: modelData.name
                                            font.pixelSize: Theme.fontSizeMedium
                                            color: DMSNetworkService.isActiveUuid(modelData.uuid) ? Theme.primary : Theme.surfaceText
                                            elide: Text.ElideRight
                                            wrapMode: Text.NoWrap
                                            width: parent.width
                                        }

                                        StyledText {
                                            text: {
                                                if (modelData.type === "wireguard")
                                                    return "WireGuard"
                                                const svc = modelData.serviceType || ""
                                                if (svc.indexOf("openvpn") !== -1)
                                                    return "OpenVPN"
                                                if (svc.indexOf("wireguard") !== -1)
                                                    return "WireGuard (plugin)"
                                                if (svc.indexOf("openconnect") !== -1)
                                                    return "OpenConnect"
                                                if (svc.indexOf("fortissl") !== -1 || svc.indexOf("forti") !== -1)
                                                    return "Fortinet"
                                                if (svc.indexOf("strongswan") !== -1)
                                                    return "IPsec (strongSwan)"
                                                if (svc.indexOf("libreswan") !== -1)
                                                    return "IPsec (Libreswan)"
                                                if (svc.indexOf("l2tp") !== -1)
                                                    return "L2TP/IPsec"
                                                if (svc.indexOf("pptp") !== -1)
                                                    return "PPTP"
                                                if (svc.indexOf("vpnc") !== -1)
                                                    return "Cisco (vpnc)"
                                                if (svc.indexOf("sstp") !== -1)
                                                    return "SSTP"
                                                if (svc)
                                                    return svc.split('.').pop()
                                                return "VPN"
                                            }
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceTextMedium
                                        }
                                    }

                                    Item {
                                        Layout.fillWidth: true
                                    }
                                }

                                MouseArea {
                                    id: rowArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: DMSNetworkService.isBusy ? Qt.BusyCursor : Qt.PointingHandCursor
                                    enabled: !DMSNetworkService.isBusy
                                    onClicked: DMSNetworkService.toggle(modelData.uuid)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
```
