pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    readonly property bool isLightMode: false

    // MD3 Dark Purple palette
    property color primary: "#D0BCFF"
    property color primaryText: "#381E72"
    property color primaryContainer: "#4F378B"
    property color secondary: "#CCC2DC"
    property color surface: "#1C1B1F"
    property color surfaceText: "#E6E1E5"
    property color surfaceVariant: "#49454F"
    property color surfaceVariantText: "#CAC4D0"
    property color surfaceTint: "#D0BCFF"
    property color background: "#1C1B1F"
    property color backgroundText: "#E6E1E5"
    property color outline: "#938F99"
    property color surfaceContainer: "#211F26"
    property color surfaceContainerHigh: "#2B2930"
    property color surfaceContainerHighest: "#36343B"
    property color error: "#F2B8B5"
    property color warning: "#FF9800"
    property color info: "#2196F3"
    property color success: "#4CAF50"

    // Derived colors
    property color primaryHover: Qt.rgba(primary.r, primary.g, primary.b, 0.12)
    property color primaryHoverLight: Qt.rgba(primary.r, primary.g, primary.b, 0.08)
    property color primaryPressed: Qt.rgba(primary.r, primary.g, primary.b, 0.16)
    property color primarySelected: Qt.rgba(primary.r, primary.g, primary.b, 0.3)
    property color surfaceHover: Qt.rgba(surfaceVariant.r, surfaceVariant.g, surfaceVariant.b, 0.08)
    property color surfacePressed: Qt.rgba(surfaceVariant.r, surfaceVariant.g, surfaceVariant.b, 0.12)
    property color surfaceLight: Qt.rgba(surfaceVariant.r, surfaceVariant.g, surfaceVariant.b, 0.1)
    property color surfaceVariantAlpha: Qt.rgba(surfaceVariant.r, surfaceVariant.g, surfaceVariant.b, 0.2)
    property color outlineButton: Qt.rgba(outline.r, outline.g, outline.b, 0.5)
    property color outlineMedium: Qt.rgba(outline.r, outline.g, outline.b, 0.08)
    property color outlineStrong: Qt.rgba(outline.r, outline.g, outline.b, 0.12)

    // Spacing
    readonly property int spacingXS: 4
    readonly property int spacingS: 8
    readonly property int spacingM: 12
    readonly property int spacingL: 16

    // Typography
    readonly property string fontFamily: "Sans"
    readonly property string monoFontFamily: "Monospace"
    readonly property string defaultFontFamily: "Sans"
    readonly property string defaultMonoFontFamily: "Monospace"
    readonly property int fontWeight: 400
    readonly property int fontSizeSmall: 12
    readonly property int fontSizeMedium: 14
    readonly property int fontSizeLarge: 16
    readonly property int iconSize: 20

    // Shape
    readonly property real cornerRadius: 12
    readonly property real popupTransparency: 0.95

    // Animation
    readonly property int shortDuration: 150
    readonly property int shorterDuration: 100
    readonly property int modalAnimationDuration: 250
    readonly property int standardEasing: Easing.OutCubic
    readonly property int emphasizedEasing: Easing.InOutCubic

    // Expressive curves and durations (used by DankAnim and DankRipple)
    readonly property var expressiveCurves: ({
        standard: [0.2, 0, 0, 1, 1, 1],
        standardDecel: [0, 0, 0, 1, 1, 1],
        emphasized: [0.2, 0, 0, 1, 1, 1],
        expressiveDefaultSpatial: [0.2, 0, 0, 1, 1, 1]
    })
    readonly property var expressiveDurations: ({
        normal: 300,
        expressiveDefaultSpatial: 400
    })

    readonly property string currentAnimationSpeed: "normal"

    // Elevation
    readonly property bool elevationEnabled: true
    readonly property real elevationBlurMax: 64
    readonly property var elevationLevel2: ({ blurPx: 8, offsetX: 0, offsetY: 4, spreadPx: 0, alpha: 0.25 })
    readonly property var elevationLevel3: ({ blurPx: 12, offsetX: 0, offsetY: 6, spreadPx: 0, alpha: 0.3 })
    readonly property string elevationLightDirection: "top"

    function elevationOffsetXFor(level, direction, fallback) {
        return level ? (level.offsetX || 0) : 0;
    }
    function elevationOffsetYFor(level, direction, fallback) {
        return level ? (level.offsetY || fallback || 0) : (fallback || 0);
    }
    function elevationShadowColor(level) {
        return Qt.rgba(0, 0, 0, level ? (level.alpha || 0.25) : 0.25);
    }
    function withAlpha(color, alpha) {
        return Qt.rgba(color.r, color.g, color.b, alpha);
    }
}
