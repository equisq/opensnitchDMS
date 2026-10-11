import QtQuick
import qs.Common
import qs.Modals.Common
import qs.Services

// The centered authorization popup.
//
// It cannot be dismissed: Escape and clicks outside do nothing, like the Qt
// prompt, because closing it without a verdict would leave the application
// hanging. The countdown inside applies the default action.
DankModal {
    id: modal

    required property var core

    layerNamespace: "dms:opensnitch-prompt"

    modalWidth: 580
    modalHeight: 700
    backgroundColor: Theme.surfaceContainer
    cornerRadius: 16
    keepContentLoaded: false
    visible: false
    closeOnEscapeKey: false

    // Newer shells can stack this over another modal (the big window) and
    // draw it above full-screen apps; older ones do not have these knobs.
    Component.onCompleted: {
        if (modal.closeOnBackgroundClick !== undefined)
            modal.closeOnBackgroundClick = false;
        if (modal.allowStacking !== undefined)
            modal.allowStacking = true;
        if (modal.useOverlayLayer !== undefined)
            modal.useOverlayLayer = true;
    }

    function present() {
        if (!modal.shouldBeVisible) {
            modal.open();
            modal.shouldHaveFocus = true;
        }
    }

    function dismiss() {
        if (modal.shouldBeVisible)
            Qt.callLater(() => modal.close());
    }

    Connections {
        target: modal.core

        function onPromptArrived() {
            modal.present();
        }

        function onPromptsChanged() {
            if (modal.core.prompts.length === 0)
                modal.dismiss();
            else
                modal.present();
        }
    }

    content: Component {
        OpenSnitchPromptContent {
            core: modal.core
            onCloseRequested: modal.dismiss()
        }
    }
}
