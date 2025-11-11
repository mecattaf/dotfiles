import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets
import "./YdotoolService.qml" as YdotoolService

Rectangle {
    id: root

    property var keyData
    property string key: keyData.label
    property string type: keyData.keytype
    property var keycode: keyData.keycode
    property string shape: keyData.shape
    property bool isShift: YdotoolService.shiftKeys.includes(keycode)
    property bool isBackspace: (key.toLowerCase() == "backspace")
    property bool isEnter: (key.toLowerCase() == "enter" || key.toLowerCase() == "return")
    property real baseWidth: 45
    property real baseHeight: 45
    property var widthMultiplier: ({
        "normal": 1,
        "fn": 1,
        "tab": 1.6,
        "caps": 1.9,
        "shift": 2.5,
        "control": 1.3
    })
    property var heightMultiplier: ({
        "normal": 1,
        "fn": 0.7,
        "tab": 1,
        "caps": 1,
        "shift": 1,
        "control": 1
    })
    property bool toggled: isShift ? YdotoolService.shiftMode > 0 : false
    property bool isPressed: false

    enabled: shape != "empty"
    color: {
        if (shape == "empty") return "transparent"
        if (toggled) return Theme.primary
        if (isPressed) return Theme.surfaceLight
        return Theme.surfaceContainer
    }
    radius: Theme.cornerRadius
    implicitWidth: baseWidth * (widthMultiplier[shape] || 1)
    implicitHeight: baseHeight * (heightMultiplier[shape] || 1)
    Layout.fillWidth: shape == "space" || shape == "expand"

    border.color: Theme.outline
    border.width: 1

    Behavior on color {
        ColorAnimation { duration: Theme.shortDuration }
    }

    Timer {
        id: capsLockTimer
        property bool hasStarted: false
        property bool canCaps: false
        interval: 300

        function startWaiting() {
            hasStarted = true;
            canCaps = true;
            start();
        }

        onTriggered: {
            canCaps = false;
        }
    }

    Connections {
        target: YdotoolService
        enabled: isShift

        function onShiftModeChanged() {
            if (YdotoolService.shiftMode == 0) {
                capsLockTimer.hasStarted = false;
            }
        }
    }

    StyledText {
        id: keyText
        anchors.centerIn: parent
        font.family: (isBackspace || isEnter) ? "Material Symbols Rounded" : Theme.fontFamily
        font.pixelSize: root.shape == "fn" ? Theme.fontSizeSmall :
            (isBackspace || isEnter) ? Theme.fontSizeLarge :
            Theme.fontSizeMedium
        horizontalAlignment: Text.AlignHCenter
        color: root.toggled ? Theme.onPrimary : Theme.surfaceText
        text: root.isBackspace ? "backspace" : root.isEnter ? "subdirectory_arrow_left" :
            YdotoolService.shiftMode == 2 ? (root.keyData.labelCaps || root.keyData.labelShift || root.keyData.label) :
            YdotoolService.shiftMode == 1 ? (root.keyData.labelShift || root.keyData.label) :
            root.keyData.label
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true

        onPressed: {
            root.isPressed = true
            YdotoolService.press(root.keycode);
            if (isShift && YdotoolService.shiftMode == 0) {
                YdotoolService.shiftMode = 1;
            }
        }

        onReleased: {
            root.isPressed = false

            if (root.type == "normal") {
                YdotoolService.release(root.keycode);
                if (YdotoolService.shiftMode == 1) {
                    YdotoolService.releaseShiftKeys()
                }
            } else if (isShift) {
                if (YdotoolService.shiftMode == 1) {
                    if (!capsLockTimer.hasStarted) {
                        capsLockTimer.startWaiting();
                    } else {
                        if (capsLockTimer.canCaps) {
                            YdotoolService.shiftMode = 2; // Caps lock mode
                        } else {
                            YdotoolService.releaseShiftKeys()
                        }
                    }
                } else if (YdotoolService.shiftMode == 2) {
                    YdotoolService.releaseShiftKeys();
                }
            } else if (root.type == "modkey") {
                root.toggled = !root.toggled;
                if (!root.toggled) {
                    if (isShift) {
                        YdotoolService.releaseShiftKeys();
                    } else {
                        YdotoolService.release(root.keycode);
                    }
                }
            }
        }
    }
}
