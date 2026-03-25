import QtQuick

StyledRect {
    id: root

    property alias text: textInput.text
    property string placeholderText: ""
    property alias font: textInput.font
    property alias textColor: textInput.color
    property alias enabled: textInput.enabled
    property alias echoMode: textInput.echoMode
    property alias validator: textInput.validator
    property alias maximumLength: textInput.maximumLength
    property string leftIconName: ""
    property int leftIconSize: Theme.iconSize
    property color leftIconColor: Theme.surfaceVariantText
    property color leftIconFocusedColor: Theme.primary
    property bool showClearButton: false
    property color backgroundColor: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
    property color focusedBorderColor: Theme.primary
    property color normalBorderColor: Theme.outlineMedium
    property color placeholderColor: Theme.outlineButton
    property int borderWidth: 1
    property int focusedBorderWidth: 2
    property real cornerRadius: Theme.cornerRadius
    property real topPadding: Theme.spacingS
    property real bottomPadding: Theme.spacingS
    property bool ignoreLeftRightKeys: false
    property bool ignoreUpDownKeys: false
    property bool ignoreTabKeys: false
    property var keyForwardTargets: []
    property Item keyNavigationTab: null
    property Item keyNavigationBacktab: null

    signal textEdited
    signal editingFinished
    signal accepted
    signal focusStateChanged(bool hasFocus)

    function forceActiveFocus() { textInput.forceActiveFocus(); }
    function selectAll() { textInput.selectAll(); }
    function clear() { textInput.clear(); }

    width: 200
    height: Math.round(Theme.fontSizeMedium * 3)
    radius: cornerRadius
    color: backgroundColor
    border.color: textInput.activeFocus ? focusedBorderColor : normalBorderColor
    border.width: textInput.activeFocus ? focusedBorderWidth : borderWidth

    KeyNavigation.tab: keyNavigationTab
    KeyNavigation.backtab: keyNavigationBacktab

    DankIcon {
        id: leftIcon
        anchors.left: parent.left
        anchors.leftMargin: Theme.spacingM
        anchors.verticalCenter: parent.verticalCenter
        name: leftIconName
        size: leftIconSize
        color: textInput.activeFocus ? leftIconFocusedColor : leftIconColor
        visible: leftIconName !== ""
    }

    TextInput {
        id: textInput
        anchors.left: leftIcon.visible ? leftIcon.right : parent.left
        anchors.leftMargin: Theme.spacingM
        anchors.right: clearBtn.visible ? clearBtn.left : parent.right
        anchors.rightMargin: Theme.spacingM
        anchors.top: parent.top
        anchors.topMargin: root.topPadding
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.bottomPadding
        font.pixelSize: Theme.fontSizeMedium
        color: Theme.surfaceText
        selectionColor: Theme.primaryContainer
        selectedTextColor: Theme.primary
        horizontalAlignment: TextInput.AlignLeft
        verticalAlignment: TextInput.AlignVCenter
        selectByMouse: true
        clip: true
        activeFocusOnTab: true
        KeyNavigation.tab: root.keyNavigationTab
        KeyNavigation.backtab: root.keyNavigationBacktab
        onTextChanged: root.textEdited()
        onEditingFinished: root.editingFinished()
        onAccepted: root.accepted()
        onActiveFocusChanged: root.focusStateChanged(activeFocus)
        Keys.forwardTo: root.keyForwardTargets
        Keys.onPressed: event => {
            if (root.ignoreTabKeys && (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)) {
                event.accepted = false;
                for (var i = 0; i < root.keyForwardTargets.length; i++) {
                    if (root.keyForwardTargets[i])
                        root.keyForwardTargets[i].Keys.pressed(event);
                }
                return;
            }
            if (root.ignoreUpDownKeys && (event.key === Qt.Key_Up || event.key === Qt.Key_Down)) {
                event.accepted = false;
                for (var i = 0; i < root.keyForwardTargets.length; i++) {
                    if (root.keyForwardTargets[i])
                        root.keyForwardTargets[i].Keys.pressed(event);
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.IBeamCursor
            acceptedButtons: Qt.NoButton
        }
    }

    Rectangle {
        id: clearBtn
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter
        width: 20; height: 20; radius: 10
        color: clearArea.containsMouse ? Theme.outlineStrong : "transparent"
        visible: showClearButton && textInput.text.length > 0
        DankIcon { anchors.centerIn: parent; name: "close"; size: 14; color: Theme.surfaceVariantText }
        MouseArea {
            id: clearArea
            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: textInput.text = ""
        }
    }

    StyledText {
        anchors.fill: textInput
        text: root.placeholderText
        font: textInput.font
        color: placeholderColor
        horizontalAlignment: Text.AlignLeft
        verticalAlignment: textInput.verticalAlignment
        visible: textInput.text.length === 0 && !textInput.activeFocus
        elide: Text.ElideRight
    }

    Behavior on border.color { ColorAnimation { duration: Theme.shortDuration } }
    Behavior on border.width { NumberAnimation { duration: Theme.shortDuration } }
}
