pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets

Flickable {
    id: root

    required property var core
    readonly property var s: core.settings
    readonly property var cfg: core.daemonConfig || ({})
    readonly property var fw: core.node ? core.node.sysFirewall : ({
            "known": false
        })

    readonly property var targets: [I18n.trFor("opensnitch", "from this executable"), I18n.trFor("opensnitch", "from this command line"), I18n.trFor("opensnitch", "to port"), I18n.trFor("opensnitch", "to IP"), I18n.trFor("opensnitch", "from user"), I18n.trFor("opensnitch", "from this PID")]
    readonly property var logLevels: [I18n.trFor("opensnitch", "Trace"), I18n.trFor("opensnitch", "Debug"), I18n.trFor("opensnitch", "Info"), I18n.trFor("opensnitch", "Warning"), I18n.trFor("opensnitch", "Error"), I18n.trFor("opensnitch", "Important")]
    readonly property var monitors: ["ebpf", "proc", "audit", "ftrace"]
    readonly property var backends: ["nftables", "iptables"]

    contentWidth: width
    contentHeight: col.implicitHeight + 64
    clip: true
    boundsBehavior: Flickable.StopAtBounds

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

    function idx(list, v, fallback) {
        const i = list.indexOf(v);
        return i >= 0 ? i : (fallback === undefined ? 0 : fallback);
    }

    ColumnLayout {
        id: col

        x: 32
        y: 28
        width: root.width - 64
        spacing: 16

        OsPageHeader {
            Layout.fillWidth: true
            title: I18n.trFor("opensnitch", "Settings")
            subtitle: I18n.trFor("opensnitch", "Prompt behaviour is kept by this plugin; daemon options are sent to opensnitchd")
        }

        // ---- protection ---------------------------------------------
        OsCard {
            Layout.fillWidth: true
            spacing: 16
            StyledText {
                text: I18n.trFor("opensnitch", "Protection")
                font.pixelSize: Theme.fontSizeLarge
                font.weight: Font.Bold
                color: Theme.surfaceText
            }
            OsRow {
                title: I18n.trFor("opensnitch", "Intercept connections")
                description: I18n.trFor("opensnitch", "Turn the filtering off and on without stopping the daemon.")
                OsSwitch {
                    enabled: root.core.daemonOnline
                    checked: root.core.interception
                    onToggled: v => root.core.setInterception(v)
                }
            }
            OsRow {
                visible: root.fw.known
                title: I18n.trFor("opensnitch", "System firewall")
                description: root.fw.known ? I18n.trFor("opensnitch", "%1 chains, %2 rules managed by OpenSnitch (editing them is done in the Qt UI or system-fw.json)").arg(root.fw.chains).arg(root.fw.rules) : ""
                OsSwitch {
                    enabled: root.core.daemonOnline
                    checked: root.fw.enabled === true
                    onToggled: v => root.core.setSystemFirewall(v)
                }
            }
            OsRow {
                title: I18n.trFor("opensnitch", "When nobody answers")
                description: I18n.trFor("opensnitch", "The action for connections no rule matches, while this UI is connected.")
                RowLayout {
                    spacing: 8
                    OsChip {
                        text: I18n.trFor("opensnitch", "Allow")
                        selected: root.core.defaultAction === "allow"
                        onClicked: root.core.setSettings({
                            "defaultAction": "allow"
                        })
                    }
                    OsChip {
                        text: I18n.trFor("opensnitch", "Deny")
                        selected: root.core.defaultAction !== "allow"
                        onClicked: root.core.setSettings({
                            "defaultAction": "deny"
                        })
                    }
                }
            }
        }

        // ---- prompt -----------------------------------------------
        OsCard {
            Layout.fillWidth: true
            spacing: 16
            StyledText {
                text: I18n.trFor("opensnitch", "Authorization prompt")
                font.pixelSize: Theme.fontSizeLarge
                font.weight: Font.Bold
                color: Theme.surfaceText
            }
            OsRow {
                title: I18n.trFor("opensnitch", "Ask when an application connects")
                description: I18n.trFor("opensnitch", "Off: unknown connections get the default action silently.")
                OsSwitch {
                    checked: root.s.disablePopups !== true
                    onToggled: v => root.core.setSettings({
                        "disablePopups": !v
                    })
                }
            }
            OsRow {
                title: I18n.trFor("opensnitch", "Answer after")
                description: I18n.trFor("opensnitch", "Seconds before the default action is applied. 0 never shows the prompt.")
                RowLayout {
                    spacing: 6
                    Repeater {
                        model: [0, 10, 15, 30, 60, 120]
                        delegate: OsChip {
                            id: tchip

                            required property int modelData

                            compact: true
                            text: modelData === 0 ? I18n.trFor("opensnitch", "off") : I18n.trFor("opensnitch", "%1s").arg(modelData)
                            selected: root.s.timeout === modelData
                            onClicked: root.core.setSettings({
                                "timeout": modelData
                            })
                        }
                    }
                }
            }
            OsRow {
                title: I18n.trFor("opensnitch", "Default duration")
                OsSelect {
                    Layout.preferredWidth: 240
                    model: root.core.durations.map(d => ({
                                "label": root.durationLabel(d.id)
                            }))
                    currentIndex: {
                        for (let i = 0; i < root.core.durations.length; i++)
                            if (root.core.durations[i].id === root.s.defaultDuration)
                                return i;
                        return 7;
                    }
                    onActivated: i => root.core.setSettings({
                        "defaultDuration": root.core.durations[i].id
                    })
                }
            }
            OsRow {
                title: I18n.trFor("opensnitch", "Default target")
                description: I18n.trFor("opensnitch", "What a new rule matches unless you pick otherwise.")
                OsSelect {
                    Layout.preferredWidth: 240
                    model: root.targets.map(t => ({
                                "label": t
                            }))
                    currentIndex: root.s.defaultTarget || 0
                    onActivated: i => root.core.setSettings({
                        "defaultTarget": i
                    })
                }
            }
            OsRow {
                title: I18n.trFor("opensnitch", "Show advanced options")
                description: I18n.trFor("opensnitch", "Start the prompt with the advanced section open.")
                OsSwitch {
                    checked: root.s.popupAdvanced === true
                    onToggled: v => root.core.setSettings({
                        "popupAdvanced": v
                    })
                }
            }
            OsRow {
                title: I18n.trFor("opensnitch", "Also match, by default")
                Flow {
                    Layout.preferredWidth: 300
                    spacing: 6
                    OsChip {
                        compact: true
                        text: I18n.trFor("opensnitch", I18n.trFor("opensnitch", "Dest. IP"))
                        selected: root.s.advDstIp === true
                        onClicked: root.core.setSettings({
                            "advDstIp": !root.s.advDstIp
                        })
                    }
                    OsChip {
                        compact: true
                        text: I18n.trFor("opensnitch", "Port")
                        selected: root.s.advDstPort === true
                        onClicked: root.core.setSettings({
                            "advDstPort": !root.s.advDstPort
                        })
                    }
                    OsChip {
                        compact: true
                        text: I18n.trFor("opensnitch", "User")
                        selected: root.s.advUid === true
                        onClicked: root.core.setSettings({
                            "advUid": !root.s.advUid
                        })
                    }
                    OsChip {
                        compact: true
                        text: I18n.trFor("opensnitch", "Checksum")
                        selected: root.s.advChecksum === true
                        onClicked: root.core.setSettings({
                            "advChecksum": !root.s.advChecksum
                        })
                    }
                }
            }
        }

        // ---- daemon -----------------------------------------------
        OsCard {
            Layout.fillWidth: true
            spacing: 16
            enabled: root.core.daemonOnline
            opacity: enabled ? 1 : 0.5
            StyledText {
                text: I18n.trFor("opensnitch", "Daemon (opensnitchd)")
                font.pixelSize: Theme.fontSizeLarge
                font.weight: Font.Bold
                color: Theme.surfaceText
            }
            OsRow {
                title: I18n.trFor("opensnitch", "Intercept unknown processes")
                description: I18n.trFor("opensnitch", "Also filter connections whose process could not be identified.")
                OsSwitch {
                    checked: root.cfg.InterceptUnknown === true
                    onToggled: v => root.core.setDaemonConfig({
                        "InterceptUnknown": v
                    })
                }
            }
            OsRow {
                title: I18n.trFor("opensnitch", "Verify checksums in rules")
                description: I18n.trFor("opensnitch", "Rules with a process hash are checked against the binary.")
                OsSwitch {
                    checked: root.cfg.Rules ? root.cfg.Rules.EnableChecksums === true : false
                    onToggled: v => root.core.setDaemonConfig({
                        "Rules.EnableChecksums": v
                    })
                }
            }
            OsRow {
                title: I18n.trFor("opensnitch", "Queue bypass")
                description: I18n.trFor("opensnitch", "Let traffic through if the daemon stops, instead of blocking everything.")
                OsSwitch {
                    checked: root.cfg.FwOptions ? root.cfg.FwOptions.QueueBypass === true : false
                    onToggled: v => root.core.setDaemonConfig({
                        "FwOptions.QueueBypass": v
                    })
                }
            }
            OsRow {
                title: I18n.trFor("opensnitch", "Process monitor")
                description: I18n.trFor("opensnitch", "How the daemon finds the process behind a connection.")
                OsSelect {
                    Layout.preferredWidth: 200
                    model: root.monitors.map(m => ({
                                "label": m
                            }))
                    currentIndex: root.idx(root.monitors, root.cfg.ProcMonitorMethod)
                    onActivated: i => root.core.setDaemonConfig({
                        "ProcMonitorMethod": root.monitors[i]
                    })
                }
            }
            OsRow {
                title: I18n.trFor("opensnitch", "Firewall backend")
                OsSelect {
                    Layout.preferredWidth: 200
                    model: root.backends.map(m => ({
                                "label": m
                            }))
                    currentIndex: root.idx(root.backends, root.cfg.Firewall)
                    onActivated: i => root.core.setDaemonConfig({
                        "Firewall": root.backends[i]
                    })
                }
            }
            OsRow {
                title: I18n.trFor("opensnitch", "Log level")
                OsSelect {
                    Layout.preferredWidth: 200
                    model: root.logLevels.map(m => ({
                                "label": m
                            }))
                    currentIndex: root.cfg.LogLevel !== undefined ? root.cfg.LogLevel : 2
                    onActivated: i => root.core.setDaemonConfig({
                        "LogLevel": i
                    })
                }
            }
        }

        // ---- overview statistics ----------------------------------
        OsCard {
            Layout.fillWidth: true
            spacing: 16

            StyledText {
                text: I18n.trFor("opensnitch", "Overview statistics")
                font.pixelSize: Theme.fontSizeLarge
                font.weight: Font.Bold
                color: Theme.surfaceText
            }
            OsRow {
                title: I18n.trFor("opensnitch", "Reset overview stats")
                description: I18n.trFor("opensnitch", "Start counters and top lists from zero for this daemon. The baseline is saved by the plugin; daemon uptime, rules and connection history stay intact.")
                OsButton {
                    text: I18n.trFor("opensnitch", "Reset stats")
                    icon: "restart_alt"
                    variant: "outlined"
                    enabled: root.core.stats !== null
                    onClicked: root.core.resetStats()
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.bottomMargin: 8
            wrapMode: Text.WordWrap
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            text: I18n.trFor("opensnitch", "OpenSnitch UI backend %1%2").arg(root.core.backendVersion).arg(root.core.node ? I18n.trFor("opensnitch", " · daemon ") + root.core.node.version : "")
        }
    }
}
