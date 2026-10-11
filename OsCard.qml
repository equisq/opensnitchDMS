import QtQuick
import QtQuick.Layouts
import qs.Common

// Flat tonal container with the theme corner radius and a hairline border.
Rectangle {
    id: root

    // surface | high | primary | primaryAction | error | tertiary
    property string tone: "high"
    property int padding: 20
    property int spacing: 12
    default property alias contents: col.data

    implicitHeight: col.implicitHeight + padding * 2
    implicitWidth: col.implicitWidth + padding * 2
    radius: Theme.cornerRadius
    border.width: 1
    border.color: Theme.withAlpha(Theme.outline, 0.12)
    color: {
        switch (tone) {
        case "surface":
            return Theme.surfaceContainer;
        case "primary":
            return Theme.primaryContainer;
        case "primaryAction":
            return Theme.primary;
        case "error":
            // A fixed red tint over the surface rather than the theme's
            // errorContainer, which some themes make near-white.
            return Qt.rgba(0.9, 0.22, 0.21, 0.32);
        case "tertiary":
            return Theme.withAlpha(Theme.tertiary, 0.22);
        default:
            return Theme.surfaceContainerHigh;
        }
    }

    Behavior on color {
        ColorAnimation {
            duration: 220
        }
    }

    ColumnLayout {
        id: col

        anchors.fill: parent
        anchors.margins: root.padding
        spacing: root.spacing
    }
}
