pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services

// Everything the surfaces show, and everything they can ask for.
//
// It holds no logic about OpenSnitch itself: rules are built, counted and
// expired in the backend (src in backend/), and this is a view onto that.
Item {
    id: root

    required property var link

    // Surfaces that are on screen and want live numbers. With none, the backend
    // stops streaming stats; prompts and status changes always come through.
    property int refCount: 0

    readonly property bool available: link.isConnected

    property var nodes: []
    property var settings: ({})
    property var durations: []
    property var prompts: []
    property var events: []
    property var alerts: []
    property string backendVersion: ""

    // The node the UI is about: the first one online, else the first known.
    readonly property var node: {
        for (let i = 0; i < nodes.length; i++)
            if (nodes[i].online)
                return nodes[i];
        return nodes.length > 0 ? nodes[0] : null;
    }
    readonly property bool daemonOnline: node !== null && node.online
    readonly property bool interception: daemonOnline && node.interception
    readonly property var stats: {
        if (!node || !node.stats)
            return null;
        const savedBaseline = settings.statsBaseline;
        if (!savedBaseline || settings.statsBaselineNodeKey !== node.key)
            return node.stats;

        const current = node.stats;
        // A daemon restart starts fresh counters; ignore a baseline from its
        // previous uptime in that case.
        const baseline = current.uptime < savedBaseline.uptime ? ({}) : savedBaseline;
        const result = Object.assign({}, current);
        for (const key of ["dnsResponses", "connections", "ignored", "accepted", "dropped", "ruleHits", "ruleMisses"])
            result[key] = Math.max(0, current[key] - (baseline[key] || 0));
        for (const key of ["byProto", "byAddress", "byHost", "byPort", "byUid", "byExecutable"]) {
            const before = Object.create(null);
            for (const entry of (baseline[key] || []))
                before[entry.key] = entry.count;
            result[key] = (current[key] || []).map(entry => ({
                "key": entry.key,
                "count": Math.max(0, entry.count - (before[entry.key] || 0))
            })).filter(entry => entry.count > 0).sort((a, b) => b.count - a.count).slice(0, 10);
        }
        return result;
    }
    readonly property var rules: node && node.rules ? node.rules : []
    readonly property var daemonConfig: node ? node.config : ({})
    readonly property int pendingCount: prompts.length

    // "off": no daemon, "paused": interception off, "ok": protecting
    readonly property string status: !available ? "backend" : !daemonOnline ? "off" : !interception ? "paused" : "ok"

    signal promptArrived(var prompt)
    signal promptGone(string id)
    signal alertArrived(var alert)

    onRefCountChanged: _syncSubscription()
    onAvailableChanged: if (!available) {
        root.nodes = [];
        root.prompts = [];
    }

    function _syncSubscription() {
        if (!available)
            return;
        link.request(refCount > 0 ? "subscribe" : "unsubscribe", {}, null);
        if (refCount > 0)
            refreshEvents();
    }

    Connections {
        target: root.link

        function onLinkEstablished() {
            root.link.request("hello", {
                "prompts": true
            }, r => {
                if (r.error)
                    return;
                root._apply(r.result);
                root._syncSubscription();
            });
        }

        function onEventReceived(name, data) {
            root._onEvent(name, data);
        }
    }

    function _apply(s) {
        root.nodes = s.nodes || [];
        root.settings = s.settings || ({});
        root.durations = s.durations || [];
        root.prompts = s.prompts || [];
        root.alerts = s.alerts || [];
        root.backendVersion = s.version || "";
        for (const p of root.prompts)
            root.promptArrived(p);
    }

    function refresh() {
        link.request("state", {}, r => {
            if (!r.error)
                root._apply(r.result);
        });
    }

    function refreshEvents() {
        link.request("events", {
            "limit": 500
        }, r => {
            if (!r.error)
                root.events = r.result.events || [];
        });
    }

    function clearEvents() {
        root.events = [];
        link.request("events.clear", {}, r => {
            if (r.error)
                root.refreshEvents();
        });
    }

    // Reset only the Overview counters and top lists from this point onward.
    // OpenSnitch exposes cumulative stats but no daemon-side reset operation.
    function resetStats() {
        if (!node || !node.stats)
            return;
        setSettings({
            "statsBaseline": node.stats,
            "statsBaselineNodeKey": node.key
        });
    }

    function _onEvent(name, d) {
        if (name === "node") {
            const next = root.nodes.slice();
            const i = next.findIndex(n => n.key === d.key);
            if (i >= 0) {
                // stats ride on their own event; keep the last ones
                if (!d.stats && next[i].stats)
                    d.stats = next[i].stats;
                next[i] = d;
            } else {
                next.push(d);
            }
            root.nodes = next;
        } else if (name === "stats") {
            const next = root.nodes.slice();
            const i = next.findIndex(n => n.key === d.node);
            if (i >= 0) {
                next[i] = Object.assign({}, next[i], {
                    "stats": d.stats
                });
                root.nodes = next;
            }
        } else if (name === "events") {
            root.events = root.events.concat(d).slice(-500);
        } else if (name === "settings") {
            root.settings = d;
        } else if (name === "prompt") {
            if (!root.prompts.some(p => p.id === d.id)) {
                root.prompts = root.prompts.concat([d]);
                root.promptArrived(d);
            }
        } else if (name === "prompt.done") {
            root.prompts = root.prompts.filter(p => p.id !== d.id);
            root.promptGone(d.id);
        } else if (name === "alert") {
            root.alerts = root.alerts.concat([d]).slice(-100);
            root.alertArrived(d);
        }
    }

    // ---- actions -----------------------------------------------------------

    function _call(method, params, done) {
        link.request(method, params, r => {
            if (r.error) {
                ToastService.showError("OpenSnitch", r.error);
                // The backend's idea of the state may differ from what a
                // switch just showed; ask again.
                root.refresh();
            }
            if (done)
                done(r);
        });
    }

    function setInterception(enabled) {
        _call("interception.set", {
            "node": node ? node.key : "",
            "enabled": enabled
        });
    }

    function setSystemFirewall(enabled) {
        _call("firewall.set", {
            "node": node ? node.key : "",
            "enabled": enabled
        });
    }

    // Default policy of the opensnitch input / output chains: "accept" | "drop".
    function setFirewallPolicy(hook, policy) {
        _call("firewall.policy", {
            "node": node ? node.key : "",
            "hook": hook,
            "policy": policy
        });
    }

    // Daemon-side options (DefaultAction, LogLevel, FwOptions.QueueBypass, ...).
    function setDaemonConfig(changes) {
        _call("config.set", {
            "node": node ? node.key : "",
            "changes": changes
        });
    }

    // UI-side preferences (prompt timeout, defaults, ...).
    function setSettings(changes) {
        _call("settings.set", {
            "changes": changes
        });
    }

    function answerPrompt(id, answer, done) {
        link.request("prompt.answer", {
            "id": id,
            "answer": answer
        }, r => {
            if (done)
                done(r);
        });
    }

    function ruleAction(kind, name) {
        _call("rule." + kind, {
            "node": node ? node.key : "",
            "name": name
        });
    }

    function saveRule(rule, done) {
        _call("rule.set", {
            "node": node ? node.key : "",
            "rule": rule
        }, done);
    }

    // Convenience for the switches: the daemon's own default action.
    readonly property string defaultAction: daemonConfig && daemonConfig.DefaultAction ? daemonConfig.DefaultAction : settings.defaultAction || "deny"
}
