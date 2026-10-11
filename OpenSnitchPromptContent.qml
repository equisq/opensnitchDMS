pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets

// The authorization prompt: what the Qt popup asks, in the same order -- who
// is connecting where, what the rule should match, for how long, and the
// verdict -- with the same countdown that applies the default action.
Item {
    id: root

    required property var core
    signal closeRequested

    readonly property var prompt: core.prompts.length > 0 ? core.prompts[0] : null
    readonly property string promptId: prompt ? prompt.id : ""
    readonly property var conn: prompt ? prompt.conn : null
    readonly property var app: prompt ? prompt.app : null
    readonly property var opts: prompt ? prompt.options : null

    // selections (reset per prompt)
    property int target: 0
    property int ipTarget: 0
    property int duration: 7
    property bool advanced: false
    property bool chkIp: false
    property bool chkPort: false
    property bool chkUid: false
    property bool chkSum: false
    property string denyMode: "deny"
    property bool denyMenu: false
    property bool details: false
    property bool submitting: false

    property int remaining: 0
    property bool counting: false

    // Anything that can be clicked is a decision being made: stop the clock,
    // as the Qt dialog does on any mouse press.
    function stopCountdown() {
        counting = false;
    }

    onPromptIdChanged: {
        if (!prompt) {
            counting = false;
            return;
        }
        const d = prompt.defaults;
        target = d.target;
        ipTarget = d.ipTarget;
        duration = d.duration;
        advanced = d.advanced;
        chkIp = d.dstIp;
        chkPort = d.dstPort;
        chkUid = d.uid;
        chkSum = d.checksum;
        denyMode = d.action === "reject" ? "reject" : "deny";
        denyMenu = false;
        details = false;
        submitting = false;
        remaining = prompt.timeout;
        counting = prompt.timeout > 0;
        scroller.contentY = 0;
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.counting && root.prompt !== null
        onTriggered: {
            root.remaining -= 1;
            if (root.remaining <= 0) {
                root.counting = false;
                root.submit(root.prompt.defaults.action);
            }
        }
    }

    function submit(action) {
        if (!prompt || submitting)
            return;
        submitting = true;
        core.answerPrompt(prompt.id, {
            "action": action,
            "target": target,
            "ipTarget": ipTarget,
            "duration": duration,
            "advanced": advanced,
            "dstIp": chkIp,
            "dstPort": chkPort,
            "uid": chkUid,
            "checksum": chkSum
        }, r => {
            submitting = false;
            if (r.error)
                ToastService.showError("OpenSnitch", r.error);
        });
    }

    function esc(s) {
        return String(s === undefined || s === null ? "" : s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    readonly property string message: {
        if (!conn)
            return "";
        const name = "<b>" + esc(app && app.name ? app.name : I18n.trFor("opensnitch", "Outgoing connection")) + "</b>";
        const who = prompt.local ? name : I18n.trFor("opensnitch", "<b>Remote</b> process %1 on <b>%2</b>").arg(name).arg(esc(prompt.hostname));
        const dest = "<b>" + esc(conn.dstHost || conn.dstIp) + "</b>";
        const proto = String(conn.protocol).toUpperCase();
        if (conn.dstPort === 53 && conn.dstHost && conn.dstHost !== conn.dstIp)
            return I18n.trFor("opensnitch", "%1 is attempting to resolve %2 via %3, %4 port 53").arg(who).arg(dest).arg(esc(conn.dstIp)).arg(proto);
        if (conn.dstPort === 0)
            return I18n.trFor("opensnitch", "%1 is connecting to %2, %3").arg(who).arg(dest).arg(proto);
        return I18n.trFor("opensnitch", "%1 is connecting to %2 on %3 port %4").arg(who).arg(dest).arg(proto).arg(conn.dstPort);
    }

    readonly property string argsText: conn ? conn.processArgs.join(" ") : ""
    readonly property bool hasMd5: conn ? conn.md5 !== "" : false
    readonly property var promptNode: prompt ? core.nodes.find(n => n.key === prompt.node) || null : null
    property string updatingChecksumRule: ""
    readonly property var checksumMismatches: {
        if (!promptNode || !conn || !hasMd5 || !conn.processPath)
            return [];

        const mismatches = [];
        const collect = (operator, leaves) => {
            if (!operator)
                return;
            if (operator.type === "list" && operator.list && operator.list.length) {
                for (const child of operator.list)
                    collect(child, leaves);
            } else {
                leaves.push(operator);
            }
        };

        for (const rule of (promptNode.rules || [])) {
            if (!rule.enabled || rule.duration === "once" || (rule.expires && rule.expires * 1000 <= Date.now()))
                continue;
            const leaves = [];
            collect(rule.operator, leaves);
            const matchesPath = leaves.some(op => op.operand === "process.path" && op.data === conn.processPath);
            if (!matchesPath)
                continue;
            for (const op of leaves) {
                if (op.operand === "process.hash.md5" && op.data && op.data.toLowerCase() !== conn.md5.toLowerCase()) {
                    mismatches.push({"rule": rule, "expected": op.data});
                    break;
                }
            }
        }
        return mismatches;
    }

    function updateChecksumRule(item) {
        if (!prompt || !conn || !conn.md5 || !item || !item.rule)
            return;
        stopCountdown();
        updatingChecksumRule = item.rule.name;
        const updated = JSON.parse(JSON.stringify(item.rule));
        const replaceHash = operator => {
            if (!operator)
                return;
            if (operator.type === "list" && operator.list) {
                for (const child of operator.list)
                    replaceHash(child);
            } else if (operator.operand === "process.hash.md5") {
                operator.data = conn.md5;
            }
        };
        replaceHash(updated.operator);
        core.link.request("rule.set", {"node": prompt.node, "rule": updated}, result => {
            updatingChecksumRule = "";
            if (result.error) {
                ToastService.showError("OpenSnitch", result.error);
                return;
            }
            core.refresh();
            ToastService.showInfo("OpenSnitch", I18n.trFor("opensnitch", "Checksum updated for %1").arg(item.rule.name));
        });
    }

    function durationLabel(id) {
        const labels = {
            "once": I18n.trFor("opensnitch", "once"),
            "30s": I18n.trFor("opensnitch", "30 seconds"),
            "5m": I18n.trFor("opensnitch", "5 minutes"),
            "15m": I18n.trFor("opensnitch", "15 minutes"),
            "30m": I18n.trFor("opensnitch", "30 minutes"),
            "1h": I18n.trFor("opensnitch", "1 hour"),
            "12h": I18n.trFor("opensnitch", "12 hours"),
            "until restart": I18n.trFor("opensnitch", "until reboot"),
            "always": I18n.trFor("opensnitch", "forever")
        };
        return labels[id] || id;
    }

    function optionLabel(option) {
        const kind = option.kind;
        if (kind === "process_path") return I18n.trFor("opensnitch", "from this executable");
        if (kind === "process_args") return I18n.trFor("opensnitch", "from this command line");
        if (kind === "process_id") return I18n.trFor("opensnitch", "from this PID");
        if (kind === "user_id") return I18n.trFor("opensnitch", "from user %1").arg(option.label.replace(/^from user /, ""));
        if (kind === "dst_port") return I18n.trFor("opensnitch", "to port %1").arg(option.label.replace(/^to port /, ""));
        if (kind === "dst_ip" || kind === "dst_network" || kind === "simple_host" || kind === "regex_host" || kind === "regex_ip")
            return I18n.trFor("opensnitch", "to %1").arg(option.label.replace(/^to /, ""));
        if (kind === "appimage_path" || kind === "snap_path")
            return I18n.trFor("opensnitch", "from %1").arg(option.label.replace(/^from /, ""));
        return option.label;
    }

    function listModel(list) {
        return (list || []).map(o => ({
                    "label": optionLabel(o),
                    "enabled": o.enabled
                }));
    }

    function actionLabel(a) {
        return a === "allow" ? I18n.trFor("opensnitch", "Allow") : a === "reject" ? I18n.trFor("opensnitch", "Reject") : I18n.trFor("opensnitch", "Deny");
    }

    MouseArea {
        anchors.fill: parent
        z: 100
        // observe only: never takes the click away from what is under it
        propagateComposedEvents: true
        onPressed: mouse => {
            root.stopCountdown();
            mouse.accepted = false;
        }
    }

    Flickable {
        id: scroller

        anchors.fill: parent
        contentWidth: width
        contentHeight: page.implicitHeight + 40 + verdictBar.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: page

            x: 24
            y: 24
            width: scroller.width - 48
            spacing: 16

            // ---- who ---------------------------------------------------
            RowLayout {
                Layout.fillWidth: true
                spacing: 16

                Rectangle {
                    Layout.preferredWidth: 64
                    Layout.preferredHeight: 64
                    radius: Theme.cornerRadius
                    color: Theme.primary

                    Image {
                        id: appIcon

                        anchors.centerIn: parent
                        width: 40
                        height: 40
                        sourceSize: Qt.size(80, 80)
                        source: root.app && root.app.icon ? Quickshell.iconPath(root.app.icon, true) : ""
                        visible: status === Image.Ready
                        fillMode: Image.PreserveAspectFit
                    }
                    DankIcon {
                        anchors.centerIn: parent
                        visible: !appIcon.visible
                        name: "shield"
                        size: 32
                        color: Theme.onPrimary
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    StyledText {
                        Layout.fillWidth: true
                        text: root.app && root.app.name ? root.app.name : I18n.trFor("opensnitch", "Outgoing connection")
                        font.pixelSize: Theme.fontSizeXLarge
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: root.conn && root.conn.processPath !== ""
                        text: root.conn ? root.conn.processPath : ""
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        elide: Text.ElideMiddle
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: text !== "" && text !== (root.conn ? root.conn.processPath : "")
                        text: root.argsText
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    visible: root.core.prompts.length > 1
                    Layout.preferredHeight: 28
                    Layout.preferredWidth: queueText.implicitWidth + 20
                    radius: Theme.cornerRadius
                    color: Theme.errorContainer
                    StyledText {
                        id: queueText

                        anchors.centerIn: parent
                        text: I18n.trFor("opensnitch", "%1 waiting").arg("+" + (root.core.prompts.length - 1))
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.DemiBold
                        color: Theme.onErrorContainer
                    }
                }

                OsIconButton {
                    icon: root.details ? "close" : "info"
                    tonal: true
                    onClicked: {
                        root.details = !root.details;
                        root.stopCountdown();
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.app && root.app.description !== undefined && root.app.description !== ""
                text: root.app ? root.app.description : ""
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }

            // ---- what --------------------------------------------------
            OsCard {
                Layout.fillWidth: true
                tone: "primaryAction"
                padding: 18
                StyledText {
                    Layout.fillWidth: true
                    text: root.message
                    textFormat: Text.StyledText
                    wrapMode: Text.WordWrap
                    font.pixelSize: Theme.fontSizeLarge
                    color: Theme.onPrimary
                }
            }

            OsCard {
                Layout.fillWidth: true
                visible: root.checksumMismatches.length > 0
                tone: "error"
                padding: 14
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    DankIcon {
                        name: "warning"
                        size: 22
                        color: Theme.error
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        StyledText {
                            Layout.fillWidth: true
                            text: I18n.trFor("opensnitch", "Checksum mismatch")
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.DemiBold
                            color: Theme.error
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: I18n.trFor("opensnitch", "This executable's MD5 differs from an active rule. Review the affected rules before allowing it.")
                            wrapMode: Text.WordWrap
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceText
                        }
                    }
                }

                Repeater {
                    model: root.checksumMismatches
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 8

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            StyledText {
                                Layout.fillWidth: true
                                text: modelData.rule.name
                                elide: Text.ElideRight
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.DemiBold
                                color: Theme.surfaceText
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: I18n.trFor("opensnitch", "Expected %1 · Current %2").arg(modelData.expected).arg(root.conn.md5)
                                elide: Text.ElideMiddle
                                font.pixelSize: Theme.fontSizeSmall
                                font.family: Theme.monoFontFamily
                                color: Theme.surfaceVariantText
                            }
                        }
                        OsButton {
                            text: I18n.trFor("opensnitch", "Update rule")
                            icon: "refresh"
                            compact: true
                            variant: "errorTonal"
                            busy: root.updatingChecksumRule === modelData.rule.name
                            enabled: root.updatingChecksumRule === ""
                            onClicked: root.updateChecksumRule(modelData)
                        }
                    }
                }
            }

            // ---- connection details / process details ------------------
            OsCard {
                Layout.fillWidth: true
                visible: !root.details
                padding: 16
                spacing: 6

                Repeater {
                    model: root.conn ? [
                        {
                            "k": I18n.trFor("opensnitch", "Source"),
                            "v": root.conn.srcIp + (root.conn.srcPort ? ":" + root.conn.srcPort : ""),
                            "show": true
                        },
                        {
                            "k": I18n.trFor("opensnitch", "Destination IP"),
                            "v": root.conn.dstIp,
                            "show": true
                        },
                        {
                            "k": I18n.trFor("opensnitch", "Destination port"),
                            "v": String(root.conn.dstPort),
                            "show": root.conn.dstPort !== 0
                        },
                        {
                            "k": I18n.trFor("opensnitch", "User"),
                            "v": root.conn.userLabel || String(root.conn.userId),
                            "show": true
                        },
                        {
                            "k": I18n.trFor("opensnitch", "Launched from"),
                            "v": root.conn.processCwd,
                            "show": root.conn.processCwd !== ""
                        },
                        {
                            "k": I18n.trFor("opensnitch", "MD5"),
                            "v": root.conn.md5,
                            "show": root.advanced && root.hasMd5
                        }
                    ].filter(x => x.show) : []

                    delegate: RowLayout {
                        id: infoRow

                        required property var modelData

                        Layout.fillWidth: true
                        spacing: 12
                        StyledText {
                            Layout.preferredWidth: 120
                            text: infoRow.modelData.k
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: infoRow.modelData.v
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeMedium
                            elide: Text.ElideMiddle
                        }
                    }
                }
            }

            OsCard {
                Layout.fillWidth: true
                visible: root.details
                padding: 16
                spacing: 8

                Repeater {
                    model: root.conn ? [
                        {
                            "k": I18n.trFor("opensnitch", "Executable"),
                            "v": root.conn.processPath
                        },
                        {
                            "k": I18n.trFor("opensnitch", "Command line"),
                            "v": root.argsText
                        },
                        {
                            "k": I18n.trFor("opensnitch", "Working dir"),
                            "v": root.conn.processCwd
                        },
                        {
                            "k": I18n.trFor("opensnitch", "PID"),
                            "v": String(root.conn.processId)
                        },
                        {
                            "k": I18n.trFor("opensnitch", "User"),
                            "v": root.conn.userLabel || String(root.conn.userId)
                        },
                        {
                            "k": I18n.trFor("opensnitch", "Protocol"),
                            "v": String(root.conn.protocol).toUpperCase()
                        },
                        {
                            "k": I18n.trFor("opensnitch", "Source"),
                            "v": root.conn.srcIp + ":" + root.conn.srcPort
                        },
                        {
                            "k": I18n.trFor("opensnitch", "Destination"),
                            "v": (root.conn.dstHost ? root.conn.dstHost + " " : "") + root.conn.dstIp + ":" + root.conn.dstPort
                        },
                        {
                            "k": I18n.trFor("opensnitch", "MD5"),
                            "v": root.conn.md5
                        },
                        {
                            "k": I18n.trFor("opensnitch", "Node"),
                            "v": root.prompt.local ? "this computer" : root.prompt.hostname
                        }
                    ].filter(x => x.v !== "") : []

                    delegate: RowLayout {
                        id: detailRow

                        required property var modelData

                        Layout.fillWidth: true
                        spacing: 12
                        StyledText {
                            Layout.preferredWidth: 100
                            Layout.alignment: Qt.AlignTop
                            text: detailRow.modelData.k
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: detailRow.modelData.v
                            wrapMode: Text.WrapAnywhere
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeSmall
                            font.family: Theme.monoFontFamily
                        }
                    }
                }
            }

            // ---- rule: target, duration, advanced ----------------------
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10
                visible: !root.details

                OsSelect {
                    Layout.fillWidth: true
                    label: I18n.trFor("opensnitch", "Apply to connections")
                    model: root.listModel(root.opts ? root.opts.targets : [])
                    currentIndex: root.target
                    onActivated: i => {
                        root.target = i;
                        root.stopCountdown();
                    }
                }

                OsSelect {
                    Layout.fillWidth: true
                    label: I18n.trFor("opensnitch", "For")
                    model: root.prompt ? root.prompt.durations.map(d => ({
                                "label": root.durationLabel(d.id)
                            })) : []
                    currentIndex: root.duration
                    onActivated: i => {
                        root.duration = i;
                        root.stopCountdown();
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    StyledText {
                        text: I18n.trFor("opensnitch", "Advanced")
                        Layout.fillWidth: true
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeMedium
                    }
                    OsSwitch {
                        checked: root.advanced
                        onToggled: v => {
                            root.advanced = v;
                            root.stopCountdown();
                        }
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    visible: root.advanced
                    spacing: 8
                    OsChip {
                        text: I18n.trFor("opensnitch", "Destination IP")
                        compact: true
                        selected: root.chkIp
                        onClicked: root.chkIp = !root.chkIp
                    }
                    OsChip {
                        visible: root.conn && root.conn.dstPort !== 0
                        text: I18n.trFor("opensnitch", "Port %1").arg(root.conn ? root.conn.dstPort : "")
                        compact: true
                        selected: root.chkPort
                        onClicked: root.chkPort = !root.chkPort
                    }
                    OsChip {
                        text: I18n.trFor("opensnitch", "User ID")
                        compact: true
                        selected: root.chkUid
                        onClicked: root.chkUid = !root.chkUid
                    }
                    OsChip {
                        visible: root.hasMd5
                        text: I18n.trFor("opensnitch", "Checksum")
                        compact: true
                        selected: root.chkSum
                        onClicked: root.chkSum = !root.chkSum
                    }
                }

                OsSelect {
                    Layout.fillWidth: true
                    visible: root.advanced && root.chkIp
                    label: I18n.trFor("opensnitch", "Destination IP matches")
                    model: root.listModel(root.opts ? root.opts.ipTargets : [])
                    currentIndex: root.ipTarget
                    onActivated: i => {
                        root.ipTarget = i;
                        root.stopCountdown();
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: root.denyMenu
                spacing: 8
                OsChip {
                    text: I18n.trFor("opensnitch", "Drop")
                    compact: true
                    selected: root.denyMode === "deny"
                    onClicked: {
                        root.denyMode = "deny";
                        root.denyMenu = false;
                    }
                }
                OsChip {
                    text: I18n.trFor("opensnitch", "Reject")
                    compact: true
                    selected: root.denyMode === "reject"
                    onClicked: {
                        root.denyMode = "reject";
                        root.denyMenu = false;
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    text: I18n.trFor("opensnitch", "Reject tells the app straight away; drop makes it wait.")
                    wrapMode: Text.WordWrap
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }
            }
        }
    }

    // Always-visible verdict bar, floating over the bottom of the scroller.
    Item {
        id: verdictBar

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: barRow.implicitHeight + 32

            RowLayout {
                id: barRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 24
                anchors.bottomMargin: 16
                spacing: 12

                // Deny / Reject split button
                RowLayout {
                    spacing: 3
                    OsButton {
                        text: root.actionLabel(root.denyMode) + (root.counting && root.prompt && root.prompt.defaults.action !== "allow" ? " (" + root.remaining + ")" : "")
                        icon: root.denyMode === "reject" ? "block" : "gpp_bad"
                        variant: "neutral"
                        enabled: !root.submitting
                        onClicked: root.submit(root.denyMode)
                    }
                    OsIconButton {
                        icon: root.denyMenu ? "expand_less" : "expand_more"
                        tonal: true
                        onClicked: {
                            root.denyMenu = !root.denyMenu;
                            root.stopCountdown();
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                OsButton {
                    text: I18n.trFor("opensnitch", "Allow") + (root.counting && root.prompt && root.prompt.defaults.action === "allow" ? " (" + root.remaining + ")" : "")
                    icon: "check_circle"
                    variant: "filled"
                    enabled: !root.submitting
                    onClicked: root.submit("allow")
                }
            }
    }
}
