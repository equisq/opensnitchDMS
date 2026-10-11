import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Common
import qs.Widgets
import "OsColors.js" as OsColors

// A dropdown whose list floats above the page (a popup of the popup) instead
// of pushing the layout down. It is an in-window overlay item, not a separate
// window, so it works inside layer-shell surfaces too.
//
// model: [{label, value?, enabled?}]
Item {
    id: root

    property var model: []
    property int currentIndex: 0
    property string label: ""
    property int maxListHeight: 220
    property bool open: false

    signal activated(int index)

    implicitHeight: field.implicitHeight
    implicitWidth: 240
    clip: false

    readonly property string currentText: model.length > currentIndex && currentIndex >= 0 ? model[currentIndex].label : ""

    Item {
        id: field

        anchors.left: parent.left
        anchors.right: parent.right
        implicitHeight: 52

        Rectangle {
            anchors.fill: parent
            implicitHeight: 52
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHighest
            border.width: root.open ? 2 : 0
            border.color: Theme.primary

            ColumnLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 14
                spacing: 0
                StyledText {
                    visible: root.label !== ""
                    text: root.label
                    color: Theme.primary
                    font.pixelSize: 11
                    Layout.topMargin: 6
                }
                RowLayout {
                    Layout.fillHeight: true
                    Layout.fillWidth: true
                    StyledText {
                        text: root.currentText
                        elide: Text.ElideRight
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeMedium
                        Layout.fillWidth: true
                    }
                    DankIcon {
                        name: "expand_more"
                        size: 22
                        color: Theme.surfaceVariantText
                        rotation: root.open ? 180 : 0
                        Behavior on rotation {
                            NumberAnimation {
                                duration: 250
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.open ? pop.close() : pop.open()
            }
        }
    }

    Popup {
        id: pop

        parent: field
        y: field.height + 6
        width: field.width
        padding: 0
        margins: 8
        height: Math.min(list.contentHeight + 12, root.maxListHeight)
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onAboutToShow: root.open = true
        onClosed: root.open = false

        enter: Transition {
            NumberAnimation {
                property: "opacity"
                from: 0
                to: 1
                duration: 120
            }
        }
        exit: Transition {
            NumberAnimation {
                property: "opacity"
                from: 1
                to: 0
                duration: 90
            }
        }

        background: Rectangle {
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHighest
            border.width: 1
            border.color: Theme.outlineVariant
        }

        contentItem: Item {
            ListView {
                id: list

                anchors.fill: parent
                anchors.margins: 6
                model: root.model
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                delegate: Rectangle {
                    id: item

                    required property var modelData
                    required property int index

                    width: ListView.view.width
                    height: 40
                    radius: Theme.cornerRadius / 2
                    opacity: modelData.enabled === false ? 0.4 : 1
                    color: index === root.currentIndex ? OsColors.activeAccent : (hover.containsMouse && modelData.enabled !== false ? Theme.withAlpha(Theme.surfaceText, 0.08) : "transparent")

                    StyledText {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        text: item.modelData.label
                        color: item.index === root.currentIndex ? OsColors.onActiveAccent : Theme.surfaceText
                        font.pixelSize: Theme.fontSizeMedium
                    }
                    MouseArea {
                        id: hover

                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: item.modelData.enabled !== false
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            pop.close();
                            root.activated(item.index);
                        }
                    }
                }
            }
        }
    }
}
