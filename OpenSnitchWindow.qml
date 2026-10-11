import QtQuick
import qs.Common
import qs.Modals.Common
import qs.Services

// The big window.
DankModal {
    id: modal

    required property var core

    layerNamespace: "dms:opensnitch"

    modalWidth: 1040
    modalHeight: 700
    backgroundColor: Theme.withAlpha(Theme.surfaceContainer, Theme.popupTransparency)
    cornerRadius: 8
    // Reopening lands on the page you left.
    keepContentLoaded: true
    visible: false

    closeOnEscapeKey: !(contentLoader.item?.hasOverlay ?? false)

    property bool _retained: false

    function toggle() {
        if (shouldBeVisible)
            hide();
        else
            show();
    }

    function show() {
        open();
        shouldHaveFocus = true;
        if (!_retained) {
            _retained = true;
            core.refCount += 1;
        }
        Qt.callLater(() => {
            core.refresh();
            contentLoader.item?.takeFocus();
        });
    }

    function hide() {
        Qt.callLater(() => close());
    }

    onDialogClosed: {
        if (_retained) {
            _retained = false;
            core.refCount -= 1;
        }
    }

    content: Component {
        OpenSnitchWindowContent {
            core: modal.core
            onCloseRequested: modal.hide()
        }
    }
}
