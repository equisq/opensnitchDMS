pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

// The plugin's headless core: it owns the backend process, the shared state,
// the big window and the authorization prompt.
//
// The bar widget reaches it through
// PluginService.pluginDaemonInstances["opensnitch"] and shares the "open"
// global var with it to open the window.
PluginComponent {
    id: root

    property var popoutService: null

    readonly property alias core: osCore
    readonly property alias link: osLink

    PluginGlobalVar {
        id: openVar

        varName: "open"
        defaultValue: false
    }

    OpenSnitchLink {
        id: osLink

        pluginDir: Qt.resolvedUrl(".")
        listenAddress: root.pluginData.listenAddress || "unix:///tmp/osui.sock"
    }

    OpenSnitchCore {
        id: osCore

        link: osLink

        onAlertArrived: alert => {
            if (alert.type === "error")
                ToastService.showError("OpenSnitch", alert.text);
            else if (alert.type === "warning")
                ToastService.showWarning("OpenSnitch", alert.text);
        }
    }

    OpenSnitchWindow {
        id: window

        core: osCore
    }

    OpenSnitchPrompt {
        id: prompt

        core: osCore
    }

    function openWindow() {
        openVar.set(true);
    }

    Connections {
        target: openVar

        function onValueChanged() {
            if (openVar.value)
                window.show();
            else
                window.hide();
        }
    }

    Connections {
        target: window

        function onShouldBeVisibleChanged() {
            openVar.set(window.shouldBeVisible);
        }
    }

    IpcHandler {
        target: "opensnitch"

        function toggle(): string {
            openVar.set(!openVar.value);
            return openVar.value ? "OPENSNITCH_OPEN" : "OPENSNITCH_CLOSED";
        }

        function open(): string {
            openVar.set(true);
            return "OPENSNITCH_OPEN";
        }

        function close(): string {
            openVar.set(false);
            return "OPENSNITCH_CLOSED";
        }

        // dms ipc call opensnitch interception on|off
        function interception(state: string): string {
            if (!osCore.daemonOnline)
                return "OPENSNITCH_UNAVAILABLE: the daemon is not connected";
            osCore.setInterception(state === "on" || state === "true" || state === "1");
            return "OPENSNITCH_OK";
        }

        function status(): string {
            if (!osCore.available)
                return "OPENSNITCH_UNAVAILABLE: the backend is not running";
            return `OPENSNITCH_STATUS: ${osCore.status} pending=${osCore.pendingCount} rules=${osCore.rules.length}`;
        }
    }
}
