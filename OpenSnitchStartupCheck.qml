import QtQuick
import qs.Common
import qs.Services

// Gates activation on the backend being built. It is Go, compiled for the
// machine it runs on, so it is not shipped prebuilt.
QtObject {
    function check(done) {
        const dir = PluginService.getPluginPath("opensnitch");
        if (!dir) {
            done({
                "title": I18n.trFor("opensnitch", "OpenSnitch plugin directory not found"),
                "details": I18n.trFor("opensnitch", "The plugin could not locate its own files. Try reinstalling it.")
            });
            return;
        }
        Proc.runCommand("opensnitch.backendCheck", ["test", "-x", dir + "/bin/opensnitch-dmsd"], (stdout, exitCode) => {
            if (exitCode === 0) {
                done(null);
                return;
            }
            done({
                "title": I18n.trFor("opensnitch", "The OpenSnitch backend is not built"),
                "details": I18n.trFor("opensnitch", "Run ./build.sh in %1 (needs Go), then enable this plugin again.").arg(dir)
            });
        });
    }
}
