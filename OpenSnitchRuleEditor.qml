pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets

Item {
    id: root

    required property var core
    property var rule: ({})
    property bool creating: false
    signal closed

    readonly property var operands: ["process.path", "process.command", "process.id", "user.id", "dest.ip", "dest.host", "dest.port", "dest.network", "source.ip", "source.port", "source.network", "protocol", "iface.out", "iface.in", "process.hash.md5"]
    readonly property var types: ["simple", "regexp", "network"]
    readonly property var durs: ["always", "until restart", "once", "30s", "5m", "15m", "30m", "1h", "12h"]
    readonly property bool isList: rule.operator.type === "list"

    property bool saving: false

    function save() {
        const r = JSON.parse(JSON.stringify(root.rule));
        r.name = nameField.text.trim();
        r.description = descField.text;
        if (!root.isList) {
            r.operator.data = dataField.text;
            r.operator.operand = root.operands[operandSel.currentIndex];
            r.operator.type = root.types[typeSel.currentIndex];
        }
        if (r.name === "") {
            nameField.inputItem.forceActiveFocus();
            return;
        }
        root.saving = true;
        root.core.saveRule(r, res => {
            root.saving = false;
            if (!res.error)
                root.closed();
        });
    }

    // Fixed toolbar: stays put while the form scrolls underneath.
    Item {
        id: toolbar

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: bar.implicitHeight + 40
        z: 2

        OsPageHeader {
            id: bar

            x: 32
            y: 24
            width: root.width - 64
            title: root.creating ? I18n.trFor("opensnitch", "New rule") : I18n.trFor("opensnitch", "Edit rule")
            subtitle: root.creating ? "" : root.rule.name
            OsButton {
                text: I18n.trFor("opensnitch", "Cancel")
                variant: "text"
                onClicked: root.closed()
            }
            OsButton {
                text: I18n.trFor("opensnitch", "Save")
                icon: "save"
                busy: root.saving
                onClicked: root.save()
            }
        }
    }
    Flickable {
        id: flick

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: toolbar.bottom
        anchors.bottom: parent.bottom
        contentWidth: width
        contentHeight: col.implicitHeight + 40
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: col

            x: 32
            y: 4
            width: flick.width - 64
            spacing: 16

            OsCard {
                Layout.fillWidth: true
                OsField {
                    id: nameField

                    Layout.fillWidth: true
                    label: I18n.trFor("opensnitch", "Name")
                    Component.onCompleted: text = root.rule.name
                    enabled: root.creating
                    opacity: root.creating ? 1 : 0.6
                }
                OsField {
                    id: descField

                    Layout.fillWidth: true
                    label: I18n.trFor("opensnitch", "Description")
                    Component.onCompleted: text = root.rule.description
                }

                StyledText {
                    text: I18n.trFor("opensnitch", "Action")
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                }
                RowLayout {
                    spacing: 8
                    Repeater {
                        model: [
                            {
                                "id": "allow",
                                "t": I18n.trFor("opensnitch", "Allow")
                            },
                            {
                                "id": "deny",
                                "t": I18n.trFor("opensnitch", "Deny")
                            },
                            {
                                "id": "reject",
                                "t": I18n.trFor("opensnitch", "Reject")
                            }
                        ]
                        delegate: OsChip {
                            id: ac

                            required property var modelData

                            text: modelData.t
                            selected: root.rule.action === modelData.id
                            onClicked: root.rule = Object.assign({}, root.rule, {
                                "action": modelData.id
                            })
                        }
                    }
                }

                OsSelect {
                    Layout.fillWidth: true
                    label: I18n.trFor("opensnitch", "Duration")
                    model: root.durs.map(d => ({
                                "label": d === "always" ? I18n.trFor("opensnitch", "forever") : d === "until restart" ? I18n.trFor("opensnitch", "until reboot") : d === "once" ? I18n.trFor("opensnitch", "once") : d
                            }))
                    currentIndex: Math.max(0, root.durs.indexOf(root.rule.duration))
                    onActivated: i => root.rule = Object.assign({}, root.rule, {
                            "duration": root.durs[i]
                        })
                }
            }

            OsCard {
                Layout.fillWidth: true

                StyledText {
                    text: I18n.trFor("opensnitch", "Match")
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Font.Bold
                    color: Theme.surfaceText
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.isList
                    wrapMode: Text.WordWrap
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                    text: I18n.trFor("opensnitch", "This rule combines several conditions (all must match). Their editing is not offered here; you can change everything else above.")
                }
                Repeater {
                    model: root.isList ? root.rule.operator.list : []
                    delegate: StyledText {
                        id: lo

                        required property var modelData

                        Layout.fillWidth: true
                        text: modelData.operand + (modelData.type === "regexp" ? " ~ " : " = ") + modelData.data
                        elide: Text.ElideMiddle
                        color: Theme.surfaceText
                        font.family: Theme.monoFontFamily
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: !root.isList
                    spacing: 10
                    OsSelect {
                        id: operandSel

                        Layout.fillWidth: true
                        label: I18n.trFor("opensnitch", "Field")
                        model: root.operands.map(o => ({
                                    "label": o
                                }))
                        currentIndex: Math.max(0, root.operands.indexOf(root.rule.operator.operand))
                        onActivated: i => currentIndex = i
                    }
                    OsSelect {
                        id: typeSel

                        Layout.fillWidth: true
                        label: I18n.trFor("opensnitch", "Comparison")
                        model: [
                            {
                                "label": I18n.trFor("opensnitch", "equals")
                            },
                            {
                                "label": I18n.trFor("opensnitch", "regular expression")
                            },
                            {
                                "label": I18n.trFor("opensnitch", "in network (CIDR)")
                            }
                        ]
                        currentIndex: Math.max(0, root.types.indexOf(root.rule.operator.type))
                        onActivated: i => currentIndex = i
                    }
                    OsField {
                        id: dataField

                        Layout.fillWidth: true
                        label: I18n.trFor("opensnitch", "Value")
                        mono: true
                        Component.onCompleted: text = root.rule.operator.data
                    }
                }
            }

            OsCard {
                Layout.fillWidth: true
                spacing: 14
                OsRow {
                    title: I18n.trFor("opensnitch", "Enabled")
                    description: I18n.trFor("opensnitch", "A disabled rule is kept but ignored.")
                    OsSwitch {
                        checked: !!root.rule.enabled
                        onToggled: v => root.rule = Object.assign({}, root.rule, {
                            "enabled": v
                        })
                    }
                }
                OsRow {
                    title: I18n.trFor("opensnitch", "Priority rule")
                    description: I18n.trFor("opensnitch", "Checked before the others; a priority deny always wins.")
                    OsSwitch {
                        checked: !!root.rule.precedence
                        onToggled: v => root.rule = Object.assign({}, root.rule, {
                            "precedence": v
                        })
                    }
                }
                OsRow {
                    title: I18n.trFor("opensnitch", "Do not log matches")
                    description: I18n.trFor("opensnitch", "Connections this rule matches stay out of the connection list.")
                    OsSwitch {
                        checked: !!root.rule.nolog
                        onToggled: v => root.rule = Object.assign({}, root.rule, {
                            "nolog": v
                        })
                    }
                }
            }
        }
    }
}
