import QtQuick
import qs.Common
import qs.Widgets

// Selectable option (segmented / filter chip). Unselected it is a rounded
// square; selected it is tinted with a check mark.
Item {
    id: root

    property string text: ""
    property string icon: ""
    property bool selected: false
    property bool compact: false

    signal clicked

    implicitHeight: compact ? 34 : 40
    implicitWidth: row.implicitWidth + 28
    opacity: enabled ? 1 : 0.38

    Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadius / 2
        color: root.selected ? Theme.primary : Theme.surfaceContainerHigh
        border.width: root.selected ? 0 : 1
        border.color: Theme.outlineVariant
        Behavior on color {
            ColorAnimation {
                duration: 150
            }
        }
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: Theme.surfaceText
            opacity: mouse.pressed ? 0.12 : mouse.containsMouse ? 0.06 : 0
        }
    }

    Row {
        id: row

        anchors.centerIn: parent
        spacing: 6

        DankIcon {
            visible: root.selected || root.icon !== ""
            name: root.selected ? "check" : root.icon
            size: 18
            color: root.selected ? Theme.onPrimary : Theme.surfaceVariantText
            anchors.verticalCenter: parent.verticalCenter
        }
        StyledText {
            text: root.text
            color: root.selected ? Theme.onPrimary : Theme.surfaceText
            font.pixelSize: Theme.fontSizeMedium
            font.weight: root.selected ? Font.DemiBold : Font.Normal
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
