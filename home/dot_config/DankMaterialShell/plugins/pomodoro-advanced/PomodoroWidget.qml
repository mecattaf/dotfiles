import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    // Pomodoro service instance
    PomodoroService {
        id: pomoService
    }

    // Control Center integration
    ccWidgetIcon: pomoService.icon.replace(/[\u{1F000}-\u{1F9FF}]/gu, "schedule")
    ccWidgetPrimaryText: "Pomodoro"
    ccWidgetSecondaryText: {
        if (!pomoService.running)
            return "Timer stopped"
        if (pomoService.status === "paused")
            return "Paused - " + pomoService.timeDisplay
        if (pomoService.phase === "work")
            return "Focus - " + pomoService.timeDisplay
        if (pomoService.phase === "break")
            return "Break - " + pomoService.timeDisplay
        return pomoService.timeDisplay
    }
    ccWidgetIsActive: pomoService.running && pomoService.status !== "paused"

    onCcWidgetToggled: {
        if (pomoService.running) {
            pomoService.stop()
        } else {
            pomoService.start()
        }
    }

    // DankBar horizontal pill (for top/bottom bars)
    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            StyledText {
                text: pomoService.icon
                font.pixelSize: Theme.barIconSize(root.barThickness, -2)
                anchors.verticalCenter: parent.verticalCenter
                opacity: pomoService.isBusy ? 0.5 : 1.0

                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.shortDuration
                        easing.type: Easing.InOutQuad
                    }
                }
            }

            StyledText {
                text: pomoService.running ? pomoService.timeDisplay : "Pomo"
                color: {
                    if (!pomoService.running) return Theme.surfaceVariantText
                    if (pomoService.status === "paused") return Theme.warning
                    if (pomoService.phase === "work") return Theme.primary
                    if (pomoService.phase === "break") return Theme.success
                    return Theme.surfaceText
                }
                font.pixelSize: Theme.fontSizeMedium
                font.weight: pomoService.running ? Font.Medium : Font.Normal
                opacity: pomoService.isBusy ? 0.5 : 1.0
                anchors.verticalCenter: parent.verticalCenter

                Behavior on color {
                    ColorAnimation {
                        duration: Theme.shortDuration
                    }
                }
            }

            // Progress indicator
            Rectangle {
                width: 40
                height: 4
                radius: 2
                color: Theme.surfaceContainerHigh
                anchors.verticalCenter: parent.verticalCenter
                visible: pomoService.running

                Rectangle {
                    width: parent.width * (pomoService.percentage / 100.0)
                    height: parent.height
                    radius: parent.radius
                    color: {
                        if (pomoService.status === "paused") return Theme.warning
                        if (pomoService.phase === "work") return Theme.primary
                        if (pomoService.phase === "break") return Theme.success
                        return Theme.surfaceText
                    }

                    Behavior on width {
                        NumberAnimation {
                            duration: Theme.shortDuration
                        }
                    }

                    Behavior on color {
                        ColorAnimation {
                            duration: Theme.shortDuration
                        }
                    }
                }
            }
        }
    }

    // DankBar vertical pill (for left/right bars)
    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS

            StyledText {
                text: pomoService.icon
                font.pixelSize: Theme.barIconSize(root.barThickness, -2)
                anchors.horizontalCenter: parent.horizontalCenter
                opacity: pomoService.isBusy ? 0.5 : 1.0

                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.shortDuration
                        easing.type: Easing.InOutQuad
                    }
                }
            }

            StyledText {
                text: pomoService.running ? pomoService.minutes.toString() : ""
                color: {
                    if (pomoService.status === "paused") return Theme.warning
                    if (pomoService.phase === "work") return Theme.primary
                    if (pomoService.phase === "break") return Theme.success
                    return Theme.surfaceText
                }
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                anchors.horizontalCenter: parent.horizontalCenter
                visible: pomoService.running
            }
        }
    }

    // Popout content
    popoutContent: Component {
        PopoutComponent {
            id: popout

            headerText: "Pomodoro Timer"
            detailsText: pomoService.getDisplayText()
            showCloseButton: true

            Column {
                width: parent.width
                spacing: Theme.spacingM

                // Main timer display
                Rectangle {
                    width: parent.width
                    height: 200
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh

                    Column {
                        anchors.centerIn: parent
                        spacing: Theme.spacingL

                        // Timer icon
                        StyledText {
                            text: pomoService.icon
                            font.pixelSize: 48
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        // Time display
                        StyledText {
                            text: pomoService.timeDisplay
                            font.pixelSize: 56
                            font.weight: Font.Bold
                            color: {
                                if (!pomoService.running) return Theme.surfaceText
                                if (pomoService.status === "paused") return Theme.warning
                                if (pomoService.phase === "work") return Theme.primary
                                if (pomoService.phase === "break") return Theme.success
                                return Theme.surfaceText
                            }
                            anchors.horizontalCenter: parent.horizontalCenter

                            Behavior on color {
                                ColorAnimation {
                                    duration: Theme.shortDuration
                                }
                            }
                        }

                        // Phase label
                        StyledText {
                            text: {
                                if (!pomoService.running) return "Not running"
                                if (pomoService.status === "paused") return "Paused"
                                if (pomoService.phase === "work") return "Focus Time"
                                if (pomoService.phase === "break") return "Break Time"
                                return ""
                            }
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceTextMedium
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        // Progress bar
                        Rectangle {
                            width: 250
                            height: 8
                            radius: 4
                            color: Theme.surfaceContainerHigher
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: pomoService.running

                            Rectangle {
                                width: parent.width * (pomoService.percentage / 100.0)
                                height: parent.height
                                radius: parent.radius
                                color: {
                                    if (pomoService.status === "paused") return Theme.warning
                                    if (pomoService.phase === "work") return Theme.primary
                                    if (pomoService.phase === "break") return Theme.success
                                    return Theme.surfaceText
                                }

                                Behavior on width {
                                    NumberAnimation {
                                        duration: 500
                                        easing.type: Easing.InOutQuad
                                    }
                                }
                            }
                        }

                        // Percentage text
                        StyledText {
                            text: pomoService.percentage + "%"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceTextMedium
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: pomoService.running
                        }
                    }
                }

                // Control buttons
                Rectangle {
                    width: parent.width
                    implicitHeight: controlsRow.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh

                    Row {
                        id: controlsRow
                        anchors.centerIn: parent
                        spacing: Theme.spacingM

                        // Start/Stop button
                        Rectangle {
                            width: 120
                            height: 48
                            radius: Theme.cornerRadius
                            color: {
                                if (startStopArea.containsMouse) {
                                    return pomoService.running ? Theme.errorHover : Theme.primaryHover
                                }
                                return pomoService.running ? Theme.error : Theme.primary
                            }
                            opacity: pomoService.isBusy ? 0.5 : 1.0

                            Row {
                                anchors.centerIn: parent
                                spacing: Theme.spacingS

                                DankIcon {
                                    name: pomoService.running ? "stop" : "play_arrow"
                                    size: Theme.iconSize - 4
                                    color: Theme.onPrimary
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                StyledText {
                                    text: pomoService.running ? "Stop" : "Start"
                                    color: Theme.onPrimary
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Font.Medium
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            MouseArea {
                                id: startStopArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: pomoService.isBusy ? Qt.BusyCursor : Qt.PointingHandCursor
                                enabled: !pomoService.isBusy
                                onClicked: {
                                    if (pomoService.running) {
                                        pomoService.stop()
                                    } else {
                                        pomoService.start()
                                    }
                                }
                            }
                        }

                        // Pause button
                        Rectangle {
                            width: 120
                            height: 48
                            radius: Theme.cornerRadius
                            color: pauseArea.containsMouse ? Theme.surfaceLight : Theme.surfaceContainer
                            opacity: pomoService.isBusy ? 0.5 : 1.0
                            visible: pomoService.running

                            Row {
                                anchors.centerIn: parent
                                spacing: Theme.spacingS

                                DankIcon {
                                    name: pomoService.status === "paused" ? "play_arrow" : "pause"
                                    size: Theme.iconSize - 4
                                    color: Theme.surfaceText
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                StyledText {
                                    text: pomoService.status === "paused" ? "Resume" : "Pause"
                                    color: Theme.surfaceText
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Font.Medium
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            MouseArea {
                                id: pauseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: pomoService.isBusy ? Qt.BusyCursor : Qt.PointingHandCursor
                                enabled: !pomoService.isBusy
                                onClicked: pomoService.togglePause()
                            }
                        }

                        // Restart button
                        Rectangle {
                            width: 48
                            height: 48
                            radius: Theme.cornerRadius
                            color: restartArea.containsMouse ? Theme.surfaceLight : Theme.surfaceContainer
                            opacity: pomoService.isBusy ? 0.5 : 1.0

                            DankIcon {
                                name: "refresh"
                                size: Theme.iconSize - 4
                                color: Theme.surfaceText
                                anchors.centerIn: parent
                            }

                            MouseArea {
                                id: restartArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: pomoService.isBusy ? Qt.BusyCursor : Qt.PointingHandCursor
                                enabled: !pomoService.isBusy
                                onClicked: pomoService.restart()
                            }
                        }
                    }
                }

                // Settings section
                Rectangle {
                    width: parent.width
                    implicitHeight: settingsColumn.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh

                    Column {
                        id: settingsColumn
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingM

                        StyledText {
                            text: "Timer Settings"
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

                        // Work time
                        Row {
                            width: parent.width
                            spacing: Theme.spacingS

                            DankIcon {
                                name: "work"
                                size: Theme.iconSize - 4
                                color: Theme.primary
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: "Work Time:"
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: pomoService.workTime + " minutes"
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.primary
                                font.weight: Font.Medium
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        // Break time
                        Row {
                            width: parent.width
                            spacing: Theme.spacingS

                            DankIcon {
                                name: "coffee"
                                size: Theme.iconSize - 4
                                color: Theme.success
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: "Break Time:"
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: pomoService.breakTime + " minutes"
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.success
                                font.weight: Font.Medium
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        StyledText {
                            text: "Configure work and break times using environment variables POMO_WORK_TIME and POMO_BREAK_TIME"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceTextMedium
                            wrapMode: Text.WordWrap
                            width: parent.width
                        }
                    }
                }

                // Tips section
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
                                name: "lightbulb"
                                size: Theme.iconSize - 4
                                color: Theme.warning
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: "Pomodoro Technique Tips"
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
                            text: "• Focus on one task during work periods\n• Take short breaks between work sessions\n• Use breaks to rest your eyes and stretch\n• After 4 pomodoros, take a longer 15-30 min break"
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

    popoutWidth: 400
    popoutHeight: 700
}
