import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Item {
    id: root

    visible: false

    property bool spotlightOpen: false
    property bool keyboardActive: false
    property bool contentVisible: false
    property var spotlightContent: launcherContentLoader.item
    property bool isClosing: false
    property bool _pendingInitialize: false
    property string _pendingQuery: ""
    property string _pendingMode: ""

    readonly property int baseWidth: 620
    readonly property int baseHeight: 600
    readonly property real screenWidth: launcherWindow.screen?.width ?? 1920
    readonly property real screenHeight: launcherWindow.screen?.height ?? 1080
    readonly property int modalWidth: Math.min(baseWidth, screenWidth - 100)
    readonly property int modalHeight: Math.min(baseHeight, screenHeight - 100)
    readonly property real modalX: (screenWidth - modalWidth) / 2
    readonly property real modalY: (screenHeight - modalHeight) / 2

    readonly property color backgroundColor: Theme.withAlpha(Theme.surfaceContainer, Theme.popupTransparency)
    readonly property real cornerRadius: Theme.cornerRadius
    readonly property color borderColor: Theme.outlineMedium
    readonly property int borderWidth: 0

    signal dialogClosed

    function _ensureContentLoadedAndInitialize(query, mode) {
        _pendingQuery = query || "";
        _pendingMode = mode || "";
        _pendingInitialize = true;
        contentVisible = true;
        launcherContentLoader.active = true;
        if (spotlightContent) {
            _initializeAndShow(_pendingQuery, _pendingMode);
            _pendingInitialize = false;
        }
    }

    function _initializeAndShow(query, mode) {
        if (!spotlightContent) return;
        contentVisible = true;
        spotlightContent.searchField.forceActiveFocus();
        if (spotlightContent.searchField) {
            spotlightContent.searchField.text = query;
        }
        if (spotlightContent.controller) {
            var targetMode = mode || SessionData.launcherLastMode || "all";
            spotlightContent.controller.searchMode = targetMode;
            spotlightContent.controller.activePluginId = "";
            spotlightContent.controller.activePluginName = "";
            spotlightContent.controller.pluginFilter = "";
            spotlightContent.controller.fileSearchType = "all";
            spotlightContent.controller.fileSearchExt = "";
            spotlightContent.controller.fileSearchFolder = "";
            spotlightContent.controller.fileSearchSort = "score";
            spotlightContent.controller.collapsedSections = {};
            spotlightContent.controller.selectedFlatIndex = 0;
            spotlightContent.controller.selectedItem = null;
            if (query) {
                spotlightContent.controller.setSearchQuery(query);
            } else {
                spotlightContent.controller.searchQuery = "";
                spotlightContent.controller.performSearch();
            }
        }
        if (spotlightContent.resetScroll) spotlightContent.resetScroll();
        if (spotlightContent.actionPanel) spotlightContent.actionPanel.hide();
    }

    function show() {
        closeCleanupTimer.stop();
        isClosing = false;
        spotlightOpen = true;
        keyboardActive = true;
        ModalManager.openModal(root);
        _ensureContentLoadedAndInitialize("", "");
    }

    function showWithQuery(query) {
        closeCleanupTimer.stop();
        isClosing = false;
        spotlightOpen = true;
        keyboardActive = true;
        ModalManager.openModal(root);
        _ensureContentLoadedAndInitialize(query, "");
    }

    function hide() {
        if (!spotlightOpen) return;
        isClosing = true;
        contentVisible = false;
        keyboardActive = false;
        spotlightOpen = false;
        ModalManager.closeModal(root);
        closeCleanupTimer.start();
    }

    function toggle() {
        spotlightOpen ? hide() : show();
    }

    function showWithMode(mode) {
        closeCleanupTimer.stop();
        isClosing = false;
        spotlightOpen = true;
        keyboardActive = true;
        ModalManager.openModal(root);
        _ensureContentLoadedAndInitialize("", mode);
    }

    Timer {
        id: closeCleanupTimer
        interval: Theme.modalAnimationDuration + 50
        repeat: false
        onTriggered: {
            isClosing = false;
            dialogClosed();
        }
    }

    Connections {
        target: spotlightContent?.controller ?? null
        function onModeChanged(mode) {
            if (spotlightContent.controller.autoSwitchedToFiles) return;
            SessionData.setLauncherLastMode(mode);
        }
    }

    Connections {
        target: ModalManager
        function onCloseAllModalsExcept(excludedModal) {
            if (excludedModal !== root && spotlightOpen) hide();
        }
    }

    PanelWindow {
        id: launcherWindow
        visible: spotlightOpen || isClosing
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore

        WlrLayershell.namespace: "eqsh:launcher"
        WlrLayershell.layer: WlrLayershell.Top
        WlrLayershell.keyboardFocus: keyboardActive ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        mask: Region {
            item: spotlightOpen ? fullScreenMask : null
        }

        Item {
            id: fullScreenMask
            anchors.fill: parent
        }

        Rectangle {
            id: backgroundDarken
            anchors.fill: parent
            color: "black"
            opacity: contentVisible && SettingsData.modalDarkenBackground ? 0.5 : 0
            visible: contentVisible || opacity > 0
            Behavior on opacity {
                NumberAnimation { duration: Theme.modalAnimationDuration; easing.type: Easing.OutCubic }
            }
        }

        MouseArea {
            anchors.fill: parent
            enabled: spotlightOpen
            onClicked: mouse => {
                var contentX = modalContainer.x;
                var contentY = modalContainer.y;
                var contentW = modalContainer.width;
                var contentH = modalContainer.height;
                if (mouse.x < contentX || mouse.x > contentX + contentW || mouse.y < contentY || mouse.y > contentY + contentH) {
                    root.hide();
                }
            }
        }

        Item {
            id: modalContainer
            x: root.modalX
            y: root.modalY
            width: root.modalWidth
            height: root.modalHeight
            visible: contentVisible || opacity > 0

            opacity: contentVisible ? 1 : 0
            scale: contentVisible ? 1 : 0.96
            transformOrigin: Item.Center

            Behavior on opacity {
                NumberAnimation { duration: Theme.modalAnimationDuration; easing.type: Easing.OutCubic }
            }
            Behavior on scale {
                NumberAnimation { duration: Theme.modalAnimationDuration; easing.type: Easing.OutCubic }
            }

            ElevationShadow {
                id: launcherShadowLayer
                anchors.fill: parent
                level: Theme.elevationLevel3
                fallbackOffset: 6
                targetColor: root.backgroundColor
                borderColor: root.borderColor
                borderWidth: root.borderWidth
                targetRadius: root.cornerRadius
                shadowEnabled: Theme.elevationEnabled
            }

            MouseArea {
                anchors.fill: parent
                onPressed: mouse => mouse.accepted = true
            }

            FocusScope {
                anchors.fill: parent
                focus: keyboardActive

                Loader {
                    id: launcherContentLoader
                    anchors.fill: parent
                    active: true
                    asynchronous: false
                    sourceComponent: LauncherContent {
                        focus: true
                        parentModal: root
                    }

                    onLoaded: {
                        if (root._pendingInitialize) {
                            root._initializeAndShow(root._pendingQuery, root._pendingMode);
                            root._pendingInitialize = false;
                        }
                    }
                }

                Keys.onEscapePressed: event => {
                    root.hide();
                    event.accepted = true;
                }
            }
        }
    }
}
