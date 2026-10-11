pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// The link to bin/opensnitch-dmsd.
//
// That process is the OpenSnitch UI proper: it is the gRPC server the
// (unmodified) opensnitchd connects to. This plugin owns it -- starts it,
// restarts it if it dies -- and talks to it in JSON lines over a unix socket.
Item {
    id: root

    property string pluginDir: ""
    // Server.Address of the daemon's config, as the daemon spells it.
    property string listenAddress: "unix:///tmp/osui.sock"

    readonly property bool isConnected: socket.linkUp
    property bool backendRunning: false

    // Events pushed by the backend: {event, data}.
    signal eventReceived(string name, var data)
    // Emitted after every (re)connect, before anything else, so the core can
    // say hello and resync.
    signal linkEstablished

    property int _nextId: 1
    property var _pending: ({})

    readonly property string _socketPath: {
        const runtimeDir = Quickshell.env("XDG_RUNTIME_DIR");
        return (runtimeDir ? runtimeDir : "/tmp") + "/dms-opensnitch.sock";
    }

    readonly property string _binary: {
        let dir = root.pluginDir;
        if (dir.startsWith("file://"))
            dir = dir.substring(7);
        if (dir.endsWith("/"))
            dir = dir.slice(0, -1);
        return dir + "/bin/opensnitch-dmsd";
    }

    function request(method, params, callback) {
        if (!socket.linkUp) {
            if (callback)
                callback({
                    "error": I18n.trFor("opensnitch", "The OpenSnitch backend is not running")
                });
            return;
        }
        const id = root._nextId++;
        if (callback)
            root._pending[id] = callback;
        socket.send(JSON.stringify({
            "id": id,
            "method": method,
            "params": params || {}
        }));
    }

    Process {
        id: backend

        command: [root._binary, "-socket", root._socketPath, "-listen", root.listenAddress]

        stderr: SplitParser {
            onRead: line => {
                if (!line)
                    return;
                if (line.indexOf("ERROR") >= 0)
                    console.warn("opensnitch-dmsd:", line);
                else
                    console.log("opensnitch-dmsd:", line);
            }
        }

        onStarted: {
            root.backendRunning = true;
            redial.start();
        }
        onExited: exitCode => {
            root.backendRunning = false;
            if (exitCode !== 0)
                console.warn("opensnitch: backend exited with", exitCode);
        }
    }

    // Dial again quickly while the backend is starting up.
    Timer {
        id: redial

        property int attempts: 0

        interval: 250
        repeat: true
        onRunningChanged: if (running)
            attempts = 0
        onTriggered: {
            if (socket.linkUp || !backend.running || ++attempts > 40) {
                stop();
                return;
            }
            socket.connected = false;
            socket.connected = true;
        }
    }

    // Starts the backend only when nothing answers the socket, and restarts the
    // connection when it drops. A backend left over from a previous shell is
    // served rather than fought over.
    Timer {
        interval: 2000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            if (socket.linkUp)
                return;
            if (!backend.running)
                backend.running = true;
            else if (!redial.running) {
                socket.connected = false;
                socket.connected = true;
            }
        }
    }

    // DankSocket is the shell's own socket wrapper (the chat plugin uses the
    // same one): it keeps retrying, reports `linkUp`, and `send` ends a line
    // for us.
    DankSocket {
        id: socket

        path: root._socketPath
        connected: true

        parser: SplitParser {
            onRead: line => {
                if (!line)
                    return;
                let msg;
                try {
                    msg = JSON.parse(line);
                } catch (e) {
                    console.warn("opensnitch: unreadable line from backend:", line.substring(0, 200));
                    return;
                }
                try {
                    root._handle(msg);
                } catch (e) {
                    console.warn("opensnitch: failed handling a message:", e);
                }
            }
        }

        onConnectionStateChanged: {
            if (socket.linkUp) {
                root.linkEstablished();
                return;
            }
            const pending = root._pending;
            root._pending = ({});
            for (const id in pending)
                pending[id]({
                    "error": I18n.trFor("opensnitch", "Lost the connection to the OpenSnitch backend")
                });
        }
    }

    function _handle(msg) {
        if (msg.event !== undefined) {
            root.eventReceived(msg.event, msg.data);
            return;
        }
        const cb = root._pending[msg.id];
        if (!cb)
            return;
        delete root._pending[msg.id];
        cb(msg);
    }
}
