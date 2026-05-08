# RightClickKit Handoff

Last updated: 2026-05-08

## Project Location

The active source repository has been migrated to:

```text
/Users/echo/projects/RightClickKit
```

The original Codex working copy was:

```text
/Users/echo/Documents/Codex/2026-04-30/automator-macos-vscode-finder-quick-action
```

That older directory is now only a backup/reference copy. Continue development in
`~/projects/RightClickKit`.

## What RightClickKit Is

RightClickKit is a personal macOS utility for managing Finder right-click Quick
Actions without manually building Automator workflows.

The product goal changed during development:

1. Initial goal: make "right-click -> Open in VSCode/Cursor" stable.
2. Broader goal: create a self-use app for managing many Finder right-click
   shortcuts.
3. Current product direction: a "Finder right-click action configurator", not a
   script editor.

The preferred user story is:

```text
Choose action type -> choose app/fill simple options -> save -> install
```

YAML, generated shell, and logs exist, but they should be secondary/advanced
surfaces. The user should not need to understand `$@`, shell quoting, bundle IDs,
or Automator internals for common actions.

## Current Architecture

The project is a pure SwiftPM macOS package. There is no Xcode project.

`Package.swift` defines three products:

- `RightClickKitCore`: shared core library.
- `rck`: CLI helper.
- `RightClickKitApp`: SwiftUI/AppKit macOS app executable.

Important source directories:

- `Sources/RightClickKitCore/`: service models, YAML codec, workflow installer,
  runner, paths, process helpers, script generation.
- `Sources/rck/`: command line entrypoint.
- `Sources/RightClickKitApp/`: SwiftUI app and GUI state.
- `services/`: versioned source of right-click actions.
- `scripts/`: install, uninstall, preview-app, smoke-test scripts.

## Runtime Flow

Finder does not run service business logic directly. Installed workflows are thin
launchers:

```text
Finder Quick Action -> generated .workflow -> ~/.rightclickkit/bin/rck run <service-id> "$@"
```

`rck run` then:

- loads the service from the configured repository,
- accepts Finder-passed paths,
- falls back to Finder selection if no paths arrived,
- writes a temporary newline-delimited `RCK_ITEMS_FILE`,
- chooses a working directory:
  - selected folder -> that folder,
  - selected file -> its parent folder,
  - no item -> repository root,
- injects environment variables,
- executes the service script,
- writes logs.

Environment given to service scripts:

- `"$@"`: selected Finder paths.
- `RCK_SERVICE_ID`: current action ID.
- `RCK_ITEMS_FILE`: temp file containing one path per line.
- `RCK_HELPER`: configured `rck` helper path.
- `RCK_REPOSITORY_ROOT`: configured repository root.
- `PATH`: extended with `/usr/local/bin` and `/opt/homebrew/bin`.

Logs:

- `~/Library/Logs/RightClickKit/<service-id>.log`
- `~/Library/Logs/RightClickKit/<service-id>.launcher.log`

## Files To Know

Core:

- `Sources/RightClickKitCore/Models.swift`
  - `ServiceDefinition`
  - `ServiceMode`
  - `ActionType`
  - `ActionConfig`
  - `CopyPathsFormat`
- `Sources/RightClickKitCore/YAMLServiceCodec.swift`
  - Lightweight YAML load/dump for the project-owned v1 format.
  - Backwards-compatible with old raw script services.
- `Sources/RightClickKitCore/ActionScriptGenerator.swift`
  - Generates `action.zsh` from `ActionConfig`.
- `Sources/RightClickKitCore/WorkflowInstaller.swift`
  - Generates and removes Finder `.workflow` bundles.
  - Only deletes workflows with `RightClickKitManaged=true`.
- `Sources/RightClickKitCore/ServiceRunner.swift`
  - Executes actions and records logs.
- `Sources/RightClickKitCore/ServiceStore.swift`
  - Loads services.
  - Saves YAML/script.
  - Materializes generated scripts before CLI installs.
- `Sources/RightClickKitCore/Paths.swift`
  - Central path policy.

CLI:

- `Sources/rck/main.swift`
  - `install`, `uninstall`, `list`, `run`, `logs`, `config`.

App:

- `Sources/RightClickKitApp/RightClickKitApp.swift`
  - Manual AppKit `NSApplication` entrypoint wrapping SwiftUI.
  - This was used because plain SwiftPM executables are not automatically native
    `.app` bundles.
- `Sources/RightClickKitApp/ContentView.swift`
  - `NavigationSplitView`, sidebar, detail, bottom toolbar.
- `Sources/RightClickKitApp/ActionBuilderView.swift`
  - Main action configuration surface.
- `Sources/RightClickKitApp/AppPickerView.swift`
  - Installed app picker.
- `Sources/RightClickKitApp/Panels.swift`
  - Logs and Advanced panels.
- `Sources/RightClickKitApp/AppModel.swift`
  - App state, saving, install/uninstall, logs, helper repair.
- `Sources/RightClickKitApp/EditableAction.swift`
  - UI-editable wrapper around `ServiceDefinition`.
- `Sources/RightClickKitApp/InstalledAppCatalog.swift`
  - Scans `/Applications` and `~/Applications`.
- `Sources/RightClickKitApp/HighlightedTextEditor.swift`
  - Simple AppKit-backed code highlighting for shell/YAML.

Scripts:

- `scripts/install.sh`
  - Builds release.
  - Installs CLI to `~/.rightclickkit/bin/rck`.
  - Builds app bundle at `~/Applications/RightClickKit.app`.
  - Installs enabled workflows.
- `scripts/uninstall.sh`
  - Removes managed workflows.
  - Removes installed app and CLI.
  - Keeps logs and service source.
- `scripts/preview-app.sh`
  - Builds a preview bundle at `~/Applications/RightClickKitPreview.app`.
  - Copies bundled `rck` into app resources.
  - Writes repository-root config.
- `scripts/smoke-test.sh`
  - Builds package.
  - Uses temp `RIGHTCLICKKIT_HOME`.
  - Installs and uninstalls workflow.
  - Verifies generated plist/wflow files and managed marker.

## Service Format

Services live under:

```text
services/<service-id>/service.yaml
services/<service-id>/action.zsh
```

Current built-in services:

```text
services/analyze-storage/
services/open-in-code/
services/show-directory-tree/
```

`Analyze Storage` opens a native macOS storage analysis window immediately and
scans in the background. The completed view shows a dark radial storage map,
top-level usage bars, and file/folder counts. `--no-open` still generates local
JSON data. `Show Directory Tree` still generates a plain text tree report.

Current YAML model:

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

Supported action types:

- `openWithApp`
- `openWithCodeEditor`
- `openTerminalHere`
- `copyPaths`
- `runCommand`
- `showDirectoryTree`
- `analyzeStorage`

Backwards compatibility:

- Services without `mode`/`action` load as `rawScript`.
- Raw script mode keeps the script editable in Advanced.

## Development Timeline

### 1. Finder Quick Action Prototype

The first practical target was "right-click a folder and open it in VS Code or
Cursor." The initial Automator/XML attempt had a bug where Finder did not pass
paths as expected, so opening worked only after fixing the workflow to pass
Finder paths correctly.

Important lessons:

- `code .` worked from a shell, so the code editor itself was not the problem.
- Finder service input and shell argument passing were the risky part.
- The final stable pattern was to route through a helper and log both launcher
  and service behavior.

### 2. RightClickKit Concept

After the first action worked, the scope expanded into a personal app for
managing many Finder right-click shortcuts.

Product assumptions:

- Current-user install only.
- No sudo required for normal operation.
- Service source is versioned in GitHub under `services/`.
- Installed workflows go to `~/Library/Services`.
- Uninstall must only remove RightClickKit-managed workflows.
- Logs must remain available after uninstall.

### 3. SwiftPM App + CLI Foundation

Swift was chosen over Go/Rust for first version because:

- Native SwiftUI app is easier for macOS-only UX.
- Swift can generate workflows, run subprocesses, and bridge to AppKit when
  needed.
- SwiftPM is enough for this personal app; no Xcode project is required.

The first implementation created:

- core service model,
- YAML loader,
- workflow installer,
- service runner,
- CLI commands,
- preview app bundle script,
- installer/uninstaller scripts.

### 4. Logging And Debugging Improvements

Finder Quick Actions are hard to debug because failures can be silent. The app
now writes two logs:

- launcher log: generated workflow started, paths received, helper existence,
  exit status.
- service log: actual script run, items, script output, exit status.

This fixed the earlier "报错了，但是没有日志" problem.

### 5. Script Editor Rejected

An early GUI showed templates and script editing too prominently. The user
correctly pushed back: even with templates, it still required understanding
which shell lines to edit and which lines to leave alone.

Product decision:

- Default UI should not be a script editor.
- Advanced users may still edit raw scripts, but normal users should configure
  an action by selecting an app/type/options.

### 6. Action Builder Refactor

The UI was refactored around action configuration:

- sidebar renamed to "Right-click Actions",
- detail page centers on Configure,
- action type picker added,
- AppPicker scans installed apps,
- generated script and YAML moved into Advanced,
- logs moved into a collapsible panel,
- raw script mode kept but hidden behind a toggle.

The core model gained:

- `ServiceMode`
- `ActionType`
- `ActionConfig`
- `CopyPathsFormat`
- `ServiceStatus`
- `ActionScriptGenerator`

The CLI install path was also improved so action services can materialize their
generated scripts before workflow install.

## Current Validation Status

Known validation commands:

```bash
./scripts/smoke-test.sh
swift build --disable-sandbox --disable-build-manifest-caching --cache-path .build/cache --scratch-path .build/swiftpm -c release
swift run --disable-sandbox --disable-build-manifest-caching --cache-path .build/cache --scratch-path .build/swiftpm rck list --repo "$PWD"
```

Previous known status before migration:

- smoke test passed,
- release build passed,
- `Open in Code` Finder action worked manually after fixing Finder path passing.

After migration, run the validation commands again from:

```text
/Users/echo/projects/RightClickKit
```

## Known Limitations

- `swift test` is not currently useful because there are no test targets yet.
- YAML parsing is deliberately lightweight and handles the project-owned v1
  format, not full YAML.
- The app can edit existing actions, but the "New Action" flow still needs to be
  made first-class.
- `AppPickerView` is basic:
  - scans `/Applications` and `~/Applications`,
  - shows installed apps,
  - fills app name and bundle ID,
  - still needs better search/favorites and clearer manual override behavior.
- `openTerminalHere` currently uses `open -a <terminal> "$PWD"`.
  - This is okay for Terminal-style apps but may need app-specific AppleScript
    for iTerm/Warp polish.
- `copyPaths` JSON generation is shell-based and should get focused tests for
  quotes, newlines, and backslashes.
- GUI status currently distinguishes installed/not installed/error, but
  "modified" is UI-local and not a content hash comparison with installed
  workflows.
- The app is not signed/notarized for distribution.
- The app is packaged by shell scripts, not a DMG/pkg.

## Recommended Next Steps

High priority:

1. Add a real "New Action" flow in the sidebar toolbar.
2. Redesign Configure forms to be even more choice-driven:
   - app action: one big "Choose App" control, hide bundle ID behind "Manual".
   - code editor: preset buttons for Cursor, VS Code, custom command.
   - terminal: preset buttons for Terminal, iTerm, Warp.
   - copy paths: segmented format picker only.
   - run command: one command field plus clear working-directory note.
3. Add a "Test With..." flow that lets the user pick a folder/file rather than
   relying only on Finder selection fallback.
4. Surface last failure summary above Logs, not only inside raw log text.
5. Add narrow unit tests for:
   - YAML load/dump compatibility,
   - script generation,
   - managed workflow detection,
   - service store materialization.

Medium priority:

1. Add app search to `AppPickerView`.
2. Add action presets.
3. Improve `openTerminalHere` for iTerm/Warp.
4. Add import/export action commands to CLI.
5. Add `rck status` to compare source services with installed workflows.
6. Add `Remove all data` uninstall option, but keep default uninstall safe.

Low priority:

1. Create an app icon.
2. Add signed/notarized packaging.
3. Add GitHub release automation.
4. Consider a menu bar helper if frequent reinstall/test actions become useful.

## Product Design Notes

The guiding product rule is:

```text
The user configures intent, RightClickKit writes shell.
```

Good UI defaults:

- Keep shell hidden.
- Prefer pickers, preset buttons, and segmented controls.
- Manual fields should be secondary.
- Bundle ID should be auto-filled, not asked first.
- Logs should answer "what failed and what should I do next?"
- Install/uninstall should be reversible and obviously safe.

Avoid regressing into:

- a YAML editor,
- a general shell IDE,
- an Automator clone,
- a marketplace before the one-person flow is excellent.

## Git Notes

This project was migrated from a temporary Codex workspace into
`~/projects/RightClickKit` and should be committed there. The initial commit
should include:

- source files,
- service definitions,
- install/uninstall scripts,
- README,
- this handoff.

Do not commit:

- `.build/`,
- local app bundles,
- `~/.rightclickkit`,
- logs,
- generated user workflows from `~/Library/Services`.
