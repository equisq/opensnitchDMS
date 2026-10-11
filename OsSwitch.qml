import QtQuick
import qs.Common
import "OsColors.js" as OsColors
import qs.Widgets

// Switch with a thumb that grows slightly when pressed.
Item {
    id: root

    property bool checked: false

    // Emitted when the user flips it; `checked` is left to the binding so the
    // switch never claims a state the backend has not confirmed.
    signal toggled(bool value)

    implicitWidth: 56
    implicitHeight: 34
    opacity: enabled ? 1 : 0.38

    Rectangle {
        id: track

        anchors.fill: parent
        radius: height / 2
        color: root.checked ? OsColors.activeAccent : Theme.surfaceContainerHighest
        border.width: root.checked ? 0 : 2
        border.color: Theme.outline
        Behavior on color {
            ColorAnimation {
                duration: 160
            }
        }
    }

    // The thumb lives in a fixed 28px slot so its centre only depends on the
    // switch state, however much it grows.
    Item {
        id: slot

        width: 28
        height: 28
        anchors.verticalCenter: parent.verticalCenter
        x: root.checked ? root.width - width - 3 : 3

        Behavior on x {
            NumberAnimation {
                duration: 320
                easing.type: Easing.OutCubic
            }
        }

        Rectangle {
            id: thumb

            property real d: mouse.pressed ? 28 : root.checked ? 24 : 16

            width: d
            height: d
            radius: d / 2
            anchors.centerIn: parent
            color: root.checked ? OsColors.onActiveAccent : Theme.outline

            Behavior on d {
                NumberAnimation {
                    duration: 260
                    easing.type: Easing.OutCubic
                }
            }

            DankIcon {
                anchors.centerIn: parent
                name: "check"
                size: 16
                color: Theme.primary
                opacity: root.checked ? 1 : 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: 140
                    }
                }
            }
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled(!root.checked)
    }
}
