import QtQuick
import qs.Common
import qs.Widgets

// Icon button with the theme corner radius; filled while `toggled`.
Item {
    id: root

    property string icon: ""
    property bool toggled: false
    property bool tonal: false
    property int size: 40
    property string tip: ""

    signal clicked

    implicitWidth: size
    implicitHeight: size
    opacity: enabled ? 1 : 0.38

    Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadius
        color: root.toggled ? Theme.primary : root.tonal ? Theme.primary : "transparent"
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: Theme.surfaceText
            opacity: mouse.pressed ? 0.14 : mouse.containsMouse ? 0.08 : 0
        }
    }

    DankIcon {
        anchors.centerIn: parent
        name: root.icon
        size: Math.round(root.size * 0.55)
        color: (root.toggled || root.tonal) ? Theme.onPrimary : Theme.surfaceText
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
