pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets
import "format.js" as F

Item {
    id: root

    required property var core

    property string filter: "all"
    property string query: ""
    property string expandedId: ""
    property bool followingLive: true
    property string viewportAnchorId: ""
    property real viewportAnchorOffset: 0
    property bool restoringViewport: false
    property var knownEventIds: []

    ListModel {
        id: shownModel
        dynamicRoles: true
    }

    function eventId(event) {
        if (event.unixnano !== undefined)
            return String(event.node || "") + "|" + String(event.unixnano);
        return [event.node, event.time, event.pid, event.process, event.dstIp, event.dstPort].join("|");
    }

    function eventIsBlocked(event) {
        return F.isBlock(event.action);
    }

    function rememberViewportAnchor() {
        const index = list.indexAt(1, 1);
        if (index < 0)
            return;
        const item = list.itemAtIndex(index);
        if (!item)
            return;
        viewportAnchorId = item.eventKey;
        viewportAnchorOffset = item.y - list.contentY;
    }

    function restoreViewportAnchor() {
        if (followingLive || viewportAnchorId === "") {
            restoringViewport = false;
            return;
        }
        if (list.moving) {
            restoringViewport = false;
            return;
        }
        let index = -1;
        for (let i = 0; i < shownModel.count; i++) {
            if (shownModel.get(i).eventKey === viewportAnchorId) {
                index = i;
                break;
            }
        }
        if (index < 0) {
            restoringViewport = false;
            return;
        }
        restoringViewport = true;
        list.positionViewAtIndex(index, ListView.Beginning);
        Qt.callLater(() => {
            list.forceLayout();
            const item = list.itemAtIndex(index);
            if (item)
                list.contentY = Math.max(0, item.y - viewportAnchorOffset);
            Qt.callLater(() => {
                restoringViewport = false;
                rememberViewportAnchor();
            });
        });
    }

    function returnToLive() {
        restoringViewport = true;
        followingLive = true;
        viewportAnchorId = "";
        list.positionViewAtBeginning();
        Qt.callLater(() => restoringViewport = false);
    }

    function matchesEvent(event) {
        const blocked = eventIsBlocked(event);
        if (filter === "allowed" && blocked)
            return false;
        if (filter === "blocked" && !blocked)
            return false;
        const q = query.toLowerCase();
        if (q === "")
            return true;
        const hay = (event.process + " " + event.dstHost + " " + event.dstIp + " " + event.dstPort + " " + event.rule).toLowerCase();
        return hay.indexOf(q) >= 0;
    }

    function rebuildEventModel() {
        restoringViewport = true;
        shownModel.clear();
        const events = core.events;
        for (let i = events.length - 1; i >= 0; i--) {
            if (matchesEvent(events[i]))
                shownModel.append({ "event": events[i], "eventKey": eventId(events[i]) });
        }
        Qt.callLater(root.restoreViewportAnchor);
    }

    function syncEventModel() {
        const events = core.events;
        const ids = events.map(event => eventId(event));
        if (ids.length === 0) {
            shownModel.clear();
            knownEventIds = [];
            return;
        }
        if (knownEventIds.length === 0) {
            knownEventIds = ids;
            rebuildEventModel();
            return;
        }
        const lastKnownIndex = ids.lastIndexOf(knownEventIds[knownEventIds.length - 1]);
        if (lastKnownIndex < 0) {
            knownEventIds = ids;
            rebuildEventModel();
            return;
        }
        const newEvents = events.slice(lastKnownIndex + 1);
        for (let i = 0; i < newEvents.length; i++) {
            const event = newEvents[i];
            if (matchesEvent(event))
                shownModel.insert(0, { "event": event, "eventKey": eventId(event) });
        }
        if (newEvents.length > 0 && !followingLive)
            Qt.callLater(root.restoreViewportAnchor);
        const currentIds = new Set(ids);
        for (let i = shownModel.count - 1; i >= 0; i--) {
            if (!currentIds.has(shownModel.get(i).eventKey))
                shownModel.remove(i);
        }
        knownEventIds = ids;
    }

    onFilterChanged: root.rebuildEventModel()
    onQueryChanged: root.rebuildEventModel()

    Connections {
        target: root.core
        function onEventsChanged() {
            root.syncEventModel();
        }
    }

    Component.onCompleted: {
        root.syncEventModel();
        root.core.refreshEvents();
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 32
        spacing: 16

        OsPageHeader {
            Layout.fillWidth: true
            title: I18n.trFor("opensnitch", "Connections")
            subtitle: I18n.trFor("opensnitch", "%1 recent · live").arg(shownModel.count)
            OsButton {
                text: I18n.trFor("opensnitch", "Clear all")
                icon: "delete_sweep"
                variant: "filled"
                enabled: root.core.events.length > 0
                onClicked: {
                    root.expandedId = "";
                    root.core.clearEvents();
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Repeater {
                model: [
                    {
                        "id": "all",
                        "t": I18n.trFor("opensnitch", "All")
                    },
                    {
                        "id": "allowed",
                        "t": I18n.trFor("opensnitch", "Allowed")
                    },
                    {
                        "id": "blocked",
                        "t": I18n.trFor("opensnitch", "Blocked")
                    }
                ]
                delegate: OsChip {
                    id: fchip

                    required property var modelData

                    text: modelData.t
                    selected: root.filter === modelData.id
                    onClicked: {
                        if (modelData.id === "allowed")
                            root.filter = "allowed";
                        else if (modelData.id === "blocked")
                            root.filter = "blocked";
                        else
                            root.filter = "all";
                    }
                }
            }
            Item {
                Layout.fillWidth: true
            }
            OsField {
                Layout.preferredWidth: 280
                implicitHeight: 48
                label: I18n.trFor("opensnitch", "Search")
                onEdited: root.query = text
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: list

                anchors.fill: parent
                clip: true
                spacing: 6
                model: shownModel
                boundsBehavior: Flickable.StopAtBounds
                onMovementStarted: {
                    if (!root.restoringViewport)
                        root.followingLive = false;
                }
                onMovementEnded: Qt.callLater(root.rememberViewportAnchor)

                delegate: Rectangle {
                    id: row

                required property var event
                required property string eventKey
                readonly property var modelData: event
                readonly property bool blocked: root.eventIsBlocked(modelData)
                readonly property bool open: root.expandedId === eventKey

                width: ListView.view.width
                height: rowCol.implicitHeight + 20
                radius: Theme.cornerRadius
                color: open ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                ColumnLayout {
                    id: rowCol

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 10
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        Rectangle {
                            Layout.preferredWidth: 36
                            Layout.preferredHeight: 36
                            radius: Theme.cornerRadius
                            color: row.blocked ? Theme.errorContainer : Theme.primary
                            DankIcon {
                                anchors.centerIn: parent
                                name: row.open ? "keyboard_arrow_up" : "keyboard_arrow_down"
                                size: 20
                                color: row.blocked ? Theme.onErrorContainer : Theme.onPrimary
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                text: F.basename(row.modelData.process) || I18n.trFor("opensnitch", "unknown process")
                                elide: Text.ElideRight
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.DemiBold
                                color: Theme.surfaceText
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: (row.modelData.dstHost || row.modelData.dstIp) + ":" + row.modelData.dstPort + "  ·  " + String(row.modelData.protocol).toUpperCase()
                                elide: Text.ElideRight
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }
                        }
                        StyledText {
                            text: row.modelData.rule
                            elide: Text.ElideRight
                            Layout.maximumWidth: 200
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }
                        StyledText {
                            text: F.clock(row.modelData.time)
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            font.family: Theme.monoFontFamily
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 48
                        visible: row.open
                        spacing: 3
                        Repeater {
                            model: [
                                [I18n.trFor("opensnitch", "Executable"), row.modelData.process],
                                [I18n.trFor("opensnitch", "Command line"), (row.modelData.args || []).join(" ")],
                                [I18n.trFor("opensnitch", "Working dir"), row.modelData.cwd],
                                [I18n.trFor("opensnitch", "PID / UID"), row.modelData.pid + " / " + row.modelData.uid],
                                [I18n.trFor("opensnitch", "Source"), row.modelData.srcIp + ":" + row.modelData.srcPort],
                                [I18n.trFor("opensnitch", "Destination"), row.modelData.dstIp + ":" + row.modelData.dstPort]
                            ].filter(x => x[1] !== "")
                            delegate: RowLayout {
                                id: kv

                                required property var modelData

                                Layout.fillWidth: true
                                StyledText {
                                    Layout.preferredWidth: 100
                                    text: kv.modelData[0]
                                    color: Theme.surfaceVariantText
                                    font.pixelSize: Theme.fontSizeSmall
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: kv.modelData[1]
                                    wrapMode: Text.WrapAnywhere
                                    color: Theme.surfaceText
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.family: Theme.monoFontFamily
                                }
                            }
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    z: -1
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.followingLive) {
                            root.rememberViewportAnchor();
                            root.followingLive = false;
                        }
                        root.expandedId = row.open ? "" : row.eventKey;
                        Qt.callLater(root.rememberViewportAnchor);
                    }
                }
            }

                StyledText {
                    anchors.centerIn: parent
                    visible: list.count === 0
                    text: I18n.trFor("opensnitch", "No connections yet")
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeMedium
                }
            }

            OsButton {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: 16
                anchors.bottomMargin: 16
                visible: !root.followingLive
                text: I18n.trFor("opensnitch", "Back to latest")
                icon: "vertical_align_top"
                compact: true
                z: 2
                onClicked: root.returnToLive()
            }
        }
    }
}
