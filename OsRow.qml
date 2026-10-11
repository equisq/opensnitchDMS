import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets

// A setting: title and description on the left, the control on the right.
RowLayout {
    id: root

    property string title: ""
    property string description: ""
    default property alias control: slot.data

    Layout.fillWidth: true
    spacing: 16

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        StyledText {
            Layout.fillWidth: true
            text: root.title
            color: Theme.surfaceText
            font.pixelSize: Theme.fontSizeMedium
            wrapMode: Text.WordWrap
        }
        StyledText {
            Layout.fillWidth: true
            visible: root.description !== ""
            text: root.description
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall
            wrapMode: Text.WordWrap
        }
    }
    RowLayout {
        id: slot
        spacing: 8
    }
}
