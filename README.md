# OpenSnitch for DankMaterialShell

A replacement for the Qt `opensnitch-ui`, as a DMS plugin. **The `opensnitchd`
daemon is untouched**: it keeps connecting to a UI over gRPC, and this plugin is
that UI.

- **Bar icon** (shield; red badge when prompts wait, and crossed when disabled) with a popout: interception
  on/off, system firewall on/off, ask-on-connect on/off and a button to open the big window.
- **Big window**: 
	- An  overview tab with counters and top
  hosts/apps/ports/addresses.
	- A live connection list tab, with search bar and filters (all/allowed/blocked). A click on any entry shows more information.
	- A rule tab, where you can enable, disable, delete, edit and create rules (prompt defaults and daemon options).
	- A firewall tab
	- A settings tab to edit default preferences for authorization dialog and daemon.
- **Authorization prompt**: centered, can't be dismissed without a verdict, with
  the Qt prompt's options: apply to executable / command line / port / IP /
  user / PID / network / host / regex variants, duration (once … forever),
  advanced (destination IP, port, user, checksum), Allow, Deny/Reject, details,
  and the countdown that applies your default. It also warns when the executable's
  MD5 differs from an active rule for that path, and lets you update each affected
  rule after reviewing the change.

## Disclaimer

This project was created entirely by Claude Sonnet 5.5 and ChatGPT 6 Luna. It is provided "as is", without warranties of any kind. Use it at your own risk; the author is not responsible for any damage, data loss, or other issues resulting from its use.

## Requirements

- DankMaterialShell 1.5.0 or newer (composite plugin support).
- The OpenSnitch daemon (`opensnitchd`) installed and running.
- Go 1.25 or newer to build the small UI backend for your machine. The backend
  is deliberately built locally; a prebuilt binary is not included.

## Install
From DankLinux registry:
- Install plugin
- Run `~/.config/DankMaterialShell/plugins/opensnitch/build.sh`
- Make sure the original OpenSnitch UI is not active
- In Settings → Plugins, enable **OpenSnitch**.
- Then in Settings → Bar → Widgets, click on **Add widget**, then select **OpenSnitch**.
- Enjoy!

Or from github (make sure you have git installed):
```sh
git clone https://github.com/equisq/opensnitchDMS.git
cp -r ./opensnitchDMS/ ~/.config/DankMaterialShell/plugins/opensnitch/
~/.config/DankMaterialShell/plugins/opensnitch/build.sh
```
- Make sure the original OpenSnitch UI is not active
- In Settings → Plugins, click **Scan for Plugins** and enable **OpenSnitch**.
- Then in Settings → Bar → Widgets, click on **Add widget**, then select **OpenSnitch**.
- Enjoy!

The daemon must point at the address this plugin listens on. The default is
what opensnitchd ships with (`Server.Address` in
`/etc/opensnitchd/default-config.json`):

```
"Address": "unix:///tmp/osui.sock"
```

If you changed it, set the same value in the plugin's settings.

### Keyboard shortcut
To assign a keyboard shortcut to the main window, you can use ipc commands.
In Settings → Keyboard Shotcuts, click on the **+** button, then click on the **record** button and type your desired shortcut.
In type, select **Shell Command**, and type `dms ipc call opensnitch toggle`.

## How it works

```
opensnitchd ──gRPC──▶ bin/opensnitch-dmsd ──JSON lines──▶ QML plugin
 (unchanged)           (Go; the UI server)   $XDG_RUNTIME_DIR/dms-opensnitch.sock
```

The backend implements the `UI` service from `ui.proto` (Subscribe, Ping,
AskRule, Notifications, PostAlert). Rules are built there, by a port of the Qt
prompt's logic, so the QML only sends the *index* of what you picked. The daemon
keeps and expires rules itself; the backend mirrors them.

With no prompt UI connected (shell not running), or with prompts off, the
backend refuses `AskRule` and the daemon applies its default action.

UI-side preferences live in `~/.local/state/DankMaterialShell/opensnitch/settings.json`.

## IPC

```sh
dms ipc call opensnitch toggle
dms ipc call opensnitch interception off
dms ipc call opensnitch status
```

## Differences from the Qt UI

- No system-firewall *rule editor*, only the on/off switch; no multi-node
  management beyond showing the first online node; no statistics database,
  import/export of rules, or task monitors.
- The prompt always shows on the shell's screen layer; there are no corner
  positions.

## Development

- Build the backend on the target machine with `./build.sh`; the generated
  executable under `bin/` is machine-specific and should not be committed.
- `backend/protocol/ui.pb.go` is generated from `tools/ui.proto` by
  `tools/genpb.py` (plain structs with protobuf tags, so no protoc plugins are
  needed). Re-run it if `ui.proto` changes.
- `tests/e2e_sim.py <binary>` runs the backend against a simulated daemon that
  uses stubs generated from the original proto (`pip install grpcio grpcio-tools`).

## Contributing

Contributions are welcome. Please use this workflow so changes are easy to review:

1. Start from the latest default branch. If you do not have write access, fork the repository first.
2. Create a separate branch for each change. Use a short, descriptive name with a type prefix, such as `feat/add-connection-filter`, `fix/prompt-timeout`, or `docs/update-install-steps`. Do not work directly on the default branch.
3. Make focused changes that follow the style and patterns already used in the project.
4. Test your changes before opening a pull request. For backend or build changes, run `./build.sh` on the target machine. When applicable, run the end-to-end simulator with `tests/e2e_sim.py <path-to-binary>` (it requires `grpcio` and `grpcio-tools`; see Development). For UI changes, also check the affected plugin flow in DankMaterialShell. If a check cannot be run, say why in the pull request.
5. Push your branch and open a pull request against the repository's default branch. Keep each pull request focused on one change and provide enough context for someone else to review it.
6. Respond to review feedback by pushing follow-up commits to the same branch.

### Pull request format

Use this structure in the pull request description:

```markdown
## Summary
<!-- What does this change do, and why? -->

## Changes
<!-- List the main changes. -->

## Testing
<!-- List the checks you ran and their results. If none, explain why. -->

## Checklist
- [ ] The change is focused and follows the existing project style.
- [ ] I tested the change, or explained why testing was not possible.
- [ ] I updated documentation or translations if needed.
- [ ] I checked that no generated or machine-specific build artifacts are included.
```


## Translations

The interface uses DMS `I18n.trFor("opensnitch", ...)` and ships plugin-local catalogs in `translations/`. Available catalogs are `de.json`, `es.json`, `fr.json`, `it.json`, `ja.json`, `nl.json`, `pl.json`, `pt.json`, `ru.json`, `zh_CN.json`, and `zh_TW.json`. They cover German, Spanish, French, Italian, Japanese, Dutch, Polish, Portuguese, Russian, Simplified Chinese, and Traditional Chinese.

Translations were created by AI and may contain mistakes or inaccurate wording. Please check important details against the English source strings. DMS loads the catalog matching the active locale and refreshes plugin strings when the locale changes. English source strings remain the fallback for terms not yet translated in a catalog. Feel free to enhace existing translations or add new languages!

Plugin translations require DMS 1.6.0 or newer.
