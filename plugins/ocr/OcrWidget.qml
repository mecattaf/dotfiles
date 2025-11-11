import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property string currentLang: pluginData.language || "eng"
    property bool quietMode: pluginData.quietMode || false
    property bool showIcon: pluginData.showIcon !== undefined ? pluginData.showIcon : true
    property bool showLabel: pluginData.showLabel !== undefined ? pluginData.showLabel : true
    property string customIcon: pluginData.customIcon || "󰕸"
    property var availableLanguages: []

    Component.onCompleted: {
        loadAvailableLanguages()
    }

    function loadAvailableLanguages() {
        Proc.runCommand(
            "ocr.listLanguages",
            ["tesseract", "--list-langs"],
            (stdout, exitCode) => {
                if (exitCode === 0) {
                    const lines = stdout.trim().split("\n")
                    // Skip first line (header) and filter out empty lines and "osd"
                    availableLanguages = lines.slice(1)
                        .map(lang => lang.trim())
                        .filter(lang => lang.length > 0 && lang !== "osd")
                } else {
                    availableLanguages = ["eng"]
                }
            }
        )
    }

    function runOcr() {
        const scriptPath = Qt.resolvedUrl("./ocr.sh").toString().replace("file://", "")
        let command = [scriptPath, "--lang", currentLang]

        if (quietMode) {
            command.push("--no-notify")
        }

        Quickshell.execDetached(["sh", "-c", command.join(" ")])
    }

    function showLanguagePopout(x, y, width, section, screen) {
        if (typeof popoutService !== "undefined" && popoutService) {
            popoutService.showCustomPopout(x, y, width, section, screen, languagePopoutComponent)
        }
    }

    Component {
        id: languagePopoutComponent

        PopoutComponent {
            id: popoutColumn

            headerText: "OCR Language"
            detailsText: "Select OCR language (current: " + root.currentLang + ")"
            showCloseButton: true

            Item {
                width: parent.width
                implicitHeight: 400

                DankListView {
                    id: langList
                    anchors.fill: parent
                    clip: true
                    model: root.availableLanguages

                    delegate: StyledRect {
                        width: langList.width
                        height: 40
                        radius: Theme.cornerRadius
                        color: langMouseArea.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                        border.width: modelData === root.currentLang ? 2 : 0
                        border.color: Theme.primary

                        StyledText {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingM
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: modelData === root.currentLang ? Font.Bold : Font.Normal
                        }

                        MouseArea {
                            id: langMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor

                            onClicked: {
                                root.currentLang = modelData
                                if (typeof pluginService !== "undefined" && pluginService) {
                                    pluginService.savePluginData("ocr", "language", modelData)
                                }
                                ToastService.showInfo("OCR language set to: " + modelData)
                                popoutColumn.closePopout()
                            }
                        }
                    }
                }
            }
        }
    }

    pillClickAction: () => {
        runOcr()
    }

    pillRightClickAction: (x, y, width, section, screen) => {
        showLanguagePopout(x, y, width, section, screen)
    }

    horizontalBarPill: Component {
        StyledRect {
            width: pillContent.implicitWidth + Theme.spacingM * 2
            height: parent.widgetThickness
            radius: Theme.cornerRadius
            color: pillMouseArea.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

            Row {
                id: pillContent
                anchors.centerIn: parent
                spacing: Theme.spacingXS

                StyledText {
                    visible: root.showIcon
                    text: root.customIcon
                    font.family: "Nerd Font"
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceText
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    visible: root.showLabel
                    text: "OCR"
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeMedium
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            MouseArea {
                id: pillMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton

                onClicked: (mouse) => {
                    if (mouse.button === Qt.LeftButton) {
                        root.runOcr()
                    } else if (mouse.button === Qt.RightButton) {
                        const globalPos = mapToGlobal(mouse.x, mouse.y)
                        root.showLanguagePopout(globalPos.x, globalPos.y, width, root.section, root.parentScreen)
                    }
                }
            }
        }
    }

    verticalBarPill: Component {
        StyledRect {
            width: parent.widgetThickness
            height: pillContent.implicitHeight + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: pillMouseArea.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

            Column {
                id: pillContent
                anchors.centerIn: parent
                spacing: Theme.spacingXS

                StyledText {
                    visible: root.showIcon
                    text: root.customIcon
                    font.family: "Nerd Font"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    visible: root.showLabel
                    text: "OCR"
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeSmall
                    rotation: 90
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }

            MouseArea {
                id: pillMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton

                onClicked: (mouse) => {
                    if (mouse.button === Qt.LeftButton) {
                        root.runOcr()
                    } else if (mouse.button === Qt.RightButton) {
                        const globalPos = mapToGlobal(mouse.x, mouse.y)
                        root.showLanguagePopout(globalPos.x, globalPos.y, width, root.section, root.parentScreen)
                    }
                }
            }
        }
    }
}
