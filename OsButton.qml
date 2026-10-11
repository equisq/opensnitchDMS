import QtQuick
import qs.Common
import qs.Widgets

// Flat DMS-style button with the theme corner radius.
Item {
    id: root

    property string text: ""
    property string icon: ""
    // filled | tonal | outlined | text | error | errorTonal
    property string variant: "filled"
    property bool compact: false
    property bool busy: false
    // stays "selected" (square-ish) while true, for toggle-like buttons
    property bool selected: false

    signal clicked

    readonly property color bgColor: {
        switch (variant) {
        case "filled":
            return Theme.primary;
        case "tonal":
            return Theme.primary;
        case "error":
            return Theme.error;
        case "errorTonal":
            return Theme.errorContainer;
        case "neutral":
            return Theme.surfaceContainerHighest;
        default:
            return "transparent";
        }
    }
    readonly property color fgColor: {
        switch (variant) {
        case "filled":
            return Theme.onPrimary;
        case "tonal":
            return Theme.onPrimary;
        case "error":
            return Theme.onError;
        case "errorTonal":
            return Theme.onErrorContainer;
        case "neutral":
            return Theme.surfaceText;
        default:
            return Theme.primary;
        }
    }

    implicitHeight: compact ? 32 : 40
    implicitWidth: content.implicitWidth + (compact ? 24 : 32)
    opacity: enabled ? 1 : 0.38

    Rectangle {
        id: bg

        anchors.fill: parent
        color: root.bgColor
        radius: Theme.cornerRadius
        border.width: root.variant === "outlined" ? 1 : 0
        border.color: Theme.outline

        Behavior on color {
            ColorAnimation {
                duration: 150
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: root.fgColor
            opacity: mouse.pressed ? 0.14 : mouse.containsMouse ? 0.08 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: 120
                }
            }
        }
    }

    Row {
        id: content

        anchors.centerIn: parent
        spacing: 8

        DankIcon {
            visible: root.icon !== "" && !root.busy
            name: root.icon
            size: root.compact ? 18 : 20
            color: root.fgColor
            anchors.verticalCenter: parent.verticalCenter
        }
        DankIcon {
            visible: root.busy
            name: "progress_activity"
            size: 18
            color: root.fgColor
            anchors.verticalCenter: parent.verticalCenter
            RotationAnimator on rotation {
                running: root.busy
                from: 0
                to: 360
                duration: 900
                loops: Animation.Infinite
            }
        }
        StyledText {
            visible: root.text !== ""
            text: root.text
            color: root.fgColor
            font.pixelSize: root.compact ? Theme.fontSizeSmall : Theme.fontSizeMedium
            font.weight: Font.DemiBold
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabled && !root.busy
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
