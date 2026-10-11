pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

// Bar icon + quick-controls popout. State lives in the daemon part of the
// plugin; this only shows it.
PluginComponent {
    id: root

    readonly property var daemon: PluginService.pluginDaemonInstances["opensnitch"] ?? null
    readonly property var core: daemon ? daemon.core : null

    readonly property string status: core ? core.status : "backend"
    readonly property int pending: core ? core.pendingCount : 0

    readonly property string iconName: status === "ok" ? "shield" : status === "paused" ? "remove_moderator" : "gpp_maybe"
    readonly property color iconColor: pending > 0 ? Theme.error : status === "ok" ? Theme.primary : status === "paused" ? Theme.warning : Theme.surfaceVariantText

    popoutWidth: 400
    popoutHeight: 0

    Component {
        id: pillBadge

        Rectangle {
            visible: root.pending > 0
            width: 14
            height: 14
            radius: 7
            color: Theme.error
            StyledText {
                anchors.centerIn: parent
                text: root.pending > 9 ? "9+" : String(root.pending)
                font.pixelSize: 9
                font.weight: Font.Bold
                color: Theme.onError
            }
        }
    }

    horizontalBarPill: Component {
        Item {
            implicitWidth: root.iconSize + Theme.spacingS
            implicitHeight: root.widgetThickness

            DankIcon {
                anchors.centerIn: parent
                name: root.iconName
                size: root.iconSize
                color: root.iconColor
            }
            Loader {
                sourceComponent: pillBadge
                x: parent.width / 2 + 2
                y: parent.height / 2 - root.iconSize / 2 - 4
            }
        }
    }

    verticalBarPill: Component {
        Item {
            implicitWidth: root.widgetThickness
            implicitHeight: root.iconSize + Theme.spacingS

            DankIcon {
                anchors.centerIn: parent
                name: root.iconName
                size: root.iconSize
                color: root.iconColor
            }
            Loader {
                sourceComponent: pillBadge
                x: parent.width / 2 + 2
                y: parent.height / 2 - root.iconSize / 2 - 4
            }
        }
    }

    popoutContent: Component {
        PopoutComponent {
            id: pop

            headerText: "OpenSnitch"
            detailsText: !root.core ? I18n.trFor("opensnitch", "Starting…") : root.status === "ok" ? I18n.trFor("opensnitch", "Protecting this computer") : root.status === "paused" ? I18n.trFor("opensnitch", "Interception is off") : root.status === "off" ? I18n.trFor("opensnitch", "Daemon not connected") : I18n.trFor("opensnitch", "Backend not running")
            showCloseButton: true

            // Live numbers while this is open.
            Component.onCompleted: if (root.core)
                root.core.refCount += 1
            Component.onDestruction: if (root.core)
                root.core.refCount -= 1

            Item {
                width: parent.width
                implicitHeight: body.implicitHeight + Theme.spacingM

                ColumnLayout {
                    id: body

                    width: parent.width
                    spacing: 12

                    // ---- main switch ---------------------------------
                    OsCard {
                        Layout.fillWidth: true
                        tone: root.status === "ok" ? "primary" : root.status === "paused" ? "surface" : "error"
                        padding: 18

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 14
                            Rectangle {
                                Layout.preferredWidth: 52
                                Layout.preferredHeight: 52
                                radius: Theme.cornerRadius
                                color: Theme.withAlpha(Theme.surfaceText, 0.1)
                                DankIcon {
                                    anchors.centerIn: parent
                                    name: root.iconName
                                    size: 28
                                    color: Theme.surfaceText
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                StyledText {
                                    text: I18n.trFor("opensnitch", "Firewall")
                                    font.pixelSize: Theme.fontSizeLarge
                                    font.weight: Font.Bold
                                    color: Theme.surfaceText
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: root.core && root.core.stats ? I18n.trFor("opensnitch", "%1 allowed · %2 blocked").arg(root.core.stats.accepted).arg(root.core.stats.dropped) : I18n.trFor("opensnitch", "no data yet")
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                }
                            }
                            OsSwitch {
                                enabled: root.core !== null && root.core.daemonOnline
                                checked: root.core !== null && root.core.interception
                                onToggled: v => root.core.setInterception(v)
                            }
                        }
                    }

                    // ---- options -------------------------------------
                    OsCard {
                        Layout.fillWidth: true
                        padding: 18
                        spacing: 14
                        enabled: root.core !== null && root.core.available

                        OsRow {
                            title: I18n.trFor("opensnitch", "Ask on new connections")
                            OsSwitch {
                                checked: root.core && root.core.settings.disablePopups !== true
                                onToggled: v => root.core.setSettings({
                                    "disablePopups": !v
                                })
                            }
                        }
                        OsRow {
                            visible: root.core && root.core.node && root.core.node.sysFirewall.known
                            title: I18n.trFor("opensnitch", "System firewall")
                            OsSwitch {
                                enabled: root.core !== null && root.core.daemonOnline
                                checked: root.core && root.core.node ? root.core.node.sysFirewall.enabled === true : false
                                onToggled: v => root.core.setSystemFirewall(v)
                            }
                        }
                    }

                    OsButton {
                        Layout.fillWidth: true
                        text: I18n.trFor("opensnitch", "Open OpenSnitch")
                        icon: "open_in_full"
                        variant: "filled"
                        onClicked: {
                            pop.closePopout();
                            if (root.daemon)
                                root.daemon.openWindow();
                        }
                    }
                }
            }
        }
    }
}
