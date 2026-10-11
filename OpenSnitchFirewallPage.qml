pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets

// The Qt "Firewall" tab: default policy of incoming and outgoing traffic.
Flickable {
    id: root

    required property var core
    readonly property var fw: core.node ? core.node.sysFirewall : ({
            "known": false
        })
    readonly property bool usable: core.daemonOnline && fw.known === true && fw.enabled === true

    contentWidth: width
    contentHeight: col.implicitHeight + 64
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    component PolicyRow: OsRow {
        id: pr

        required property string hook
        property string current: ""

        OsChip {
            text: I18n.trFor("opensnitch", "Allow")
            enabled: root.usable && pr.current !== ""
            selected: pr.current === "accept"
            onClicked: root.core.setFirewallPolicy(pr.hook, "accept")
        }
        OsChip {
            text: I18n.trFor("opensnitch", "Drop")
            enabled: root.usable && pr.current !== ""
            selected: pr.current === "drop"
            onClicked: root.core.setFirewallPolicy(pr.hook, "drop")
        }
    }

    ColumnLayout {
        id: col

        x: 32
        y: 28
        width: root.width - 64
        spacing: 16

        OsPageHeader {
            Layout.fillWidth: true
            title: I18n.trFor("opensnitch", "Firewall")
            subtitle: I18n.trFor("opensnitch", "Default policy of the system firewall rules managed by OpenSnitch")
        }

        OsCard {
            Layout.fillWidth: true
            spacing: 16
            visible: root.fw.known !== true
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: root.core.daemonOnline ? I18n.trFor("opensnitch", "The daemon did not report a system firewall configuration. It needs a recent opensnitchd with the nftables backend.") : I18n.trFor("opensnitch", "The OpenSnitch daemon is not connected.")
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeMedium
            }
        }

        OsCard {
            Layout.fillWidth: true
            spacing: 16
            visible: root.fw.known === true
            StyledText {
                text: I18n.trFor("opensnitch", "System firewall")
                font.pixelSize: Theme.fontSizeLarge
                font.weight: Font.Bold
                color: Theme.surfaceText
            }
            OsRow {
                title: I18n.trFor("opensnitch", "Enable firewall")
                description: root.fw.known ? I18n.trFor("opensnitch", "%1 chains, %2 rules").arg(root.fw.chains).arg(root.fw.rules) : ""
                OsSwitch {
                    enabled: root.core.daemonOnline
                    checked: root.fw.enabled === true
                    onToggled: v => root.core.setSystemFirewall(v)
                }
            }
        }

        OsCard {
            Layout.fillWidth: true
            spacing: 16
            visible: root.fw.known === true
            opacity: root.usable ? 1 : 0.5
            StyledText {
                text: I18n.trFor("opensnitch", "Default policy")
                font.pixelSize: Theme.fontSizeLarge
                font.weight: Font.Bold
                color: Theme.surfaceText
            }
            PolicyRow {
                hook: "input"
                current: root.fw.policyInput || ""
                title: I18n.trFor("opensnitch", "Incoming connections")
                description: I18n.trFor("opensnitch", "Allow: anything may reach this computer. Drop: only local and already established traffic gets in.")
            }
            PolicyRow {
                hook: "output"
                current: root.fw.policyOutput || ""
                title: I18n.trFor("opensnitch", "Outgoing connections")
                description: I18n.trFor("opensnitch", "Allow: applications may connect out, subject to your rules. Drop: only established traffic leaves, so new connections need an allow rule.")
            }
            StyledText {
                Layout.fillWidth: true
                visible: root.fw.policyOutput === "drop"
                wrapMode: Text.WordWrap
                text: I18n.trFor("opensnitch", "Output policy is set to drop. If OpenSnitch stops, outbound network traffic stays blocked.")
                color: Theme.error
                font.pixelSize: Theme.fontSizeSmall
            }
            StyledText {
                Layout.fillWidth: true
                visible: !root.usable
                wrapMode: Text.WordWrap
                text: I18n.trFor("opensnitch", "Enable the firewall to change these.")
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
            }
        }

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            text: I18n.trFor("opensnitch", "Adding or editing individual firewall rules is still done in the Qt UI or system-fw.json.")
        }
    }
}
