import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets

RowLayout {
    id: root

    property string title: ""
    property string subtitle: ""
    default property alias actions: actionRow.data

    spacing: 16

    ColumnLayout {
        Layout.alignment: Qt.AlignVCenter
        spacing: 2
        StyledText {
            text: root.title
            font.pixelSize: 24
            font.weight: Font.Bold
            color: Theme.surfaceText
        }
        StyledText {
            visible: root.subtitle !== ""
            text: root.subtitle
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.surfaceVariantText
        }
    }
    Item {
        Layout.fillWidth: true
    }
    RowLayout {
        id: actionRow
        spacing: 8
    }
}
