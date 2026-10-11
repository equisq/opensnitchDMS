pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets
import "format.js" as F

Item {
    id: root

    required property var core

    property string query: ""
    property string filter: "all"
    property var editing: null     // rule object being edited, or null
    property bool creating: false
    property string confirmDelete: ""

    readonly property var shown: {
        const q = query.toLowerCase();
        return core.rules.filter(r => (filter === "all" || (filter === "blocked") === F.isBlock(r.action)) && (q === "" || (r.name + " " + r.description + " " + F.operatorSummary(r.operator)).toLowerCase().indexOf(q) >= 0));
    }

    function durationLabel(id) {
        if (id === "always") return I18n.trFor("opensnitch", "forever");
        if (id === "until restart") return I18n.trFor("opensnitch", "until reboot");
        return id;
    }

    function newRule() {
        root.editing = {
            "name": "",
            "description": "",
            "enabled": true,
            "precedence": false,
            "nolog": false,
            "action": "allow",
            "duration": "always",
            "operator": {
                "type": "simple",
                "operand": "process.path",
                "data": "",
                "sensitive": false,
                "list": []
            }
        };
        root.creating = true;
    }

    function edit(r) {
        root.editing = JSON.parse(JSON.stringify(r));
        root.creating = false;
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 32
        spacing: 16
        visible: root.editing === null

        OsPageHeader {
            Layout.fillWidth: true
            title: I18n.trFor("opensnitch", "Rules")
            subtitle: I18n.trFor("opensnitch", "%1 rules on this computer").arg(root.core.rules.length)
            OsButton {
                text: I18n.trFor("opensnitch", "New rule")
                icon: "add"
                onClicked: root.newRule()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Repeater {
                model: [
                    {
                        "id": "all",
                        "t": I18n.trFor("opensnitch", "All")
                    },
                    {
                        "id": "allowed",
                        "t": I18n.trFor("opensnitch", "Allowed")
                    },
                    {
                        "id": "blocked",
                        "t": I18n.trFor("opensnitch", "Blocked")
                    }
                ]
                delegate: OsChip {
                    required property var modelData

                    text: modelData.t
                    selected: root.filter === modelData.id
                    onClicked: root.filter = modelData.id
                }
            }
            Item {
                Layout.fillWidth: true
            }
            OsField {
                Layout.preferredWidth: 280
                implicitHeight: 48
                label: I18n.trFor("opensnitch", "Search rules")
                onEdited: root.query = text
            }
        }

        ListView {
            id: list

            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 8
            model: root.shown
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
                id: row

                required property var modelData
                readonly property bool blocked: F.isBlock(modelData.action)

                width: ListView.view.width
                height: 76
                radius: Theme.cornerRadius
                color: Theme.surfaceContainerHigh
                opacity: modelData.enabled ? 1 : 0.55

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 12
                    spacing: 12

                    Rectangle {
                        Layout.preferredWidth: 44
                        Layout.preferredHeight: 44
                        radius: Theme.cornerRadius
                        color: row.blocked ? Theme.error : Theme.primary
                        DankIcon {
                            anchors.centerIn: parent
                            name: row.modelData.action === "reject" ? "block" : row.blocked ? "gpp_bad" : "check_circle"
                            size: 24
                            color: row.blocked ? Theme.onError : Theme.onPrimary
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        StyledText {
                            Layout.fillWidth: true
                            text: row.modelData.name
                            elide: Text.ElideRight
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.DemiBold
                            color: Theme.surfaceText
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: F.operatorSummary(row.modelData.operator)
                            elide: Text.ElideMiddle
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            font.family: Theme.monoFontFamily
                        }
                    }
                    Rectangle {
                        Layout.preferredHeight: 28
                        Layout.preferredWidth: dur.implicitWidth + 24
                        radius: Theme.cornerRadius / 2
                        color: Theme.surfaceContainerHighest
                        StyledText {
                            id: dur

                            anchors.centerIn: parent
                            text: root.durationLabel(row.modelData.duration)
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceText
                        }
                    }
                    OsSwitch {
                        checked: row.modelData.enabled
                        onToggled: v => root.core.ruleAction(v ? "enable" : "disable", row.modelData.name)
                    }
                    OsIconButton {
                        icon: "edit"
                        onClicked: root.edit(row.modelData)
                    }
                    OsIconButton {
                        icon: root.confirmDelete === row.modelData.name ? "delete_forever" : "delete"
                        toggled: root.confirmDelete === row.modelData.name
                        onClicked: {
                            if (root.confirmDelete === row.modelData.name) {
                                root.confirmDelete = "";
                                root.core.ruleAction("delete", row.modelData.name);
                            } else {
                                root.confirmDelete = row.modelData.name;
                            }
                        }
                    }
                }
            }

            StyledText {
                anchors.centerIn: parent
                visible: list.count === 0
                text: root.query === "" ? I18n.trFor("opensnitch", "No rules yet. They appear as you answer prompts.") : I18n.trFor("opensnitch", "No rule matches")
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeMedium
            }
        }
    }

    // ---- editor ------------------------------------------------------
    Loader {
        anchors.fill: parent
        active: root.editing !== null
        sourceComponent: OpenSnitchRuleEditor {
            core: root.core
            rule: root.editing
            creating: root.creating
            onClosed: root.editing = null
        }
    }
}
