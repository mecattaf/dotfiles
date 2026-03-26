// MprisBridge.qml -- Port of current-dotfiles MusicPlayerProvider.qml
// Uses Quickshell.Services.Mpris. Exposes active player (last in list),
// title, artist, album, thumbnail, isPlaying, duration, position.
// IPC handler (target: "music", togglePlay/next/previous/getData).

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

Scope {
    id: root

    // ======================================================================
    // Reactive properties (os.media)
    // ======================================================================

    // All players flattened for WebChannel
    property var players: []

    // Active player: last in Mpris.players list (current dotfiles pattern)
    property var activePlayer: null

    // Convenience properties (matching current dotfiles API)
    property string title: ""
    property string artist: ""
    property string album: ""
    property string thumbnail: ""
    property bool isPlaying: false
    property int duration: 0
    property int position: 0
    property bool isAvailable: false

    // ======================================================================
    // Signals
    // ======================================================================

    signal trackChanged(var event)

    // ======================================================================
    // Methods (os.media)
    // ======================================================================

    function togglePlay() {
        var qsPlayer = _getActiveQsPlayer()
        if (!qsPlayer) return
        if (qsPlayer.playbackState === MprisPlaybackState.Playing) {
            qsPlayer.pause()
        } else {
            qsPlayer.play()
        }
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

    function seek(offsetSeconds, playerId) {
        var p = _resolvePlayer(playerId)
        if (p && p.canSeek) p.seek(offsetSeconds * 1000000)
    }

    function setPosition(positionSeconds, playerId) {
        var p = _resolvePlayer(playerId)
        if (p && p.canSeek) p.position = positionSeconds * 1000000
    }

    function setVolume(value, playerId) {
        var p = _resolvePlayer(playerId)
        if (p) p.volume = Math.min(Math.max(value, 0.0), 1.0)
    }

    // ======================================================================
    // IPC handler (from current dotfiles)
    // ======================================================================

    IpcHandler {
        target: "music"
        function togglePlay() { root.togglePlay() }
        function next() { root.next() }
        function previous() { root.previous() }
        function getData() {
            return {
                title: root.title,
                artist: root.artist,
                album: root.album,
                thumbnail: root.thumbnail,
                isPlaying: root.isPlaying,
                duration: root.duration,
                position: root.position
            }
        }
    }

    // ======================================================================
    // Position polling timer (1s, from current dotfiles)
    // ======================================================================

    Timer {
        interval: 1000
        repeat: true
        running: root.isPlaying
        onTriggered: {
            var qsPlayer = root._getActiveQsPlayer()
            if (qsPlayer) {
                root.position = qsPlayer.position ?? 0
            }
        }
    }

    // ======================================================================
    // Internal: player resolution
    // ======================================================================

    property string _lastTrackTitle: ""

    function _getActiveQsPlayer() {
        var qsPlayers = Mpris.players?.values ?? []
        // Current dotfiles pattern: last player in list
        return qsPlayers.length > 0 ? qsPlayers[qsPlayers.length - 1] : null
    }

    function _resolvePlayer(playerId) {
        var qsPlayers = Mpris.players?.values ?? []
        if (playerId !== undefined && playerId !== null) {
            return qsPlayers.find(function(p) {
                return (p.identity ?? p.desktopEntry ?? "") === playerId
            }) ?? null
        }
        return _getActiveQsPlayer()
    }

    function _getPlayerId(qsPlayer) {
        return qsPlayer.identity ?? qsPlayer.desktopEntry ?? ""
    }

    // ======================================================================
    // Sync convenience properties from active player
    // ======================================================================

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
            root.activePlayer = null
        }

        // Track change detection
        if (root.title !== root._lastTrackTitle && root.title !== "Not Playing") {
            root._lastTrackTitle = root.title
            root.trackChanged({
                title: root.title,
                artist: root.artist,
                artUrl: root.thumbnail
            })
        }
    }

    // ======================================================================
    // Flatten player for WebChannel
    // ======================================================================

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
            position: p.position ?? 0,
            metadata: {
                title: p.trackTitle ?? "",
                artist: p.trackArtist ?? "",
                album: p.trackAlbum ?? "",
                artUrl: p.trackArtUrl ?? "",
                length: p.length ?? 0
            }
        }
    }

    // ======================================================================
    // Rebuild players array from ObjectModel
    // ======================================================================

    function _rebuildPlayers() {
        var qsPlayers = Mpris.players?.values ?? []
        root.players = qsPlayers.map(function(p) { return _flattenPlayer(p) })
        _syncActivePlayer()
    }

    // ======================================================================
    // Watch for changes
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
