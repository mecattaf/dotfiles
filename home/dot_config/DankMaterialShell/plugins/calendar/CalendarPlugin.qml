import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

import "./CalendarUtils.js" as CalendarUtils

PluginComponent {
    id: root

    property string viewMode: "month"
    property int monthOffset: 0
    property int weekOffset: 0
    property date today: new Date()
    readonly property int firstDayOfWeek: CalendarUtils.localeFirstDay(Qt.locale())
    readonly property date currentMonthDate: CalendarUtils.addMonths(CalendarUtils.startOfMonth(today), monthOffset)
    readonly property date currentWeekStart: CalendarUtils.addDays(CalendarUtils.startOfWeek(today, firstDayOfWeek), weekOffset * 7)
    readonly property var weekdayLabels: CalendarUtils.weekdayLabels(Qt.locale(), firstDayOfWeek)
    readonly property var monthCells: CalendarUtils.monthCells(currentMonthDate, firstDayOfWeek, today)
    readonly property var weekCells: CalendarUtils.weekCells(currentWeekStart, today, currentWeekStart.getMonth())

    readonly property string headerLabel: viewMode === "month"
                                         ? CalendarUtils.formatMonthYear(currentMonthDate, Qt.locale())
                                         : CalendarUtils.formatWeekRange(currentWeekStart, Qt.locale())

    readonly property string detailsLabel: Qt.formatDate(today, "dddd, MMMM d")

    readonly property real cellSize: 44

    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: root.refreshToday()
    }

    function refreshToday() {
        const now = new Date()
        if (!CalendarUtils.isSameDay(now, today)) {
            today = now
            if (viewMode === "month" && monthOffset === 0) {
                monthOffset = 0
            }
            if (viewMode === "week" && weekOffset === 0) {
                weekOffset = 0
            }
        } else {
            today = now
        }
    }

    function goToToday() {
        monthOffset = 0
        weekOffset = 0
    }

    function goPrevious() {
        if (viewMode === "month") {
            monthOffset -= 1
        } else {
            weekOffset -= 1
        }
    }

    function goNext() {
        if (viewMode === "month") {
            monthOffset += 1
        } else {
            weekOffset += 1
        }
    }

    function switchView(mode) {
        if (viewMode === mode)
            return
        viewMode = mode
        if (mode === "month") {
            monthOffset = 0
        } else {
            weekOffset = 0
        }
    }

    popoutWidth: 420
    popoutHeight: viewMode === "month" ? 440 : 320

    horizontalBarPill: Component {
        Rectangle {
            width: contentRow.implicitWidth + Theme.spacingM * 2
            height: parent.widgetThickness
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            Row {
                id: contentRow
                anchors.centerIn: parent
                spacing: Theme.spacingS

                DankIcon {
                    name: "calendar_month"
                    size: Theme.barIconSize(root.barThickness, -2)
                    color: Theme.surfaceText
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: Qt.formatDate(root.today, "MMM d")
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceText
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    verticalBarPill: Component {
        Rectangle {
            width: parent.widgetThickness
            height: contentColumn.implicitHeight + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            Column {
                id: contentColumn
                anchors.centerIn: parent
                spacing: Theme.spacingXS

                DankIcon {
                    name: "calendar_month"
                    size: Theme.barIconSize(root.barThickness, -2)
                    color: Theme.surfaceText
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    text: Qt.formatDate(root.today, "d")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }

    popoutContent: Component {
        PopoutComponent {
            headerText: "Calendar"
            detailsText: root.detailsLabel
            showCloseButton: true

            Column {
                width: parent.width
                spacing: Theme.spacingM

                RowLayout {
                    width: parent.width
                    spacing: Theme.spacingS

                    Rectangle {
                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 40
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHigh

                        DankIcon {
                            anchors.centerIn: parent
                            name: "chevron_left"
                            size: Theme.iconSize - 4
                            color: Theme.surfaceText
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.goPrevious()
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 80
                        Layout.preferredHeight: 40
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHigh

                        StyledText {
                            anchors.centerIn: parent
                            text: "Today"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceText
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.goToToday()
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 40
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHigh

                        DankIcon {
                            anchors.centerIn: parent
                            name: "chevron_right"
                            size: Theme.iconSize - 4
                            color: Theme.surfaceText
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.goNext()
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        Layout.alignment: Qt.AlignVCenter
                        horizontalAlignment: Text.AlignHCenter
                        text: root.headerLabel
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Font.Medium
                        color: Theme.surfaceText
                    }
                }

                Row {
                    spacing: Theme.spacingS
                    anchors.horizontalCenter: parent.horizontalCenter

                    Repeater {
                        model: [
                            { name: "Month", value: "month" },
                            { name: "Week", value: "week" }
                        ]

                        delegate: Rectangle {
                            property bool active: root.viewMode === modelData.value
                            width: 80
                            height: 32
                            radius: Theme.cornerRadius
                            color: active ? Theme.primary : Theme.surfaceContainerHigh

                            StyledText {
                                anchors.centerIn: parent
                                text: modelData.name
                                font.pixelSize: Theme.fontSizeSmall
                                color: active ? Theme.onPrimary : Theme.surfaceText
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.switchView(modelData.value)
                            }
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingS

                    Row {
                        spacing: Theme.spacingXS
                        anchors.horizontalCenter: parent.horizontalCenter
                        Repeater {
                            model: root.weekdayLabels
                            delegate: StyledText {
                                text: modelData.toUpperCase()
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.DemiBold
                                color: Theme.surfaceVariantText
                                width: root.cellSize
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }

                    Loader {
                        width: parent.width
                        sourceComponent: root.viewMode === "month" ? monthView : weekView
                    }
                }
            }
        }
    }

    Component {
        id: monthView
        GridLayout {
            columns: 7
            columnSpacing: Theme.spacingXS
            rowSpacing: Theme.spacingXS
            Layout.alignment: Qt.AlignHCenter

            Repeater {
                model: root.monthCells
                delegate: CalendarDayCell {
                    Layout.preferredWidth: root.cellSize
                    Layout.preferredHeight: root.cellSize
                    cellData: modelData
                }
            }
        }
    }

    Component {
        id: weekView
        RowLayout {
            spacing: Theme.spacingXS
            Layout.alignment: Qt.AlignHCenter

            Repeater {
                model: root.weekCells
                delegate: CalendarDayCell {
                    Layout.preferredWidth: root.cellSize
                    Layout.preferredHeight: root.cellSize
                    cellData: modelData
                }
            }
        }
    }
}
