---
name: rightclickkit-action
description: Add, refactor, or review RightClickKit Finder right-click actions. Use when creating new services, native helper viewers, script actions, or Codex/local-agent actions for this project, and when deciding how a new capability should fit into the action registry architecture.
---

# RightClickKit Action

## Product Shape

RightClickKit is a Finder-native action platform. Finder Services are only the
entry point; durable behavior should live in `rck`, `RightClickKitCore`, and
native helper apps.

Prefer this path for every new feature:

1. Capture Finder context: selected paths, cwd, file/folder kind, and any cheap metadata.
2. Route through `rck action run <action-id>`.
3. Execute through a typed action entry point.
4. Show complex results in a native macOS helper window.
5. Require explicit user confirmation before destructive writes, deletes, or moves.

## Architecture Map

- `Sources/RightClickKitCore/ActionRegistry.swift`: action manifests, kinds, native tool ids, and metadata.
- `Sources/RightClickKitCore/Models.swift`: service and action config models.
- `Sources/RightClickKitCore/ActionScriptGenerator.swift`: materializes Finder service shell scripts.
- `Sources/rck/main.swift`: CLI routing, including `rck action run`.
- `services/<id>/service.yaml`: user-visible Finder service declaration.
- `Sources/RightClickKit<Feature>View/`: native helper apps for rich analysis tools.
- `scripts/install.sh`: builds and installs the CLI, main app, helper apps, and Finder workflows.

## Choosing An Action Kind

- `builtIn`: simple local behavior such as open app, copy paths, open terminal.
- `script`: shell-only behavior where output can stay in logs or the clipboard.
- `nativeTool`: rich visual analysis with a dedicated SwiftUI/AppKit helper app.
- `agent`: local AI agent/Codex workflow. Start read-only by default.
- `workflow`: multi-step orchestration that combines scanning, agent planning, and native UI.

Do not add a new hardcoded CLI subcommand for every feature. Prefer adding a
manifest and routing through `rck action run <action-id>`.

## Adding A Native Tool Action

1. Add a manifest in `ActionRegistry.builtInManifests`.
2. Add a `NativeToolID` if the tool launches a helper app.
3. Route the id in `rck action run`.
4. Add a helper executable target only when the result needs a native window.
5. Add or update `services/<id>/service.yaml`.
6. Run build, smoke test, and install.

Keep helper apps responsive:

- Run IO and scanning off the main actor.
- Throttle UI refreshes to a visible heartbeat.
- Display partial results early.
- Use AppKit bridges for large virtualized lists or text views.
- Cancel background tasks on window close or rescan.

## Adding An Agent Action

Agent actions should gather context before invoking Codex or another local AI
agent. Useful context includes:

- selected paths
- tree text at a bounded depth
- storage summary for large folders
- git status/diff for repos
- recent files and file type counts

Default to read-only analysis. For changes, show a plan with affected paths and
ask for approval before writing, deleting, or moving files.

## Companion Or Ambient UI Lessons

Codex Desktop's pet is a page/Electron avatar overlay, not a TUI feature. The
useful pattern is a small independent surface that reflects work state without
owning the work itself.

- Keep the companion isolated from the main app window. The page layer renders
  the mascot and notification tray; the desktop shell owns the transparent
  floating window, placement, hit region, drag, and open/close state.
- Drive the mascot from semantic states: `idle`, `running`, `waiting`, `review`,
  `failed`, `waving`, `jumping`, `running-left`, and `running-right`.
- Use a fixed sprite contract for animation. Codex uses an 8 x 9 atlas,
  `192x208` cells, `1536x1872` total size, transparent background, and CSS
  `background-position` frame stepping.
- Keep built-in assets and custom assets behind the same manifest shape:
  id, display name, description, and spritesheet URL/path.
- Persist only lightweight selection/open state. Asset loading and validation
  should be separate from choosing the current companion.
- Map background work to readable notification levels. Running work becomes a
  spinner/running state, waiting input becomes warning/waiting, completed unread
  work becomes success/review, and failures become danger/failed.
- Throttle background polling and expiry. Codex refreshes activity on a heartbeat
  and expires stale running/review/waiting notifications instead of keeping the
  overlay noisy forever.
- Respect reduced motion by showing the first frame of a state instead of
  continuously animating.
- Track overlay actions such as open, close, drag, click, notification open,
  dismiss, and reply separately from the underlying task execution.

For RightClickKit, this maps well to a future native status companion: show scan
and agent state in a separate menu-bar or floating assistant surface, but keep
execution in `rck`, `RightClickKitCore`, and helper apps. The companion should
make background work visible, never become the source of truth.

## Menu Bar And Companion Agent

Long-lived desktop presence belongs in `RightClickKitAgent`, not in the main app
or one-shot helper windows.

- Keep the main `RightClickKitApp` focused on configuration and service editing.
- Keep `RightClickKitStorageView` and `RightClickKitTreeView` as result viewers
  that can be opened and closed independently.
- Use `RightClickKitAgent` for `NSStatusItem` menu bar presence, quick actions,
  and a transparent floating companion panel.
- Install the agent both in `~/.rightclickkit/bin/RightClickKitAgent` and as
  `RightClickKit.app/Contents/Helpers/RightClickKitAgent.app`.
- Make the menu bar extra short and scannable: open app, open native tools,
  toggle companion, open logs, quit.
- Use a borderless non-activating `NSPanel` for the companion so it can float,
  join all spaces, and stay separate from normal document windows.
- Start with a SwiftUI fallback sprite, but keep the renderer compatible with
  the Codex pet atlas contract so a generated `spritesheet.webp` can replace the
  fallback later.

Future work should add a shared status store or notification bus before wiring
real scan/agent progress into the companion. Do not make the overlay poll heavy
scanner state directly.

## Service YAML Rules

Keep `service.yaml` stable and boring:

```yaml
id: review-with-codex
title: Review with Codex
description: Ask the local agent to review the selected folder.
accepts: [folder]
shell: /bin/zsh
script: action.zsh
enabled: true
confirm: false
mode: action
action:
  type: runCommand
  command: "$HOME/.rightclickkit/bin/rck action run review-with-codex \"$@\""
```

For built-in native tools, prefer generated scripts that call:

```zsh
"$rck" action run <action-id> "$@"
```

## Validation

Always run:

```zsh
swift build --disable-sandbox --disable-build-manifest-caching --cache-path .build/cache --scratch-path .build/swiftpm
./scripts/smoke-test.sh
./scripts/install.sh
```

After install, old helper windows do not hot reload. Close and reopen the
Directory Tree or Storage Analysis window before checking UI changes.
