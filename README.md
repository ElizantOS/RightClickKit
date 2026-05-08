# RightClickKit

RightClickKit is a personal macOS tool for managing Finder right-click Quick Actions from versioned action files.

The app is intentionally built for one-person use: keep actions in GitHub, edit them in a small SwiftUI app, and install/uninstall Finder workflows without touching Automator by hand. The first built-in action is `Open in Code`, based on the Finder workflow already tested locally.

## Install

```bash
./scripts/install.sh
```

This builds the Swift package, installs:

- CLI: `~/.rightclickkit/bin/rck`
- App: `~/Applications/RightClickKit.app`
- Finder workflows: `~/Library/Services/*.workflow`

Then use Finder:

```text
Right-click a file or folder -> Quick Actions/Services -> Open in Code
```

You can also launch the app:

```bash
open ~/Applications/RightClickKit.app
```

## Uninstall

```bash
./scripts/uninstall.sh
```

The uninstaller removes only workflows marked with:

```text
RightClickKitManaged = true
```

It keeps your repository files and logs.

## CLI

```bash
~/.rightclickkit/bin/rck install --repo "$PWD"
~/.rightclickkit/bin/rck uninstall
~/.rightclickkit/bin/rck list
~/.rightclickkit/bin/rck run open-in-code /path/to/folder
~/.rightclickkit/bin/rck logs open-in-code
```

## Service Format

Each service has a `service.yaml`:

```yaml
id: open-in-code
title: Open in Code
description: Open selected files or folders in the code-compatible editor.
accepts: [file, folder]
shell: /bin/zsh
script: action.zsh
enabled: true
confirm: false
mode: action
action:
  type: openWithCodeEditor
  appName: Cursor
  bundleID:
  codeCommand: /usr/local/bin/code
  terminalApp: Terminal
  command: "pwd && ls -la"
  pathFormat: lines
```

And an executable script, usually `action.zsh`.

For normal use, edit actions through the app instead of editing shell. The
configured action writes the YAML and regenerates `action.zsh` automatically.

Supported action types:

- `openWithApp`
- `openWithCodeEditor`
- `openTerminalHere`
- `copyPaths`
- `runCommand`

Old services without `mode`/`action` are still loaded as `rawScript`.

At runtime, scripts receive:

- `"$@"`: selected Finder paths
- `RCK_SERVICE_ID`: the service id
- `RCK_ITEMS_FILE`: a newline-delimited file of selected paths

The working directory is the selected folder, or the parent folder of the first selected file.

## Development

```bash
./scripts/smoke-test.sh
swift run rck list --repo "$PWD"
swift run RightClickKitApp
```

Logs are written to:

```text
~/Library/Logs/RightClickKit/<service-id>.log
~/Library/Logs/RightClickKit/<service-id>.launcher.log
```

## Project Notes

See `HANDOFF.md` for the detailed development history, architecture decisions,
known limitations, and next steps.
