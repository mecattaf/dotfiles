// AudioBridge.qml -- wraps Quickshell.Services.Pipewire
// Exposes nodes, default sink/source, volume, mute, privacy state.
// CRITICAL: PwObjectTracker binds nodes so volume/muted are valid.

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

Scope {
    id: root

    // ======================================================================
    // Public properties (os.audio)
    // ======================================================================

    property bool ready: false

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

    // v0.2.0 SHOULD: device aliases (#108) -- stored as { nodeId: alias } map
    property var deviceAliases: ({})

    // ======================================================================
    // Signals
    // ======================================================================

    signal volumeOsd(var event)

    // ======================================================================
    // Public methods (os.audio)
    // ======================================================================

    function setVolume(value) {
        var sink = Pipewire.defaultAudioSink
        if (!sink || !sink.audio) return
        var clamped = Math.min(Math.max(value, 0.0), 1.0)
        _lastSetVolume = clamped
        sink.audio.volume = clamped
    }

    function setMuted(muted) {
        var sink = Pipewire.defaultAudioSink
        if (!sink || !sink.audio) return
        sink.audio.muted = muted
    }

    function setSourceVolume(value) {
        var source = Pipewire.defaultAudioSource
        if (!source || !source.audio) return
        var clamped = Math.min(Math.max(value, 0.0), 1.0)
        _lastSetSourceVolume = clamped
        source.audio.volume = clamped
    }

    function setSourceMuted(muted) {
        var source = Pipewire.defaultAudioSource
        if (!source || !source.audio) return
        source.audio.muted = muted
    }

    function toggleMute() {
        var sink = Pipewire.defaultAudioSink
        if (!sink || !sink.audio) return
        sink.audio.muted = !sink.audio.muted
    }

    function toggleSourceMute() {
        var source = Pipewire.defaultAudioSource
        if (!source || !source.audio) return
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
        if (node && node.audio) node.audio.volume = Math.min(Math.max(value, 0.0), 1.0)
    }

    function setSinkMuted(sinkId, muted) {
        var node = _findNode(sinkId)
        if (node && node.audio) node.audio.muted = muted
    }

    function setStreamVolume(streamId, value) {
        var node = _findNode(streamId)
        if (node && node.audio) node.audio.volume = Math.min(Math.max(value, 0.0), 1.0)
    }

    function setStreamMuted(streamId, muted) {
        var node = _findNode(streamId)
        if (node && node.audio) node.audio.muted = muted
    }

    // v0.2.0 SHOULD: device alias/rename (#108)
    function setDeviceAlias(nodeId, alias) {
        var updated = Object.assign({}, root.deviceAliases)
        updated[nodeId] = alias
        root.deviceAliases = updated
    }

    // ======================================================================
    // Private: OSD dedup tracking
    // ======================================================================

    property real _lastSetVolume: -1
    property real _lastSetSourceVolume: -1

    // ======================================================================
    // CRITICAL: PwObjectTracker -- binds default sink/source so that
    // volume, muted, channels, volumes properties become valid.
    // Without this, audio properties return garbage/zero.
    // ======================================================================

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
    }

    // ======================================================================
    // Private: helpers
    // ======================================================================

    function _findNode(nodeId) {
        if (!Pipewire.nodes) return null
        var vals = Pipewire.nodes.values
        for (var i = 0; i < vals.length; i++) {
            if (vals[i].id === nodeId) return vals[i]
        }
        return null
    }

    function _flattenSink(node) {
        if (!node) return null
        return {
            id: node.id,
            name: node.name ?? "",
            description: node.description ?? "",
            volume: Math.min(Math.max(node.audio ? node.audio.volume : 0, 0.0), 1.0),
            muted: node.audio ? node.audio.muted : false,
            isDefault: node === Pipewire.defaultAudioSink,
            channels: node.audio ? node.audio.channels.length : 0
        }
    }

    function _flattenSource(node) {
        if (!node) return null
        return {
            id: node.id,
            name: node.name ?? "",
            description: node.description ?? "",
            volume: Math.min(Math.max(node.audio ? node.audio.volume : 0, 0.0), 1.0),
            muted: node.audio ? node.audio.muted : false,
            isDefault: node === Pipewire.defaultAudioSource,
            channels: node.audio ? node.audio.channels.length : 0
        }
    }

    function _flattenStream(node) {
        // Streams are audio nodes with the Stream flag set.
        // node.properties requires PwObjectTracker binding -- use safe access.
        var appName = ""
        var iconName = null
        var mediaClass = "Stream/Output/Audio"
        if (node.properties) {
            appName = node.properties["application.name"] ?? node.properties["media.name"] ?? ""
            iconName = node.properties["application.icon-name"] ?? null
            mediaClass = node.properties["media.class"] ?? "Stream/Output/Audio"
        }

        // Find the target sink by scanning linkGroups for connections from this stream.
        var targetSinkId = null
        if (Pipewire.linkGroups) {
            var lgs = Pipewire.linkGroups.values
            for (var i = 0; i < lgs.length; i++) {
                if (lgs[i].source && lgs[i].source.id === node.id && lgs[i].target) {
                    targetSinkId = lgs[i].target.id
                    break
                }
            }
        }

        return {
            id: node.id,
            name: appName,
            icon: iconName,
            volume: Math.min(Math.max(node.audio ? node.audio.volume : 0, 0.0), 1.0),
            muted: node.audio ? node.audio.muted : false,
            sinkId: targetSinkId,
            mediaClass: mediaClass
        }
    }

    function _rebuildArrays() {
        if (!Pipewire.nodes) {
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
            // Use PwNodeType flags instead of properties["media.class"]
            // type flags are available without PwObjectTracker binding.
            // PwNodeType.Audio = 0b1, PwNodeType.Sink = 0b10000,
            // PwNodeType.Source = 0b1000, PwNodeType.Stream = 0b100

            if (!node.audio) continue  // Skip non-audio nodes

            var t = node.type
            var isAudio = (t & PwNodeType.Audio) !== 0
            var isSinkFlag = (t & PwNodeType.Sink) !== 0
            var isSourceFlag = (t & PwNodeType.Source) !== 0
            var isStreamFlag = (t & PwNodeType.Stream) !== 0

            if (!isAudio) continue

            if (isStreamFlag) {
                // Audio stream (application playback or capture)
                newStreams.push(_flattenStream(node))
            } else if (isSinkFlag && !isSourceFlag) {
                // Hardware audio sink (speaker, headphones)
                newSinks.push(_flattenSink(node))
            } else if (isSourceFlag && !isSinkFlag) {
                // Hardware audio source (microphone)
                newSources.push(_flattenSource(node))
            }
            // Duplex nodes (Sink + Source, no Stream) are skipped for now
        }

        root.sinks = newSinks
        root.sources = newSources
        root.streams = newStreams
    }

    function _rebuildPrivacy() {
        if (!Pipewire.nodes) return

        var micActive = false
        var camActive = false
        var screenActive = false
        var micApps = []
        var camApps = []
        var screenApps = []

        // Check link groups for active mic capture
        if (Pipewire.linkGroups) {
            var lgs = Pipewire.linkGroups.values
            for (var i = 0; i < lgs.length; i++) {
                var lg = lgs[i]
                // Mic detection: source is an AudioSource device, target is an AudioInStream
                if (lg.source && lg.target) {
                    var srcType = lg.source.type
                    var tgtType = lg.target.type

                    // AudioSource (hardware mic) -> AudioInStream (capture stream)
                    if ((srcType & PwNodeType.Audio) && (srcType & PwNodeType.Source) && !(srcType & PwNodeType.Stream) &&
                        (tgtType & PwNodeType.Audio) && (tgtType & PwNodeType.Source) && (tgtType & PwNodeType.Stream)) {
                        var appName = ""
                        if (lg.target.properties) {
                            appName = lg.target.properties["application.name"] ?? ""
                        }
                        var combined = [lg.target.name ?? "", appName].join(" ").toLowerCase()
                        if (!/cava|monitor|system/.test(combined)) {
                            micActive = true
                            if (appName && !micApps.includes(appName)) micApps.push(appName)
                        }
                    }
                    // Screenshare detection: source is a VideoSource
                    if ((srcType & PwNodeType.Video) && (srcType & PwNodeType.Source)) {
                        screenActive = true
                        var appName2 = ""
                        if (lg.target.properties) {
                            appName2 = lg.target.properties["application.name"] ?? ""
                        }
                        if (appName2 && !screenApps.includes(appName2)) screenApps.push(appName2)
                    }
                }
            }
        }

        // Camera detection: look for video input streams that are live
        var nodes = Pipewire.nodes.values
        for (var j = 0; j < nodes.length; j++) {
            var node = nodes[j]
            if (node.properties) {
                var mc = node.properties["media.class"] ?? ""
                if (mc === "Stream/Input/Video" && node.properties["stream.is-live"] === "true") {
                    camActive = true
                    var camApp = node.properties["application.name"] ?? ""
                    if (camApp && !camApps.includes(camApp)) camApps.push(camApp)
                }
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
        if (sink && sink.audio) {
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
        if (source && source.audio) {
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
            if (!sink || !sink.audio) return
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
        function onVolumesChanged() {
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
        function onVolumesChanged() { root._syncSourceState() }
        function onMutedChanged() { root._syncSourceState() }
    }

    Connections {
        target: Pipewire
        function onDefaultAudioSinkChanged() {
            if (!root.ready && Pipewire.defaultAudioSink !== null) {
                root.ready = true
            }
            root._syncSinkState()
        }
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

    // ======================================================================
    // Pull-data fallback: getData(key)
    // ======================================================================

    function getData(key) {
        if (key === "sinks") return JSON.stringify(root.sinks)
        if (key === "sources") return JSON.stringify(root.sources)
        if (key === "streams") return JSON.stringify(root.streams)
        if (key === "volume") return JSON.stringify({ volume: root.volume, muted: root.muted })
        if (key === "sourceVolume") return JSON.stringify({ volume: root.sourceVolume, muted: root.sourceMuted })
        if (key === "defaultSink") return JSON.stringify(root.defaultSink)
        if (key === "defaultSource") return JSON.stringify(root.defaultSource)
        if (key === "privacy") return JSON.stringify(root.privacy)
        return "{}"
    }

    // ======================================================================
    // Health check timer
    // ======================================================================

    Timer {
        interval: 3000
        running: true
        repeat: false
        onTriggered: {
            if (!root.ready) {
                console.warn("AudioBridge: HEALTH CHECK — not ready after 3s")
            } else {
                console.info("AudioBridge: healthy")
            }
        }
    }

    Component.onCompleted: {
        _syncSinkState()
        _syncSourceState()
        _rebuildArrays()
        _rebuildPrivacy()
        if (Pipewire.defaultAudioSink !== null) {
            root.ready = true
        }
    }
}
