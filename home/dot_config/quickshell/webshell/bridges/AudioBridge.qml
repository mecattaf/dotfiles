// AudioBridge.qml -- wraps Quickshell.Services.Pipewire
// Exposes nodes, default sink/source, volume, mute, privacy state.

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

QtObject {
    id: root

    // ======================================================================
    // Public properties (os.audio)
    // ======================================================================

    property real volume: 0.0
    property bool muted: false
    property real sourceVolume: 0.0
    property bool sourceMuted: false
    property var defaultSink: null
    property var defaultSource: null

    property var sinks: []
    property var sources: []
    property var streams: []

    property var privacy: ({
        microphoneActive: false,
        cameraActive: false,
        screenshareActive: false,
        microphoneApps: [],
        cameraApps: [],
        screenshareApps: []
    })

    // ======================================================================
    // Signals
    // ======================================================================

    signal volumeOsd(var event)

    // ======================================================================
    // Public methods (os.audio)
    // ======================================================================

    function setVolume(value) {
        var sink = Pipewire.defaultAudioSink
        if (!sink) return
        var clamped = Math.min(Math.max(value, 0.0), 1.0)
        _lastSetVolume = clamped
        sink.audio.volume = clamped
    }

    function setMuted(muted) {
        var sink = Pipewire.defaultAudioSink
        if (!sink) return
        sink.audio.muted = muted
    }

    function setSourceVolume(value) {
        var source = Pipewire.defaultAudioSource
        if (!source) return
        var clamped = Math.min(Math.max(value, 0.0), 1.0)
        _lastSetSourceVolume = clamped
        source.audio.volume = clamped
    }

    function setSourceMuted(muted) {
        var source = Pipewire.defaultAudioSource
        if (!source) return
        source.audio.muted = muted
    }

    function toggleMute() {
        var sink = Pipewire.defaultAudioSink
        if (!sink) return
        sink.audio.muted = !sink.audio.muted
    }

    function toggleSourceMute() {
        var source = Pipewire.defaultAudioSource
        if (!source) return
        source.audio.muted = !source.audio.muted
    }

    function setDefaultSink(sinkId) {
        var node = _findNode(sinkId)
        if (node) Pipewire.preferredDefaultAudioSink = node
    }

    function setDefaultSource(sourceId) {
        var node = _findNode(sourceId)
        if (node) Pipewire.preferredDefaultAudioSource = node
    }

    function setSinkVolume(sinkId, value) {
        var node = _findNode(sinkId)
        if (node) node.audio.volume = Math.min(Math.max(value, 0.0), 1.0)
    }

    function setSinkMuted(sinkId, muted) {
        var node = _findNode(sinkId)
        if (node) node.audio.muted = muted
    }

    function setStreamVolume(streamId, value) {
        var node = _findNode(streamId)
        if (node) node.audio.volume = Math.min(Math.max(value, 0.0), 1.0)
    }

    function setStreamMuted(streamId, muted) {
        var node = _findNode(streamId)
        if (node) node.audio.muted = muted
    }

    // ======================================================================
    // Private: OSD dedup tracking
    // ======================================================================

    property real _lastSetVolume: -1
    property real _lastSetSourceVolume: -1

    function _findNode(nodeId) {
        if (!Pipewire.nodes?.values) return null
        return Pipewire.nodes.values.find(function(n) { return n.id === nodeId }) ?? null
    }

    function _flattenSink(node) {
        if (!node) return null
        return {
            id: node.id,
            name: node.name ?? "",
            description: node.description ?? "",
            volume: Math.min(Math.max(node.audio?.volume ?? 0, 0.0), 1.0),
            muted: node.audio?.muted ?? false,
            isDefault: node === Pipewire.defaultAudioSink,
            channels: node.audio?.channels ?? 2
        }
    }

    function _flattenSource(node) {
        if (!node) return null
        return {
            id: node.id,
            name: node.name ?? "",
            description: node.description ?? "",
            volume: Math.min(Math.max(node.audio?.volume ?? 0, 0.0), 1.0),
            muted: node.audio?.muted ?? false,
            isDefault: node === Pipewire.defaultAudioSource,
            channels: node.audio?.channels ?? 2
        }
    }

    function _flattenStream(node) {
        return {
            id: node.id,
            name: node.properties?.["application.name"] ?? node.properties?.["media.name"] ?? "",
            icon: node.properties?.["application.icon_name"] ?? null,
            volume: Math.min(Math.max(node.audio?.volume ?? 0, 0.0), 1.0),
            muted: node.audio?.muted ?? false,
            sinkId: node.target?.id ?? null,
            mediaClass: node.properties?.["media.class"] ?? "Stream/Output/Audio"
        }
    }

    function _rebuildArrays() {
        if (!Pipewire.nodes?.values) {
            root.sinks = []
            root.sources = []
            root.streams = []
            return
        }
        var nodes = Pipewire.nodes.values
        var newSinks = []
        var newSources = []
        var newStreams = []

        for (var i = 0; i < nodes.length; i++) {
            var node = nodes[i]
            var mc = node.properties?.["media.class"] ?? ""

            if (mc === "Audio/Sink") {
                newSinks.push(_flattenSink(node))
            } else if (mc === "Audio/Source") {
                newSources.push(_flattenSource(node))
            } else if (mc.startsWith("Stream/")) {
                newStreams.push(_flattenStream(node))
            }
        }

        root.sinks = newSinks
        root.sources = newSources
        root.streams = newStreams
    }

    function _rebuildPrivacy() {
        if (!Pipewire.nodes?.values) return

        var micActive = false
        var camActive = false
        var screenActive = false
        var micApps = []
        var camApps = []
        var screenApps = []

        if (Pipewire.linkGroups?.values) {
            for (var i = 0; i < Pipewire.linkGroups.values.length; i++) {
                var lg = Pipewire.linkGroups.values[i]
                if (lg.source?.type === PwNodeType.AudioSource &&
                    lg.target?.type === PwNodeType.AudioInStream) {
                    var appName = lg.target?.properties?.["application.name"] ?? ""
                    var combined = [lg.target?.name, appName].join(" ").toLowerCase()
                    if (!/cava|monitor|system/.test(combined)) {
                        micActive = true
                        if (appName && !micApps.includes(appName)) micApps.push(appName)
                    }
                }
                if (lg.source?.type === PwNodeType.VideoSource) {
                    screenActive = true
                    var appName2 = lg.target?.properties?.["application.name"] ?? ""
                    if (appName2 && !screenApps.includes(appName2)) screenApps.push(appName2)
                }
            }
        }

        var nodes = Pipewire.nodes.values
        for (var j = 0; j < nodes.length; j++) {
            var node = nodes[j]
            var mc = node.properties?.["media.class"] ?? ""
            if (mc === "Stream/Input/Video" && node.properties?.["stream.is-live"] === "true") {
                camActive = true
                var camApp = node.properties?.["application.name"] ?? ""
                if (camApp && !camApps.includes(camApp)) camApps.push(camApp)
            }
        }

        root.privacy = {
            microphoneActive: micActive,
            cameraActive: camActive,
            screenshareActive: screenActive,
            microphoneApps: micApps,
            cameraApps: camApps,
            screenshareApps: screenApps
        }
    }

    function _syncSinkState() {
        var sink = Pipewire.defaultAudioSink
        if (sink) {
            root.volume = Math.min(Math.max(sink.audio.volume, 0.0), 1.0)
            root.muted = sink.audio.muted
            root.defaultSink = _flattenSink(sink)
        } else {
            root.volume = 0.0
            root.muted = false
            root.defaultSink = null
        }
    }

    function _syncSourceState() {
        var source = Pipewire.defaultAudioSource
        if (source) {
            root.sourceVolume = Math.min(Math.max(source.audio.volume, 0.0), 1.0)
            root.sourceMuted = source.audio.muted
            root.defaultSource = _flattenSource(source)
        } else {
            root.sourceVolume = 0.0
            root.sourceMuted = false
            root.defaultSource = null
        }
    }

    // ======================================================================
    // Private: OSD debounced, fires for external volume changes
    // ======================================================================

    Timer {
        id: osdDebounce
        interval: 50
        repeat: false
        onTriggered: {
            var sink = Pipewire.defaultAudioSink
            if (!sink) return
            var currentVol = Math.min(Math.max(sink.audio.volume, 0.0), 1.0)
            if (Math.abs(currentVol - root._lastSetVolume) > 0.001) {
                root.volumeOsd({
                    type: "sink",
                    deviceId: sink.id,
                    volume: currentVol,
                    muted: sink.audio.muted,
                    deviceDescription: sink.description ?? ""
                })
            }
        }
    }

    Connections {
        target: Pipewire.defaultAudioSink?.audio ?? null
        function onVolumeChanged() {
            root._syncSinkState()
            osdDebounce.restart()
        }
        function onMutedChanged() {
            root._syncSinkState()
            osdDebounce.restart()
        }
    }

    Connections {
        target: Pipewire.defaultAudioSource?.audio ?? null
        function onVolumeChanged() { root._syncSourceState() }
        function onMutedChanged() { root._syncSourceState() }
    }

    Connections {
        target: Pipewire
        function onDefaultAudioSinkChanged() { root._syncSinkState() }
        function onDefaultAudioSourceChanged() { root._syncSourceState() }
    }

    Timer {
        id: rebuildDebounce
        interval: 50
        repeat: false
        onTriggered: {
            root._rebuildArrays()
            root._rebuildPrivacy()
        }
    }

    Connections {
        target: Pipewire.nodes ?? null
        function onValuesChanged() { rebuildDebounce.restart() }
    }

    Connections {
        target: Pipewire.linkGroups ?? null
        function onValuesChanged() { rebuildDebounce.restart() }
    }

    Component.onCompleted: {
        _syncSinkState()
        _syncSourceState()
        _rebuildArrays()
        _rebuildPrivacy()
    }
}
