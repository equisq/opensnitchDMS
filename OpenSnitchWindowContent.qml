pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets

// Navigation rail + pages, in the shape of the Qt main window (statistics,
// connections, rules, preferences) in the DMS look.
Item {
    id: root

    required property var core
    signal closeRequested

    property int page: 0
    readonly property bool hasOverlay: false

    // Escape closes the window from anywhere in it, including while typing in
    // a search or rule field (a field leaves Escape alone, so it reaches here).
    focus: true
    Keys.onEscapePressed: event => {
        event.accepted = true;
        root.closeRequested();
    }

    // Called when the window opens, and puts the keyboard back on the window
    // itself so Escape works without clicking first.
    function takeFocus() {
        root.forceActiveFocus();
    }

    Component.onCompleted: takeFocus()

    readonly property var pages: [
        {
            "label": I18n.trFor("opensnitch", "Overview"),
            "icon": "monitoring"
        },
        {
            "label": I18n.trFor("opensnitch", "Connections"),
            "icon": "swap_vert"
        },
        {
            "label": I18n.trFor("opensnitch", "Rules"),
            "icon": "rule"
        },
        {
            "label": I18n.trFor("opensnitch", "Firewall"),
            "icon": "security"
        },
        {
            "label": I18n.trFor("opensnitch", "Settings"),
            "icon": "tune"
        }
    ]

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ---- rail ---------------------------------------------------
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 104
            color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.6)
            topLeftRadius: Theme.cornerRadius
            bottomLeftRadius: Theme.cornerRadius

            ColumnLayout {
                anchors.fill: parent
                anchors.topMargin: 28
                anchors.bottomMargin: 20
                spacing: 12

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 56
                    Layout.preferredHeight: 56
                    readonly property bool bad: root.core.status !== "ok" && root.core.status !== "paused"
                    radius: Theme.cornerRadius
                    color: bad ? Theme.errorContainer : Theme.withAlpha(Theme.surfaceText, 0.1)
                    DankIcon {
                        anchors.centerIn: parent
                        name: root.core.status === "ok" ? "shield" : root.core.status === "paused" ? "remove_moderator" : "gpp_maybe"
                        size: 30
                        color: parent.bad ? Theme.onErrorContainer : Theme.surfaceText
                    }
                }

                Item {
                    Layout.preferredHeight: 8
                }

                Repeater {
                    model: root.pages

                    delegate: Item {
                        id: navItem

                        required property var modelData
                        required property int index
                        readonly property bool active: root.page === index

                        Layout.fillWidth: true
                        Layout.preferredHeight: 72

                        Rectangle {
                            id: indicator

                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 4
                            height: 36
                            width: navItem.active ? 64 : 36
                            radius: Theme.cornerRadius
                            color: navItem.active ? Theme.primary : navMouse.containsMouse ? Theme.withAlpha(Theme.surfaceText, 0.08) : "transparent"
                            Behavior on width {
                                NumberAnimation {
                                    duration: 380
                                    easing.type: Easing.OutCubic
                                }
                            }
                            DankIcon {
                                anchors.centerIn: parent
                                name: navItem.modelData.icon
                                size: 22
                                color: navItem.active ? Theme.onPrimary : Theme.surfaceVariantText
                            }
                            // pending-prompt badge on Connections is not needed;
                            // prompts have their own popup
                        }
                        StyledText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: indicator.bottom
                            anchors.topMargin: 4
                            text: navItem.modelData.label
                            font.pixelSize: 12
                            font.weight: navItem.active ? Font.Bold : Font.Normal
                            color: navItem.active ? Theme.surfaceText : Theme.surfaceVariantText
                        }
                        MouseArea {
                            id: navMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.page = navItem.index
                        }
                    }
                }

                Item {
                    Layout.fillHeight: true
                }

                OsIconButton {
                    Layout.alignment: Qt.AlignHCenter
                    icon: "close"
                    tonal: true
                    onClicked: root.closeRequested()
                }
            }
        }

        // ---- page ---------------------------------------------------
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Backend or daemon missing: say so instead of showing zeros.
            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(parent.width - 80, 460)
                spacing: 16
                visible: !root.core.available
                DankIcon {
                    Layout.alignment: Qt.AlignHCenter
                    name: "hourglass_top"
                    size: 48
                    color: Theme.surfaceVariantText
                }
                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: I18n.trFor("opensnitch", "The OpenSnitch backend is not running")
                    font.pixelSize: Theme.fontSizeXLarge
                    font.weight: Font.Bold
                    color: Theme.surfaceText
                }
                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: I18n.trFor("opensnitch", "Build it with ./build.sh in the plugin folder (needs Go). If the Qt opensnitch-ui is running it holds the socket; quit it first.")
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeMedium
                }
            }

            Loader {
                anchors.fill: parent
                visible: root.core.available
                sourceComponent: root.page === 0 ? overview : root.page === 1 ? connections : root.page === 2 ? rules : root.page === 3 ? firewall : prefs
            }
        }
    }

    Component {
        id: overview
        OpenSnitchOverviewPage {
            core: root.core
        }
    }
    Component {
        id: connections
        OpenSnitchConnectionsPage {
            core: root.core
        }
    }
    Component {
        id: rules
        OpenSnitchRulesPage {
            core: root.core
        }
    }
    Component {
        id: firewall
        OpenSnitchFirewallPage {
            core: root.core
        }
    }
    Component {
        id: prefs
        OpenSnitchSettingsPage {
            core: root.core
        }
    }
}
