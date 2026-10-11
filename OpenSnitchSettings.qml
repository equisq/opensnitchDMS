import QtQuick
import qs.Common
import qs.Modules.Plugins

PluginSettings {
    id: root

    pluginId: "opensnitch"

    StringSetting {
        settingKey: "listenAddress"
        label: I18n.trFor("opensnitch", "Address the daemon connects to")
        description: I18n.trFor("opensnitch", "Must equal Server.Address in /etc/opensnitchd/default-config.json. Restart the shell (or reload the plugin) after changing it.")
        placeholder: "unix:///tmp/osui.sock"
        defaultValue: "unix:///tmp/osui.sock"
    }
}
