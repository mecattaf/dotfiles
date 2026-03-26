// MprisBridge.qml -- Port of current-dotfiles MusicPlayerProvider.qml
// Uses Quickshell.Services.Mpris. Exposes active player (last in list),
// title, artist, album, thumbnail, isPlaying, duration, position.
// IPC handler (target: "music", togglePlay/next/previous/getData).
//
// Fixed: position is in seconds (not microseconds), seek/setPosition
// no longer multiply by 1_000_000. Added shuffle/loopStatus properties.
// IPC getData() returns JSON string (IPC only supports primitives).

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

Scope {
    id: root

    // ======================================================================
    // Public properties (os.media)
    // ======================================================================

    property var players: []
    property var activePlayer: null

    property string title: ""
    property string artist: ""
    property string album: ""
    property string thumbnail: ""
    property bool isPlaying: false
    property real duration: 0    // seconds, with ms precision
    property real position: 0    // seconds, with ms precision
    property bool isAvailable: false
    property bool shuffle: false
    property string loopStatus: "none"  // "none", "track", "playlist"

    // ======================================================================
    // Signals
    // ======================================================================

    signal trackChanged(var event)

    // ======================================================================
    // Public methods (os.media)
    // ======================================================================

    function togglePlay() {
        var qsPlayer = _getActiveQsPlayer()
        if (!qsPlayer) return
        qsPlayer.togglePlaying()
    }

    function play(playerId) {
        var p = _resolvePlayer(playerId)
        if (p) p.play()
    }

    function pause(playerId) {
        var p = _resolvePlayer(playerId)
        if (p) p.pause()
    }

    function playPause(playerId) {
        var p = _resolvePlayer(playerId)
        if (p) p.togglePlaying()
    }

    function next(playerId) {
        var p = _resolvePlayer(playerId)
        if (p && p.canGoNext) p.next()
    }

    function previous(playerId) {
        var p = _resolvePlayer(playerId)
        if (p && p.canGoPrevious) p.previous()
    }

    // QS MprisPlayer.seek() takes seconds (qreal), NOT microseconds.
    function seek(offsetSeconds, playerId) {
        var p = _resolvePlayer(playerId)
        if (p && p.canSeek) p.seek(offsetSeconds)
    }

    // QS MprisPlayer.position is in seconds (qreal), NOT microseconds.
    function setPosition(positionSeconds, playerId) {
        var p = _resolvePlayer(playerId)
        if (p && p.canSeek) p.position = positionSeconds
    }

    function setVolume(value, playerId) {
        var p = _resolvePlayer(playerId)
        if (p) p.volume = Math.min(Math.max(value, 0.0), 1.0)
    }

    function setShuffle(value, playerId) {
        var p = _resolvePlayer(playerId)
        if (p && p.shuffleSupported) p.shuffle = value
    }

    function setLoopState(state, playerId) {
        var p = _resolvePlayer(playerId)
        if (!p || !p.loopSupported) return
        switch (state) {
            case "none": p.loopState = MprisLoopState.None; break
            case "track": p.loopState = MprisLoopState.Track; break
            case "playlist": p.loopState = MprisLoopState.Playlist; break
        }
    }

    // ======================================================================
    // Private: IPC handler
    // ======================================================================

    IpcHandler {
        target: "music"
        function togglePlay(): void { root.togglePlay() }
        function next(): void { root.next() }
        function previous(): void { root.previous() }
        // IPC only supports primitive return types. Return JSON string.
        function getData(): string {
            return JSON.stringify({
                title: root.title,
                artist: root.artist,
                album: root.album,
                thumbnail: root.thumbnail,
                isPlaying: root.isPlaying,
                duration: root.duration,
                position: root.position,
                shuffle: root.shuffle,
                loopStatus: root.loopStatus
            })
        }
    }

    // ======================================================================
    // Private: position polling timer (1s)
    // ======================================================================

    Timer {
        interval: 1000
        repeat: true
        running: root.isPlaying
        onTriggered: {
            var qsPlayer = root._getActiveQsPlayer()
            if (qsPlayer) {
                // Manually emit positionChanged so we get an updated value.
                // QS MprisPlayer.position only updates reactively on nonlinear
                // changes; we need to poll per the QS docs.
                qsPlayer.positionChanged()
                root.position = qsPlayer.position ?? 0
            }
        }
    }

    // ======================================================================
    // Private: player resolution
    // ======================================================================

    property string _lastTrackTitle: ""

    function _getActiveQsPlayer() {
        var qsPlayers = Mpris.players?.values ?? []
        // Prefer the last playing player; fall back to last in list.
        for (var i = qsPlayers.length - 1; i >= 0; i--) {
            if (qsPlayers[i].isPlaying) return qsPlayers[i]
        }
        return qsPlayers.length > 0 ? qsPlayers[qsPlayers.length - 1] : null
    }

    function _resolvePlayer(playerId) {
        var qsPlayers = Mpris.players?.values ?? []
        if (playerId !== undefined && playerId !== null) {
            for (var i = 0; i < qsPlayers.length; i++) {
                if (_getPlayerId(qsPlayers[i]) === playerId) return qsPlayers[i]
            }
            return null
        }
        return _getActiveQsPlayer()
    }

    function _getPlayerId(qsPlayer) {
        return qsPlayer.identity ?? qsPlayer.desktopEntry ?? ""
    }

    function _mapLoopState(loopState) {
        switch (loopState) {
            case MprisLoopState.None: return "none"
            case MprisLoopState.Track: return "track"
            case MprisLoopState.Playlist: return "playlist"
            default: return "none"
        }
    }

    function _syncActivePlayer() {
        var qsPlayer = _getActiveQsPlayer()
        if (qsPlayer) {
            root.title = qsPlayer.trackTitle ?? "Not Playing"
            root.artist = qsPlayer.trackArtist ?? ""
            root.album = qsPlayer.trackAlbum ?? ""
            root.thumbnail = qsPlayer.trackArtUrl ?? ""
            root.isPlaying = qsPlayer.playbackState === MprisPlaybackState.Playing
            root.duration = qsPlayer.length ?? 0
            root.position = qsPlayer.position ?? 0
            root.isAvailable = (qsPlayer.trackTitle ?? "") !== ""
            root.shuffle = qsPlayer.shuffle ?? false
            root.loopStatus = _mapLoopState(qsPlayer.loopState)
            root.activePlayer = _flattenPlayer(qsPlayer)
        } else {
            root.title = "Not Playing"
            root.artist = ""
            root.album = ""
            root.thumbnail = ""
            root.isPlaying = false
            root.duration = 0
            root.position = 0
            root.isAvailable = false
            root.shuffle = false
            root.loopStatus = "none"
            root.activePlayer = null
        }

        if (root.title !== root._lastTrackTitle && root.title !== "Not Playing") {
            root._lastTrackTitle = root.title
            root.trackChanged({
                title: root.title,
                artist: root.artist,
                artUrl: root.thumbnail
            })
        }
    }

    function _flattenPlayer(p) {
        if (!p) return null
        var status = "stopped"
        if (p.playbackState === MprisPlaybackState.Playing) status = "playing"
        else if (p.playbackState === MprisPlaybackState.Paused) status = "paused"

        return {
            id: _getPlayerId(p),
            identity: p.identity ?? "",
            canControl: p.canControl ?? false,
            canPlay: p.canPlay ?? false,
            canPause: p.canPause ?? false,
            canGoNext: p.canGoNext ?? false,
            canGoPrevious: p.canGoPrevious ?? false,
            canSeek: p.canSeek ?? false,
            playbackStatus: status,
            volume: p.volume ?? 1.0,
            shuffle: p.shuffle ?? false,
            shuffleSupported: p.shuffleSupported ?? false,
            loopStatus: _mapLoopState(p.loopState),
            loopSupported: p.loopSupported ?? false,
            position: p.position ?? 0,
            metadata: {
                title: p.trackTitle ?? "",
                artist: p.trackArtist ?? "",
                album: p.trackAlbum ?? "",
                albumArtist: p.trackAlbumArtist ?? "",
                artUrl: p.trackArtUrl ?? "",
                length: p.length ?? 0
            }
        }
    }

    function _rebuildPlayers() {
        var qsPlayers = Mpris.players?.values ?? []
        var flatPlayers = []
        for (var i = 0; i < qsPlayers.length; i++) {
            flatPlayers.push(_flattenPlayer(qsPlayers[i]))
        }
        root.players = flatPlayers
        _syncActivePlayer()
    }

    // ======================================================================
    // Private: watch for changes
    // ======================================================================

    Timer {
        id: rebuildDebounce
        interval: 50
        repeat: false
        onTriggered: root._rebuildPlayers()
    }

    Connections {
        target: Mpris.players ?? null
        function onValuesChanged() { rebuildDebounce.restart() }
    }

    Component.onCompleted: {
        _rebuildPlayers()
    }
}
