pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property bool dsearchAvailable: false
    property bool supportsTypeFilter: false

    Component.onCompleted: {
        _checkAvailable();
    }

    function _checkAvailable() {
        checkProc.running = true;
    }

    Process {
        id: checkProc
        command: ["which", "dsearch"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                root.dsearchAvailable = (checkProc.exitCode === 0);
                if (root.dsearchAvailable)
                    versionProc.running = true;
            }
        }
    }

    Process {
        id: versionProc
        command: ["dsearch", "version", "--json"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(this.text);
                    root.supportsTypeFilter = (data.schema_version || 0) >= 2;
                } catch(e) {}
            }
        }
    }

    property var _callback: null

    function search(query, params, callback) {
        if (!dsearchAvailable) return;
        _callback = callback;
        var args = ["dsearch", "search", "--json", "--limit", String(params.limit || 20)];
        if (params.fuzzy) args.push("--fuzzy");
        if (params.sort) { args.push("--sort"); args.push(params.sort); }
        if (params.type && params.type !== "all" && supportsTypeFilter) { args.push("--type"); args.push(params.type); }
        if (params.ext) { args.push("--ext"); args.push(params.ext); }
        if (params.folder) { args.push("--folder"); args.push(params.folder); }
        args.push(query);
        searchProc.command = args;
        searchProc.running = true;
    }

    Process {
        id: searchProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                if (root._callback) {
                    try {
                        var result = JSON.parse(this.text);
                        root._callback({ result: result });
                    } catch(e) {
                        root._callback({ error: "parse error" });
                    }
                    root._callback = null;
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (this.text && root._callback) {
                    root._callback({ error: this.text });
                    root._callback = null;
                }
            }
        }
    }
}
