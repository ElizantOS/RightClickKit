# RightClickKit Handoff

Last updated: 2026-05-13

## Active Repository

```text
/Users/echo/projects/RightClickKit
```

Older Codex working copies are reference-only. Continue development in the
project path above.

## Product Shape

RightClickKit is a native macOS productivity toolkit for right-click actions,
local file insight, and a small always-available Agent.

Current pillars:

- Finder Quick Action configuration and installation.
- Native Directory Tree viewer.
- Native Storage Analysis viewer.
- Menu bar Agent with activity, notifications, and companion pet.
- Local project skills under `.agent/skills/` so future features can reuse
  known implementation patterns.

Important product stance:

```text
Configure intent in a native UI. Keep shell, YAML, Automator, and scanner
mechanics behind the curtain unless the user opens Advanced surfaces.
```

## Architecture

This is a pure SwiftPM macOS package. There is no Xcode project.

Products:

- `RightClickKitCore`: shared models, paths, workflow install, script generation,
  activity store, report helpers.
- `rck`: CLI entrypoint for install/run/report/notify/pet commands.
- `RightClickKitApp`: main SwiftUI configuration app.
- `RightClickKitAgent`: accessory process with real `NSStatusItem`, activity
  notifications, and floating pet.
- `RightClickKitStorageView`: native storage analyzer helper.
- `RightClickKitTreeView`: native directory tree helper.

Important folders:

- `Sources/RightClickKitCore/`: shared core logic.
- `Sources/rck/`: CLI.
- `Sources/RightClickKitApp/`: main app.
- `Sources/RightClickKitAgent/`: status bar, activity popover, pet overlay,
  notification bridges.
- `Sources/RightClickKitStorageView/`: progressive storage scanning UI.
- `Sources/RightClickKitTreeView/`: directory tree UI.
- `services/`: versioned right-click action definitions.
- `assets/`: app icon and bundled pet assets.
- `.agent/skills/`: project-local skills for future RightClickKit work.
- `scripts/`: install, preview, uninstall, smoke test.

## Runtime Flows

### Finder Actions

Finder workflows are thin launchers:

```text
Finder Quick Action -> generated .workflow -> ~/.rightclickkit/bin/rck run <service-id> "$@"
```

`rck run` loads service source, resolves Finder paths, writes an
`RCK_ITEMS_FILE`, chooses a working directory, injects environment variables,
runs the generated action script, and writes logs.

### Native Reports

```text
rck report directory-tree /path
rck report storage-analysis /path
```

Without `--no-open`, the CLI launches the native helper app. With `--no-open`,
it writes local report data.

### Agent

The Agent is installed as:

```text
~/Applications/RightClickKit.app/Contents/Helpers/RightClickKitAgent.app
~/Library/LaunchAgents/com.elizantos.RightClickKit.agent.plist
```

Stability decisions:

- Use AppKit `NSStatusItem` as the single system status-bar entry.
- Do not create fake floating status-bar pills or RK/RK1 overlays.
- The pet is a companion/reminder layer, not a second control center.
- Experimental macOS/DingTalk notification bridges stay disabled unless a user
  explicitly enables them.
- `ActivityStore` remains the shared message lane for `rck notify`, Finder
  action status, and Agent UI.

### Pets

Default built-in pet: `rck-dimo`.

Alternate built-in pet: `fireball`.

User pets:

```text
~/.rightclickkit/pets/<pet-id>/
  pet.json
  spritesheet.webp
```

Selected pet:

```text
~/.rightclickkit/current-pet.txt
```

If selection is empty or set to `default`, the Agent uses bundled `rck-dimo`.
`rck pet use fireball` explicitly selects Fireball.

Bundled pet resource:

```text
assets/pets/rck-dimo/rck-dimo-spritesheet.webp
```

`scripts/install.sh` and `scripts/preview-app.sh` copy bundled pet resources into
both the main app Resources and Agent helper Resources.

## CLI Reference

```bash
rck install [--repo PATH] [--rck PATH]
rck uninstall
rck list [--repo PATH]
rck run <service-id> [paths...]
rck logs [service-id]
rck report <directory-tree|storage-analysis> [--no-open] [paths...]
rck action run <action-id> [paths...]
rck notify <title> [--body TEXT] [--level info|success|warning|danger] [--status running|waiting|review|failed|done] [--source NAME] [--id ID]
rck notify list|read|clear
rck pet list|current|use <id|rck-dimo|fireball|default>|install <pet-folder>
rck config
```

## Service Format

Current services:

```text
services/analyze-storage/
services/open-in-code/
services/show-directory-tree/
```

Supported action types:

- `openWithApp`
- `openWithCodeEditor`
- `openTerminalHere`
- `copyPaths`
- `runCommand`
- `showDirectoryTree`
- `analyzeStorage`

Old services without `mode`/`action` load as `rawScript`.

## Project Skills

Project-local skills are part of the architecture.

- `.agent/skills/rightclickkit-action/`: action architecture, right-click
  extension patterns, service semantics.
- `.agent/skills/rightclickkit-pet/`: pet creation, hatch-pet integration,
  bundled/default pet rules, and RCK Dimo lessons.

Use these before implementing similar features. They capture the local
conventions better than the general-purpose skills alone.

## Validation

Run from `/Users/echo/projects/RightClickKit`:

```bash
swift build --disable-sandbox --disable-build-manifest-caching --cache-path .build/cache --scratch-path .build/swiftpm
./scripts/smoke-test.sh
./scripts/install.sh
```

Useful runtime checks:

```bash
~/.rightclickkit/bin/rck pet current
~/.rightclickkit/bin/rck pet list
pgrep -fl RightClickKitAgent
ls -lh ~/Applications/RightClickKit.app/Contents/Helpers/RightClickKitAgent.app/Contents/Resources/rck-dimo-spritesheet.webp
```

Known latest validation:

- `swift build --disable-sandbox --disable-build-manifest-caching --cache-path .build/cache --scratch-path .build/swiftpm` passed.
- `./scripts/smoke-test.sh` passed.
- `./scripts/install.sh` passed.
- `rck pet use default`, `rck pet current`, and `rck pet list` verified
  `rck-dimo` as current default.
- Agent process restarted and is running.

## Known Limitations

- `swift test` is still not useful because there are no test targets.
- YAML parsing is deliberately lightweight and handles the project-owned format,
  not general YAML.
- The app is not signed/notarized for distribution.
- Packaging is shell-script based, not DMG/pkg.
- `ffmpeg` is not guaranteed on local machines; hatch-pet can produce validated
  spritesheets and contact sheets even when mp4 preview rendering fails.
- Experimental global notification ingestion is private/fragile and should stay
  opt-in only.
- Pet states exist, but Agent behavior still needs a proper state/mood mapper so
  `waiting`, `review`, `failed`, `jumping`, and directional running are used
  consistently.

## Recommended Next Steps

High priority:

1. Add `PetMoodController` to map ActivityStore, background tasks, unread count,
   permission state, and pointer/drag state to pet animation rows.
2. Add tests for `rck pet` built-in/default/user-installed behavior.
3. Keep improving Tree and Storage responsiveness with explicit progress and
   cancellation controls.
4. Add a first-class "New Action" flow in the main app.
5. Surface concise failure summaries above logs instead of requiring log reading.

Medium priority:

1. Add app search/favorites to app picking.
2. Add action presets for common apps and terminals.
3. Add `rck status` to compare source services with installed workflows.
4. Add import/export action commands.
5. Add CI coverage for script generation and workflow plist generation.

Low priority:

1. Signed/notarized packaging.
2. Release automation.
3. Optional LaunchAgent/Login Item management UI.

## Git Hygiene

Commit source, service definitions, assets, skills, scripts, and documentation.

Do not commit:

- `.build/`
- `.codex/`
- `tmp/`
- local `.app` bundles
- `~/.rightclickkit`
- logs
- generated workflows from `~/Library/Services`
