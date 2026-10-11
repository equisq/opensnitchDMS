pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets
import "format.js" as F

Flickable {
    id: root

    required property var core
    readonly property var st: core.stats

    contentWidth: width
    contentHeight: col.implicitHeight + 64
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    ColumnLayout {
        id: col

        x: 32
        y: 28
        width: root.width - 64
        spacing: 20

        OsPageHeader {
            Layout.fillWidth: true
            title: I18n.trFor("opensnitch", "Overview")
            subtitle: root.core.daemonOnline ? (root.core.node.name || I18n.trFor("opensnitch", "this computer")) + " · opensnitchd " + root.core.node.version + (root.st ? " · up " + F.uptime(root.st.uptime) : "") : I18n.trFor("opensnitch", "Waiting for the OpenSnitch daemon")
        }

        // ---- status hero -------------------------------------------
        OsCard {
            Layout.fillWidth: true
            tone: root.core.status === "ok" ? "primary" : root.core.status === "paused" ? "surface" : "error"
            padding: 24

            RowLayout {
                Layout.fillWidth: true
                spacing: 20

                Rectangle {
                    Layout.preferredWidth: 72
                    Layout.preferredHeight: 72
                    radius: Theme.cornerRadius
                    color: Theme.withAlpha(Theme.surfaceText, 0.1)
                    DankIcon {
                        anchors.centerIn: parent
                        name: root.core.status === "ok" ? "shield" : root.core.status === "paused" ? "remove_moderator" : "gpp_maybe"
                        size: 40
                        color: Theme.surfaceText
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    StyledText {
                        text: root.core.status === "ok" ? I18n.trFor("opensnitch", "Protected") : root.core.status === "paused" ? I18n.trFor("opensnitch", "Interception is off") : I18n.trFor("opensnitch", "Daemon not connected")
                        font.pixelSize: Theme.fontSizeXLarge
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                    }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: root.core.status === "ok" ? I18n.trFor("opensnitch", "Connections are checked against %1 rules; unknown ones are %2 unless you answer a prompt.").arg(root.core.rules.length).arg(root.core.defaultAction === "allow" ? I18n.trFor("opensnitch", "allowed") : I18n.trFor("opensnitch", "blocked")) : root.core.status === "paused" ? I18n.trFor("opensnitch", "Nothing is being filtered right now.") : I18n.trFor("opensnitch", "Start opensnitchd (systemctl start opensnitchd) and it will connect here.")
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeMedium
                    }
                }

                OsSwitch {
                    enabled: root.core.daemonOnline
                    checked: root.core.interception
                    onToggled: v => root.core.setInterception(v)
                }
            }
        }

        // ---- counters ----------------------------------------------
        GridLayout {
            Layout.fillWidth: true
            columns: 3
            columnSpacing: 12
            rowSpacing: 12

            Repeater {
                model: [
                    {
                        "k": I18n.trFor("opensnitch", "Connections"),
                        "v": root.st ? root.st.connections : 0,
                        "icon": "swap_vert",
                        "tone": "high"
                    },
                    {
                        "k": I18n.trFor("opensnitch", "Allowed"),
                        "v": root.st ? root.st.accepted : 0,
                        "icon": "check_circle",
                        "tone": "high"
                    },
                    {
                        "k": I18n.trFor("opensnitch", "Blocked"),
                        "v": root.st ? root.st.dropped : 0,
                        "icon": "block",
                        "tone": "error"
                    },
                    {
                        "k": I18n.trFor("opensnitch", "Rules"),
                        "v": root.core.rules.length,
                        "icon": "rule",
                        "tone": "high"
                    },
                    {
                        "k": I18n.trFor("opensnitch", "Rule hits"),
                        "v": root.st ? root.st.ruleHits : 0,
                        "icon": "target",
                        "tone": "high"
                    },
                    {
                        "k": I18n.trFor("opensnitch", "DNS answers"),
                        "v": root.st ? root.st.dnsResponses : 0,
                        "icon": "dns",
                        "tone": "high"
                    }
                ]

                delegate: OsCard {
                    id: tile

                    required property var modelData

                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    tone: tile.modelData.tone
                    padding: 18
                    spacing: 4
                    RowLayout {
                        spacing: 8
                        DankIcon {
                            name: tile.modelData.icon
                            size: 18
                            color: Theme.surfaceVariantText
                        }
                        StyledText {
                            text: tile.modelData.k
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }
                    StyledText {
                        text: F.num(tile.modelData.v)
                        font.pixelSize: 34
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                    }
                }
            }
        }

        // ---- top lists ---------------------------------------------
        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 12
            rowSpacing: 12

            Repeater {
                model: [
                    {
                        "title": I18n.trFor("opensnitch", "Top hosts"),
                        "key": "byHost"
                    },
                    {
                        "title": I18n.trFor("opensnitch", "Top applications"),
                        "key": "byExecutable"
                    },
                    {
                        "title": I18n.trFor("opensnitch", "Top ports"),
                        "key": "byPort"
                    },
                    {
                        "title": I18n.trFor("opensnitch", "Top addresses"),
                        "key": "byAddress"
                    }
                ]

                delegate: OsCard {
                    id: topCard

                    required property var modelData
                    readonly property var rows: root.st ? root.st[topCard.modelData.key] || [] : []
                    readonly property real maxCount: rows.length > 0 ? rows[0].count : 1

                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignTop
                    spacing: 8

                    StyledText {
                        text: topCard.modelData.title
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                    }
                    StyledText {
                        visible: topCard.rows.length === 0
                        text: I18n.trFor("opensnitch", "Nothing yet")
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                    }

                    Repeater {
                        model: topCard.rows.slice(0, 6)

                        delegate: Item {
                            id: bar

                            required property var modelData

                            Layout.fillWidth: true
                            Layout.preferredHeight: 30

                            Rectangle {
                                anchors.fill: parent
                                radius: Theme.cornerRadius / 2
                                color: Theme.withAlpha(Theme.surfaceText, 0.05)
                            }
                            Rectangle {
                                height: parent.height
                                width: Math.max(30, parent.width * bar.modelData.count / topCard.maxCount)
                                radius: Theme.cornerRadius / 2
                                color: Theme.withAlpha(Theme.primary, 0.28)
                                Behavior on width {
                                    NumberAnimation {
                                        duration: 500
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }
                            StyledText {
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                anchors.right: countLbl.left
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: topCard.modelData.key === "byExecutable" ? F.basename(bar.modelData.key) : bar.modelData.key
                                elide: Text.ElideMiddle
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeSmall
                            }
                            StyledText {
                                id: countLbl

                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: F.num(bar.modelData.count)
                                color: Theme.surfaceVariantText
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.DemiBold
                            }
                        }
                    }
                }
            }
        }
    }
}
