import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets

// Filled text field with a floating label.
Rectangle {
    id: root

    property alias text: input.text
    property string label: ""
    property string placeholder: ""
    property bool mono: false
    property alias inputItem: input

    signal accepted
    signal edited

    implicitHeight: 56
    implicitWidth: 240
    radius: Theme.cornerRadius
    color: Theme.surfaceContainerHighest
    border.width: input.activeFocus ? 2 : 0
    border.color: Theme.primary

    Column {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        anchors.topMargin: 8

        StyledText {
            text: root.label
            visible: root.label !== ""
            color: input.activeFocus ? Theme.primary : Theme.surfaceVariantText
            font.pixelSize: 11
        }
        TextInput {
            id: input

            width: parent.width
            clip: true
            color: Theme.surfaceText
            selectionColor: Theme.primary
            selectedTextColor: Theme.onPrimary
            font.pixelSize: Theme.fontSizeMedium
            font.family: root.mono ? Theme.monoFontFamily : Qt.application.font.family
            onAccepted: root.accepted()
            onTextEdited: root.edited()

            StyledText {
                visible: input.text === "" && root.placeholder !== ""
                text: root.placeholder
                color: Theme.withAlpha(Theme.surfaceText, 0.4)
                font.pixelSize: Theme.fontSizeMedium
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.IBeamCursor
        onPressed: mouse => {
            input.forceActiveFocus();
            mouse.accepted = false;
        }
    }
}
